package com.visa2fly.otp_message_reader

import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.provider.BaseColumns
import android.provider.Telephony
import android.telecom.TelecomManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingDialerRoleResult: MethodChannel.Result? = null

    override fun onStart() {
        super.onStart()
        AppRuntimeState.isAppVisible = true
    }

    override fun onStop() {
        AppRuntimeState.isAppVisible = false
        super.onStop()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENTS_CHANNEL_NAME,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    ForegroundSmsEvents.attachSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    ForegroundSmsEvents.detachSink()
                }
            },
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasSmsPermission" -> result.success(hasSmsPermission())
                "requestSmsPermission" -> requestSmsPermission(result)
                "isDefaultDialer" -> result.success(isDefaultDialer())
                "requestDefaultDialerRole" -> requestDefaultDialerRole(result)
                "ensureNotificationPermission" -> {
                    ensureNotificationPermission()
                    result.success(null)
                }
                "loadRuntimeSettings" -> {
                    val config = BackgroundOtpConfigStore.loadConfig(this)
                    result.success(
                        config?.let {
                            hashMapOf<String, Any?>(
                                "senderFilters" to ArrayList(it.senderFilters),
                                "autoHandleEnabled" to it.autoHandleEnabled,
                                "autoAnswerNumbers" to ArrayList(it.autoAnswerNumbers),
                                "autoHangUpDelaySeconds" to it.autoHangUpDelaySeconds,
                                "postAnswerDtmfSteps" to
                                    ArrayList(
                                        it.postAnswerDtmfSteps.map { step ->
                                            hashMapOf<String, Any>(
                                                "digit" to step.digit,
                                                "delaySeconds" to step.delaySeconds,
                                            )
                                        },
                                    ),
                            )
                        },
                    )
                }
                "syncBackgroundApiConfig" -> {
                    val apiBaseUrl = call.argument<String>("apiBaseUrl")?.trim().orEmpty()
                    val apiOrigin = call.argument<String>("apiOrigin")?.trim().orEmpty()
                    val apiReferer = call.argument<String>("apiReferer")?.trim().orEmpty()
                    val visaClientHeaderValue =
                        call.argument<String>("visaClientHeaderValue")?.trim().orEmpty()
                    val senderFilters =
                        call.argument<List<*>>("senderFilters")
                            ?.mapNotNull { it?.toString() }
                            ?: emptyList()
                    val autoHandleEnabled = call.argument<Boolean>("autoHandleEnabled") ?: false
                    val autoHangUpDelaySeconds =
                        call.argument<Number>("autoHangUpDelaySeconds")?.toInt() ?: 20
                    val rawPostAnswerDtmfSteps = call.argument<List<*>>("postAnswerDtmfSteps")
                    val postAnswerDtmfSteps =
                        if (rawPostAnswerDtmfSteps != null) {
                            parsePostAnswerDtmfStepsArgument(rawPostAnswerDtmfSteps)
                        } else {
                            loadLegacyPostAnswerDtmfSteps(call)
                        }
                    val autoAnswerNumbers =
                        call.argument<List<*>>("autoAnswerNumbers")
                            ?.mapNotNull { it?.toString()?.trim()?.takeIf { value -> value.isNotEmpty() } }
                            ?: call.argument<String>("autoAnswerNumber")
                                ?.trim()
                                ?.takeIf { it.isNotEmpty() }
                                ?.let(::listOf)
                                ?: emptyList()

                    if (apiBaseUrl.isEmpty()) {
                        result.error(
                            "invalid_argument",
                            "apiBaseUrl is required.",
                            null,
                        )
                    } else {
                        BackgroundOtpConfigStore.saveConfig(
                            this,
                            apiBaseUrl,
                            apiOrigin,
                            apiReferer,
                            visaClientHeaderValue,
                            senderFilters,
                            autoHandleEnabled,
                            autoAnswerNumbers,
                            autoHangUpDelaySeconds,
                            postAnswerDtmfSteps,
                        )
                        result.success(null)
                    }
                }
                "showApiSuccessNotification" -> {
                    val otpCode = call.argument<String>("otpCode")?.trim().orEmpty()
                    val sender = call.argument<String>("sender")?.trim().orEmpty()
                    val receivedAtLabel = call.argument<String>("receivedAtLabel")?.trim().orEmpty()
                    if (otpCode.isEmpty() || sender.isEmpty() || receivedAtLabel.isEmpty()) {
                        result.error(
                            "invalid_argument",
                            "otpCode, sender, and receivedAtLabel are required.",
                            null,
                        )
                    } else {
                        SmsNotificationHelper.showApiSuccessNotification(
                            this,
                            otpCode,
                            sender,
                            receivedAtLabel,
                        )
                        result.success(null)
                    }
                }
                "appendApiCallHistoryEntry" -> {
                    val otpCode = call.argument<String>("otpCode")?.trim().orEmpty()
                    val sender = call.argument<String>("sender")?.trim().orEmpty()
                    val smsReceivedAtMillis = call.argument<Number>("smsReceivedAtMillis")?.toLong() ?: 0L
                    val apiCalledAtMillis = call.argument<Number>("apiCalledAtMillis")?.toLong() ?: 0L
                    val isSuccess = call.argument<Boolean>("isSuccess")
                    val statusCode = call.argument<Int>("statusCode")
                    val errorMessage = call.argument<String>("errorMessage")?.trim()

                    if (
                        otpCode.isEmpty() ||
                            sender.isEmpty() ||
                            smsReceivedAtMillis <= 0L ||
                            apiCalledAtMillis <= 0L ||
                            isSuccess == null
                    ) {
                        result.error(
                            "invalid_argument",
                            "otpCode, sender, smsReceivedAtMillis, apiCalledAtMillis, and isSuccess are required.",
                            null,
                        )
                    } else {
                        ApiCallHistoryStore.appendEntry(
                            this,
                            otpCode,
                            sender,
                            smsReceivedAtMillis,
                            apiCalledAtMillis,
                            isSuccess,
                            statusCode,
                            errorMessage,
                        )
                        result.success(null)
                    }
                }
                "getApiCallHistory" -> {
                    result.success(ApiCallHistoryStore.readEntries(this))
                }
                "consumePendingBackgroundMessages" -> {
                    result.success(consumePendingBackgroundMessages())
                }
                "consumeBackgroundHandledOtpKeys" -> {
                    result.success(BackgroundHandledOtpStore.consumeHandledKeys(this))
                }
                "readAllMessages" -> {
                    if (!hasSmsPermission()) {
                        result.error(
                            "permission_denied",
                            "READ_SMS permission is required before reading messages.",
                            null,
                        )
                    } else {
                        result.success(readAllMessages())
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        AppRuntimeState.isAppVisible = false
        ForegroundSmsEvents.detachSink()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != READ_SMS_PERMISSION_REQUEST_CODE) {
            if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
                return
            }

            return
        }

        val granted =
            grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }

        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != DEFAULT_DIALER_ROLE_REQUEST_CODE) {
            return
        }

        Log.i(
            TAG,
            "Default dialer role activity finished. resultCode=$resultCode isDefaultDialer=${isDefaultDialer()}",
        )
        pendingDialerRoleResult?.success(isDefaultDialer())
        pendingDialerRoleResult = null
    }

    private fun hasSmsPermission(): Boolean {
        val hasReadPermission =
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) ==
                PackageManager.PERMISSION_GRANTED
        val hasReceivePermission =
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) ==
                PackageManager.PERMISSION_GRANTED

        return hasReadPermission && hasReceivePermission
    }

    private fun requestSmsPermission(result: MethodChannel.Result) {
        if (hasSmsPermission()) {
            result.success(true)
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS),
            READ_SMS_PERMISSION_REQUEST_CODE,
        )
    }

    private fun isDefaultDialer(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return false
        }

        val telecomManager = getSystemService(TELECOM_SERVICE) as? TelecomManager ?: return false
        return telecomManager.defaultDialerPackage == packageName
    }

    private fun requestDefaultDialerRole(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            Log.w(TAG, "Default dialer role is unsupported below Android M.")
            result.success(false)
            return
        }

        if (isDefaultDialer()) {
            Log.i(TAG, "App is already the default dialer.")
            result.success(true)
            return
        }

        if (pendingDialerRoleResult != null) {
            Log.w(TAG, "Default dialer role request ignored because one is already in progress.")
            result.error(
                "request_in_progress",
                "A default phone app request is already in progress.",
                null,
            )
            return
        }

        val requestIntent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = getSystemService(RoleManager::class.java)
                if (roleManager == null) {
                    Log.w(TAG, "RoleManager was unavailable; cannot request ROLE_DIALER.")
                    result.success(false)
                    return
                }

                val isRoleAvailable = roleManager.isRoleAvailable(RoleManager.ROLE_DIALER)
                val isRoleHeld = roleManager.isRoleHeld(RoleManager.ROLE_DIALER)
                Log.i(
                    TAG,
                    "Preparing ROLE_DIALER request. available=$isRoleAvailable held=$isRoleHeld package=$packageName",
                )

                if (!isRoleAvailable) {
                    Log.w(TAG, "ROLE_DIALER is not available on this device.")
                    result.success(false)
                    return
                }
                roleManager.createRequestRoleIntent(RoleManager.ROLE_DIALER)
            } else {
                Log.i(TAG, "Preparing legacy default dialer request for package=$packageName")
                Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER).putExtra(
                    TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME,
                    packageName,
                )
            }

        pendingDialerRoleResult = result

        try {
            Log.i(
                TAG,
                "Launching default dialer request. action=${requestIntent.action} resolved=${requestIntent.resolveActivity(packageManager)}",
            )
            startActivityForResult(requestIntent, DEFAULT_DIALER_ROLE_REQUEST_CODE)
        } catch (error: ActivityNotFoundException) {
            pendingDialerRoleResult = null
            Log.e(TAG, "Android could not open the default phone app request screen.", error)
            result.error(
                "unavailable",
                "Android could not open the default phone app request screen.",
                error.localizedMessage,
            )
        }
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }

        if (
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST_CODE,
        )
    }

    private fun parsePostAnswerDtmfStepsArgument(rawSteps: List<*>): List<PostAnswerDtmfStep> {
        return rawSteps.mapNotNull { rawStep ->
            val stepMap = rawStep as? Map<*, *> ?: return@mapNotNull null
            val digit = normalizeDtmfDigit(stepMap["digit"]?.toString()) ?: return@mapNotNull null
            val delaySeconds =
                when (val rawDelay = stepMap["delaySeconds"]) {
                    is Number -> rawDelay.toInt()
                    else -> rawDelay?.toString()?.trim()?.toIntOrNull() ?: 0
                }

            PostAnswerDtmfStep(
                digit = digit,
                delaySeconds = delaySeconds.coerceAtLeast(0),
            )
        }
    }

    private fun loadLegacyPostAnswerDtmfSteps(call: MethodCall): List<PostAnswerDtmfStep> {
        return listOfNotNull(
            buildLegacyPostAnswerDtmfStep(
                call = call,
                digitKey = "postAnswerFirstDtmfDigit",
                delayKey = "postAnswerFirstDtmfDelaySeconds",
                defaultDigit = "1",
                defaultDelaySeconds = 4,
            ),
            buildLegacyPostAnswerDtmfStep(
                call = call,
                digitKey = "postAnswerSecondDtmfDigit",
                delayKey = "postAnswerSecondDtmfDelaySeconds",
                defaultDigit = "9",
                defaultDelaySeconds = 10,
            ),
        )
    }

    private fun buildLegacyPostAnswerDtmfStep(
        call: MethodCall,
        digitKey: String,
        delayKey: String,
        defaultDigit: String,
        defaultDelaySeconds: Int,
    ): PostAnswerDtmfStep? {
        val digit = normalizeDtmfDigit(call.argument<String>(digitKey) ?: defaultDigit) ?: return null
        val delaySeconds = call.argument<Number>(delayKey)?.toInt() ?: defaultDelaySeconds
        return PostAnswerDtmfStep(
            digit = digit,
            delaySeconds = delaySeconds.coerceAtLeast(0),
        )
    }

    private fun normalizeDtmfDigit(value: String?): String? {
        val normalizedValue = value?.trim().orEmpty().uppercase()
        if (normalizedValue.isEmpty()) {
            return null
        }

        val candidate = normalizedValue.first().toString()
        return candidate.takeIf { it.matches(Regex("[0-9*#A-D]")) }
    }

    private fun consumePendingBackgroundMessages(): Int =
        SmsBackgroundStore.consumePendingMessageCount(this)

    private fun readAllMessages(): List<Map<String, Any?>> {
        val projection = arrayOf(
            BaseColumns._ID,
            Telephony.TextBasedSmsColumns.ADDRESS,
            Telephony.TextBasedSmsColumns.BODY,
            Telephony.TextBasedSmsColumns.DATE,
            Telephony.TextBasedSmsColumns.TYPE,
        )

        val messages = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            projection,
            null,
            null,
            "${Telephony.TextBasedSmsColumns.DATE} DESC",
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(BaseColumns._ID)
            val addressIndex = cursor.getColumnIndexOrThrow(Telephony.TextBasedSmsColumns.ADDRESS)
            val bodyIndex = cursor.getColumnIndexOrThrow(Telephony.TextBasedSmsColumns.BODY)
            val dateIndex = cursor.getColumnIndexOrThrow(Telephony.TextBasedSmsColumns.DATE)
            val typeIndex = cursor.getColumnIndexOrThrow(Telephony.TextBasedSmsColumns.TYPE)

            while (cursor.moveToNext()) {
                messages.add(
                    hashMapOf(
                        "id" to cursor.getLong(idIndex).toString(),
                        "address" to (cursor.getString(addressIndex) ?: "Unknown"),
                        "body" to (cursor.getString(bodyIndex) ?: ""),
                        "date" to cursor.getLong(dateIndex),
                        "type" to cursor.getInt(typeIndex),
                    ),
                )
            }
        }

        return messages
    }

    private companion object {
        const val TAG = "OtpReaderMainActivity"
        const val CHANNEL_NAME = "otp_message_reader/sms_reader"
        const val EVENTS_CHANNEL_NAME = "otp_message_reader/sms_events"
        const val READ_SMS_PERMISSION_REQUEST_CODE = 4010
        const val NOTIFICATION_PERMISSION_REQUEST_CODE = 4011
        const val DEFAULT_DIALER_ROLE_REQUEST_CODE = 4012
    }
}