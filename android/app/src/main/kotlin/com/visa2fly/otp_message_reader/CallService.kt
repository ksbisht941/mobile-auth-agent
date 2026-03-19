package com.visa2fly.otp_message_reader

import android.os.Handler
import android.os.Looper
import android.telecom.Call
import android.telecom.InCallService
import android.telecom.VideoProfile
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal const val AUTO_ANSWER_TAG = "AutoAnswerCall"
private const val AUTO_ANSWER_DELAY_MS = 3_000L
private const val DTMF_TONE_DURATION_MS = 250L

class CallService : InCallService() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val callCallbacks = mutableMapOf<Call, Call.Callback>()
    private val autoAnsweredCalls = mutableSetOf<Call>()
    private val dtmfScheduledCalls = mutableSetOf<Call>()
    private val disconnectScheduledCalls = mutableSetOf<Call>()
    private val pendingAnswerActions = mutableMapOf<Call, Runnable>()
    private val scheduledActions = mutableMapOf<Call, MutableList<Runnable>>()

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        CallControlRegistry.register(call)
        registerCallback(call)
        evaluateCall(call)
    }

    override fun onCallRemoved(call: Call) {
        clearCallState(call)
        unregisterCallback(call)
        super.onCallRemoved(call)
    }

    private fun registerCallback(call: Call) {
        if (callCallbacks.containsKey(call)) {
            return
        }

        val callback =
            object : Call.Callback() {
                override fun onStateChanged(call: Call, state: Int) {
                    if (state == Call.STATE_DISCONNECTED || state == Call.STATE_DISCONNECTING) {
                        clearCallState(call)
                        unregisterCallback(call)
                        return
                    }

                    evaluateCall(call)
                }

                override fun onDetailsChanged(call: Call, details: Call.Details) {
                    evaluateCall(call)
                }
            }

        call.registerCallback(callback)
        callCallbacks[call] = callback
    }

    private fun unregisterCallback(call: Call) {
        callCallbacks.remove(call)?.let(call::unregisterCallback)
    }

    private fun evaluateCall(call: Call) {
        when (call.state) {
            Call.STATE_RINGING -> {
                CallNotificationHelper.showIncomingCallNotification(this, call)
                evaluateRingingCall(call)
            }
            Call.STATE_ACTIVE -> {
                CallNotificationHelper.cancelIncomingCallNotification(this, call)
                cancelPendingAutoAnswer(call)
                scheduleDtmfSequenceIfNeeded(call)
                scheduleAutoDisconnectIfNeeded(call)
            }
            else -> {
                CallNotificationHelper.cancelIncomingCallNotification(this, call)
                cancelPendingAutoAnswer(call)
            }
        }
    }

    private fun evaluateRingingCall(call: Call) {
        val config = BackgroundOtpConfigStore.loadConfig(this) ?: return
        if (!config.autoHandleEnabled) {
            return
        }
        val targetNumbers = config.autoAnswerNumbers.mapNotNull(::normalizePhoneNumber).distinct()
        if (targetNumbers.isEmpty()) {
            return
        }
        val incomingNumber = normalizePhoneNumber(call.details.handle?.schemeSpecificPart) ?: return

        if (incomingNumber !in targetNumbers) {
            return
        }

        if (autoAnsweredCalls.contains(call) || pendingAnswerActions.containsKey(call)) {
            return
        }

        logInfo(call, "Scheduling auto-answer in 3 seconds for a configured incoming call.")

        val action =
            Runnable {
                pendingAnswerActions.remove(call)

                if (call.state != Call.STATE_RINGING) {
                    logInfo(call, "Skipping auto-answer because the call is no longer ringing.")
                    return@Runnable
                }

                if (!autoAnsweredCalls.add(call)) {
                    return@Runnable
                }

                logInfo(call, "Auto-answering a configured incoming call.")

                try {
                    call.answer(VideoProfile.STATE_AUDIO_ONLY)
                } catch (error: SecurityException) {
                    autoAnsweredCalls.remove(call)
                    logError(call, "Android denied the auto-answer request.", error)
                } catch (error: Exception) {
                    autoAnsweredCalls.remove(call)
                    logError(call, "Failed to auto-answer the incoming call.", error)
                }
            }

        pendingAnswerActions[call] = action
        mainHandler.postDelayed(action, AUTO_ANSWER_DELAY_MS)
    }

    private fun scheduleDtmfSequenceIfNeeded(call: Call) {
        if (!autoAnsweredCalls.contains(call) || !dtmfScheduledCalls.add(call)) {
            return
        }

        val config = BackgroundOtpConfigStore.loadConfig(this)
        val configuredSteps =
            (config?.postAnswerDtmfSteps
                ?: listOf(
                    PostAnswerDtmfStep(digit = "1", delaySeconds = 4),
                    PostAnswerDtmfStep(digit = "9", delaySeconds = 10),
                )).mapNotNull { step ->
                buildDtmfStep(step.digit, step.delaySeconds)
            }

        if (configuredSteps.isEmpty()) {
            logInfo(call, "Post-answer DTMF sequence is disabled for configured calls.")
            return
        }

        logInfo(
            call,
            "Scheduling post-answer DTMF sequence: ${configuredSteps.joinToString { "${it.digit} @ ${it.delaySeconds}s" }}.",
        )
        configuredSteps.forEach { step ->
            scheduleDtmfTone(call, step.digit, step.delaySeconds * 1_000L)
        }
    }

    private fun buildDtmfStep(digitValue: String?, delaySeconds: Int): ConfiguredDtmfStep? {
        val normalizedDigit = normalizeDtmfDigit(digitValue) ?: return null
        return ConfiguredDtmfStep(normalizedDigit, delaySeconds.coerceAtLeast(0))
    }

    private fun normalizeDtmfDigit(value: String?): Char? {
        val normalizedValue = value?.trim().orEmpty().uppercase(Locale.US)
        if (normalizedValue.isEmpty()) {
            return null
        }

        val candidate = normalizedValue.first()
        return if (candidate in "0123456789*#ABCD") candidate else null
    }

    private fun scheduleDtmfTone(call: Call, digit: Char, delayMillis: Long) {
        val action =
            Runnable {
                if (call.state != Call.STATE_ACTIVE) {
                    logInfo(call, "Skipping DTMF $digit because the call is no longer active.")
                    return@Runnable
                }

                try {
                    logInfo(call, "Sending DTMF tone: $digit")
                    call.playDtmfTone(digit)
                    mainHandler.postDelayed(
                        {
                            try {
                                call.stopDtmfTone()
                            } catch (error: Exception) {
                                logError(call, "Failed to stop DTMF tone: $digit", error)
                            }
                        },
                        DTMF_TONE_DURATION_MS,
                    )
                } catch (error: SecurityException) {
                    logError(call, "Android denied the DTMF request for: $digit", error)
                } catch (error: Exception) {
                    logError(call, "Failed to send DTMF tone: $digit", error)
                }
            }

        scheduledActions.getOrPut(call) { mutableListOf() }.add(action)
        mainHandler.postDelayed(action, delayMillis)
    }

    private fun scheduleAutoDisconnectIfNeeded(call: Call) {
        if (!autoAnsweredCalls.contains(call) || !disconnectScheduledCalls.add(call)) {
            return
        }

        val config = BackgroundOtpConfigStore.loadConfig(this)
        val autoHangUpDelaySeconds = config?.autoHangUpDelaySeconds ?: 20
        if (autoHangUpDelaySeconds <= 0) {
            logInfo(call, "Automatic disconnect is disabled for configured calls.")
            return
        }

        val delayMillis = autoHangUpDelaySeconds * 1_000L

        logInfo(call, "Scheduling automatic disconnect in $autoHangUpDelaySeconds seconds.")

        val action =
            Runnable {
                if (call.state != Call.STATE_ACTIVE) {
                    logInfo(call, "Skipping automatic disconnect because the call is no longer active.")
                    return@Runnable
                }

                try {
                    logInfo(call, "Disconnecting auto-answered call after $autoHangUpDelaySeconds seconds.")
                    call.disconnect()
                } catch (error: SecurityException) {
                    logError(call, "Android denied the disconnect request.", error)
                } catch (error: Exception) {
                    logError(call, "Failed to disconnect the auto-answered call.", error)
                }
            }

        scheduledActions.getOrPut(call) { mutableListOf() }.add(action)
        mainHandler.postDelayed(action, delayMillis)
    }

    private fun clearCallState(call: Call) {
        cancelPendingAutoAnswer(call)
        CallNotificationHelper.cancelIncomingCallNotification(this, call)
        CallControlRegistry.unregister(call)
        scheduledActions.remove(call)?.forEach(mainHandler::removeCallbacks)
        dtmfScheduledCalls.remove(call)
        disconnectScheduledCalls.remove(call)
        autoAnsweredCalls.remove(call)
    }

    private fun cancelPendingAutoAnswer(call: Call) {
        pendingAnswerActions.remove(call)?.let(mainHandler::removeCallbacks)
    }
}

private data class ConfiguredDtmfStep(
    val digit: Char,
    val delaySeconds: Int,
)

private fun logInfo(call: Call, message: String) {
    Log.i(AUTO_ANSWER_TAG, "${buildCallLogPrefix(call)} $message")
}

private fun logError(call: Call, message: String, error: Throwable) {
    Log.e(AUTO_ANSWER_TAG, "${buildCallLogPrefix(call)} $message", error)
}

internal fun buildCallLogPrefix(call: Call): String {
    val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
    val rawNumber = call.details.handle?.schemeSpecificPart ?: "unknown"
    val normalizedNumber = normalizePhoneNumber(rawNumber) ?: "unknown"
    val stateLabel = callStateLabel(call.state)
    return "[$timestamp] [state=$stateLabel] [number=$rawNumber] [normalized=$normalizedNumber]"
}

private fun callStateLabel(state: Int): String =
    when (state) {
        Call.STATE_NEW -> "NEW"
        Call.STATE_DIALING -> "DIALING"
        Call.STATE_RINGING -> "RINGING"
        Call.STATE_HOLDING -> "HOLDING"
        Call.STATE_ACTIVE -> "ACTIVE"
        Call.STATE_DISCONNECTED -> "DISCONNECTED"
        Call.STATE_SELECT_PHONE_ACCOUNT -> "SELECT_PHONE_ACCOUNT"
        Call.STATE_CONNECTING -> "CONNECTING"
        Call.STATE_DISCONNECTING -> "DISCONNECTING"
        else -> "UNKNOWN($state)"
    }

private fun normalizePhoneNumber(rawNumber: String?): String? {
    val digitsOnly = rawNumber.orEmpty().replace(Regex("[^0-9]"), "")
    return digitsOnly.takeIf { it.isNotEmpty() }
}