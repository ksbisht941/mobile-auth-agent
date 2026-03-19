package com.visa2fly.otp_message_reader

import android.Manifest
import android.net.Uri
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.text.format.DateFormat
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Date
import java.util.Locale

private const val BACKGROUND_OTP_TAG = "BackgroundOtp"

class SmsBackgroundReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty()) {
            return
        }

        if (AppRuntimeState.isAppVisible && ForegroundSmsEvents.emit(mergeIncomingMessages(messages))) {
            return
        }

        val pendingResult = goAsync()
        Thread {
            try {
                val handledInBackground = BackgroundOtpProcessor.processIncomingMessages(context, messages)
                SmsBackgroundStore.incrementPendingMessageCount(context, 1)
                if (!AppRuntimeState.isAppVisible && !handledInBackground) {
                    SmsNotificationHelper.showIncomingMessageNotification(context, messages)
                }
            } catch (error: Exception) {
                Log.e(BACKGROUND_OTP_TAG, "Failed to process incoming background SMS.", error)
                SmsBackgroundStore.incrementPendingMessageCount(context, 1)
                if (!AppRuntimeState.isAppVisible) {
                    SmsNotificationHelper.showIncomingMessageNotification(context, messages)
                }
            } finally {
                pendingResult.finish()
            }
        }.start()
    }
}

object AppRuntimeState {
    @Volatile
    var isAppVisible: Boolean = false
}

object ForegroundSmsEvents {
    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    fun attachSink(sink: EventChannel.EventSink) {
        eventSink = sink
    }

    fun detachSink() {
        eventSink = null
    }

    internal fun emit(messages: List<ReceivedSmsPayload>): Boolean {
        if (messages.isEmpty()) {
            return false
        }

        val sink = eventSink ?: return false
        val payload =
            messages.map { message ->
                hashMapOf<String, Any?>(
                    "id" to "foreground|${message.sender.trim().lowercase(Locale.US)}|${message.receivedAtMillis}",
                    "address" to message.sender,
                    "body" to message.body,
                    "date" to message.receivedAtMillis,
                    "type" to Telephony.TextBasedSmsColumns.MESSAGE_TYPE_INBOX,
                )
            }
        mainHandler.post { sink.success(payload) }
        return true
    }
}

data class BackgroundOtpConfig(
    val apiBaseUrl: String,
    val apiOrigin: String,
    val apiReferer: String,
    val visaClientHeaderValue: String,
    val senderFilters: List<String>,
)

internal data class ReceivedSmsPayload(
    val sender: String,
    val body: String,
    val receivedAtMillis: Long,
)

private fun mergeIncomingMessages(
    messages: Array<android.telephony.SmsMessage>,
): List<ReceivedSmsPayload> {
    val groupedMessages = linkedMapOf<String, MutableList<android.telephony.SmsMessage>>()
    for (message in messages) {
        val sender = message.displayOriginatingAddress ?: message.originatingAddress ?: "Unknown"
        val groupKey = "$sender|${message.timestampMillis}"
        groupedMessages.getOrPut(groupKey) { mutableListOf() }.add(message)
    }

    return groupedMessages.values.map { parts ->
        val firstPart = parts.first()
        val sender = firstPart.displayOriginatingAddress ?: firstPart.originatingAddress ?: "Unknown"
        ReceivedSmsPayload(
            sender = sender.ifBlank { "Unknown" },
            body = parts.joinToString(separator = "") { it.messageBody.orEmpty() },
            receivedAtMillis = firstPart.timestampMillis,
        )
    }
}

private data class OtpPayload(
    val sender: String,
    val otpCode: String,
    val receivedAtMillis: Long,
)

private class BackgroundOtpApiException(
    override val message: String,
    val statusCode: Int? = null,
) : Exception(message)

object BackgroundOtpConfigStore {
    private const val PREFERENCES_NAME = "otp_message_reader_background_api"
    private const val KEY_API_BASE_URL = "api_base_url"
    private const val KEY_API_ORIGIN = "api_origin"
    private const val KEY_API_REFERER = "api_referer"
    private const val KEY_VISA_CLIENT_HEADER_VALUE = "visa_client_header_value"
    private const val KEY_SENDER_FILTERS_JSON = "sender_filters_json"

    fun saveConfig(
        context: Context,
        apiBaseUrl: String,
        apiOrigin: String,
        apiReferer: String,
        visaClientHeaderValue: String,
        senderFilters: List<String>,
    ) {
        if (apiBaseUrl.isBlank()) {
            return
        }

        preferences(context)
            .edit()
            .putString(KEY_API_BASE_URL, apiBaseUrl.trim())
            .putString(KEY_API_ORIGIN, apiOrigin.trim())
            .putString(KEY_API_REFERER, apiReferer.trim())
            .putString(KEY_VISA_CLIENT_HEADER_VALUE, visaClientHeaderValue.trim())
            .putString(KEY_SENDER_FILTERS_JSON, stringListToJson(senderFilters))
            .apply()
    }

    fun loadConfig(context: Context): BackgroundOtpConfig? {
        val preferences = preferences(context)
        val apiBaseUrl = preferences.getString(KEY_API_BASE_URL, null)?.trim().orEmpty()
        if (apiBaseUrl.isBlank()) {
            return null
        }

        return BackgroundOtpConfig(
            apiBaseUrl = apiBaseUrl,
            apiOrigin =
                preferences.getString(KEY_API_ORIGIN, "https://visa2fly.com")?.trim().orEmpty(),
            apiReferer =
                preferences.getString(KEY_API_REFERER, "https://visa2fly.com/")?.trim().orEmpty(),
            visaClientHeaderValue =
                preferences.getString(KEY_VISA_CLIENT_HEADER_VALUE, "1")?.trim().orEmpty(),
            senderFilters = jsonToStringList(preferences.getString(KEY_SENDER_FILTERS_JSON, null)),
        )
    }

    private fun stringListToJson(values: List<String>): String {
        val jsonArray = JSONArray()
        values.map { it.trim() }.filter { it.isNotEmpty() }.forEach(jsonArray::put)
        return jsonArray.toString()
    }

    private fun jsonToStringList(rawJson: String?): List<String> {
        if (rawJson.isNullOrBlank()) {
            return emptyList()
        }

        return try {
            val jsonArray = JSONArray(rawJson)
            buildList {
                for (index in 0 until jsonArray.length()) {
                    val item = jsonArray.optString(index).trim()
                    if (item.isNotEmpty()) {
                        add(item)
                    }
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
}

object BackgroundHandledOtpStore {
    private const val PREFERENCES_NAME = "otp_message_reader_background_api_handled"
    private const val KEY_HANDLED_KEYS_JSON = "handled_keys_json"

    fun appendHandledKeys(context: Context, keys: Collection<String>) {
        if (keys.isEmpty()) {
            return
        }

        val existingKeys = loadKeys(preferences(context).getString(KEY_HANDLED_KEYS_JSON, null))
        keys.map { it.trim() }.filter { it.isNotEmpty() }.forEach(existingKeys::add)
        preferences(context).edit().putString(KEY_HANDLED_KEYS_JSON, keysToJson(existingKeys)).apply()
    }

    fun consumeHandledKeys(context: Context): List<String> {
        val preferences = preferences(context)
        val keys = loadKeys(preferences.getString(KEY_HANDLED_KEYS_JSON, null))
        if (keys.isNotEmpty()) {
            preferences.edit().remove(KEY_HANDLED_KEYS_JSON).apply()
        }
        return keys
    }

    private fun loadKeys(rawJson: String?): MutableList<String> {
        if (rawJson.isNullOrBlank()) {
            return mutableListOf()
        }

        return try {
            val jsonArray = JSONArray(rawJson)
            mutableListOf<String>().apply {
                for (index in 0 until jsonArray.length()) {
                    val item = jsonArray.optString(index).trim()
                    if (item.isNotEmpty()) {
                        add(item)
                    }
                }
            }
        } catch (_: Exception) {
            mutableListOf()
        }
    }

    private fun keysToJson(keys: List<String>): String {
        val jsonArray = JSONArray()
        keys.forEach(jsonArray::put)
        return jsonArray.toString()
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
}

object BackgroundOtpProcessor {
    private val keywords =
        listOf(
            "otp",
            "code",
            "verification",
            "verify",
            "passcode",
            "authentication",
            "auth code",
            "security code",
            "login code",
            "one-time password",
        )
    private val candidateCodePattern = Regex("[0-9][0-9\\-\\s]{2,10}[0-9]")
    private val nonDigitPattern = Regex("[^0-9]")

    fun processIncomingMessages(
        context: Context,
        messages: Array<android.telephony.SmsMessage>,
    ): Boolean {
        val config = BackgroundOtpConfigStore.loadConfig(context)
        if (config == null) {
            Log.i(BACKGROUND_OTP_TAG, "Skipped background OTP sync because config was unavailable.")
            return false
        }

        val matches = mergeIncomingMessages(messages).mapNotNull { matchPayload(it, config.senderFilters) }
        if (matches.isEmpty()) {
            Log.i(BACKGROUND_OTP_TAG, "Skipped background OTP sync because no OTP match was found.")
            return false
        }

        BackgroundHandledOtpStore.appendHandledKeys(context, matches.map(::buildMatchKey))
        val latestMatch = matches.maxByOrNull { it.receivedAtMillis } ?: return false
        val apiCalledAtMillis = System.currentTimeMillis()

        return try {
            val statusCode = sendLatestOtp(latestMatch.otpCode, config)
            ApiCallHistoryStore.appendEntry(
                context,
                latestMatch.otpCode,
                latestMatch.sender,
                latestMatch.receivedAtMillis,
                apiCalledAtMillis,
                true,
                statusCode,
                null,
            )
            SmsNotificationHelper.showApiSuccessNotification(
                context,
                latestMatch.otpCode,
                latestMatch.sender,
                formatReceivedAtLabel(context, latestMatch.receivedAtMillis),
            )
            Log.i(
                BACKGROUND_OTP_TAG,
                "Sent background OTP ${latestMatch.otpCode} to the API successfully.",
            )
            true
        } catch (error: BackgroundOtpApiException) {
            ApiCallHistoryStore.appendEntry(
                context,
                latestMatch.otpCode,
                latestMatch.sender,
                latestMatch.receivedAtMillis,
                apiCalledAtMillis,
                false,
                error.statusCode,
                error.message,
            )
            Log.w(
                BACKGROUND_OTP_TAG,
                "Background OTP API sync failed: ${error.message}",
                error,
            )
            true
        }
    }

    private fun matchPayload(
        payload: ReceivedSmsPayload,
        senderFilters: List<String>,
    ): OtpPayload? {
        val normalizedBody = payload.body.lowercase(Locale.US)
        if (keywords.none(normalizedBody::contains)) {
            return null
        }

        if (senderFilters.isNotEmpty()) {
            val normalizedSender = payload.sender.lowercase(Locale.US)
            val matchesSender =
                senderFilters.map { it.trim().lowercase(Locale.US) }
                    .filter { it.isNotEmpty() }
                    .any(normalizedSender::contains)
            if (!matchesSender) {
                return null
            }
        }

        val otpCode = extractOtpCode(payload.body) ?: return null
        return OtpPayload(
            sender = payload.sender,
            otpCode = otpCode,
            receivedAtMillis = payload.receivedAtMillis,
        )
    }

    private fun extractOtpCode(body: String): String? {
        for (match in candidateCodePattern.findAll(body)) {
            val digitsOnly = nonDigitPattern.replace(match.value, "")
            if (digitsOnly.length in 4..8) {
                return digitsOnly
            }
        }

        return null
    }

    private fun buildMatchKey(match: OtpPayload): String =
        "${match.sender.trim().lowercase(Locale.US)}|${match.otpCode}|${match.receivedAtMillis}"

    private fun sendLatestOtp(
        otpCode: String,
        config: BackgroundOtpConfig,
    ): Int {
        val requestUri = buildLatestOtpUri(otpCode, config)
        val connection = (URL(requestUri.toString()).openConnection() as HttpURLConnection)
        connection.requestMethod = "GET"
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        connection.setRequestProperty("origin", config.apiOrigin)
        connection.setRequestProperty("referer", config.apiReferer)
        connection.setRequestProperty("visa-client", config.visaClientHeaderValue)

        return try {
            val statusCode = connection.responseCode
            if (statusCode !in 200..299) {
                throw BackgroundOtpApiException("API request failed ($statusCode).", statusCode)
            }
            statusCode
        } catch (error: BackgroundOtpApiException) {
            throw error
        } catch (error: Exception) {
            throw BackgroundOtpApiException(
                "Could not reach OTP API: ${error.message ?: error.javaClass.simpleName}",
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun buildLatestOtpUri(otpCode: String, config: BackgroundOtpConfig): Uri {
        val baseUri = Uri.parse(config.apiBaseUrl)
        val builder = Uri.Builder().scheme(baseUri.scheme).encodedAuthority(baseUri.encodedAuthority)
        baseUri.pathSegments.filter { it.isNotEmpty() }.forEach(builder::appendPath)
        builder.appendPath("fetch")
        builder.appendPath("latest")
        builder.appendPath("otp")
        builder.appendQueryParameter("otp", otpCode)
        return builder.build()
    }

    private fun formatReceivedAtLabel(context: Context, receivedAtMillis: Long): String {
        val receivedAt = Date(receivedAtMillis)
        val dateText = DateFormat.getMediumDateFormat(context).format(receivedAt)
        val timeText = DateFormat.getTimeFormat(context).format(receivedAt)
        return "$dateText, $timeText"
    }
}

object SmsBackgroundStore {
    private const val PREFERENCES_NAME = "otp_message_reader_background_sms"
    private const val KEY_PENDING_MESSAGE_COUNT = "pending_message_count"

    fun incrementPendingMessageCount(context: Context, count: Int) {
        if (count <= 0) {
            return
        }

        val preferences = preferences(context)
        val currentCount = preferences.getInt(KEY_PENDING_MESSAGE_COUNT, 0)
        preferences.edit().putInt(KEY_PENDING_MESSAGE_COUNT, currentCount + count).apply()
    }

    fun consumePendingMessageCount(context: Context): Int {
        val preferences = preferences(context)
        val currentCount = preferences.getInt(KEY_PENDING_MESSAGE_COUNT, 0)

        if (currentCount > 0) {
            preferences.edit().putInt(KEY_PENDING_MESSAGE_COUNT, 0).apply()
        }

        return currentCount
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
}

object ApiCallHistoryStore {
    private const val PREFERENCES_NAME = "otp_message_reader_api_history"
    private const val KEY_ENTRIES_JSON = "entries_json"
    private const val MAX_ENTRIES = 50

    fun appendEntry(
        context: Context,
        otpCode: String,
        sender: String,
        smsReceivedAtMillis: Long,
        apiCalledAtMillis: Long,
        isSuccess: Boolean,
        statusCode: Int?,
        errorMessage: String?,
    ) {
        if (
            otpCode.isBlank() ||
                sender.isBlank() ||
                smsReceivedAtMillis <= 0L ||
                apiCalledAtMillis <= 0L
        ) {
            return
        }

        val entries = loadEntries(preferences(context).getString(KEY_ENTRIES_JSON, null))
        entries.put(
            JSONObject().apply {
                put("otpCode", otpCode)
                put("sender", sender)
                put("smsReceivedAtMillis", smsReceivedAtMillis)
                put("apiCalledAtMillis", apiCalledAtMillis)
                put("isSuccess", isSuccess)
                if (statusCode != null) {
                    put("statusCode", statusCode)
                }
                if (!errorMessage.isNullOrBlank()) {
                    put("errorMessage", errorMessage)
                }
            },
        )

        while (entries.length() > MAX_ENTRIES) {
            entries.remove(0)
        }

        preferences(context).edit().putString(KEY_ENTRIES_JSON, entries.toString()).apply()
    }

    fun readEntries(context: Context): List<Map<String, Any>> {
        val entries = loadEntries(preferences(context).getString(KEY_ENTRIES_JSON, null))
        val results = mutableListOf<Map<String, Any>>()

        for (index in entries.length() - 1 downTo 0) {
            val item = entries.optJSONObject(index) ?: continue
            val entry = mutableMapOf<String, Any>(
                "otpCode" to item.optString("otpCode"),
                "sender" to item.optString("sender", "Unknown"),
                "smsReceivedAtMillis" to item.optLong("smsReceivedAtMillis"),
                "apiCalledAtMillis" to item.optLong("apiCalledAtMillis"),
                "isSuccess" to item.optBoolean("isSuccess"),
            )

            if (item.has("statusCode")) {
                entry["statusCode"] = item.optInt("statusCode")
            }

            val errorMessage = item.optString("errorMessage")
            if (errorMessage.isNotBlank()) {
                entry["errorMessage"] = errorMessage
            }

            results.add(entry)
        }

        return results
    }

    private fun loadEntries(rawEntriesJson: String?): JSONArray {
        if (rawEntriesJson.isNullOrBlank()) {
            return JSONArray()
        }

        return try {
            JSONArray(rawEntriesJson)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
}

object SmsNotificationHelper {
    private const val INCOMING_SMS_CHANNEL_ID = "incoming_sms_messages"
    private const val INCOMING_SMS_CHANNEL_NAME = "Incoming SMS"
    private const val INCOMING_SMS_CHANNEL_DESCRIPTION =
        "Notifications for newly received SMS messages"
    private const val API_SUCCESS_CHANNEL_ID = "otp_api_success"
    private const val API_SUCCESS_CHANNEL_NAME = "OTP API Success"
    private const val API_SUCCESS_CHANNEL_DESCRIPTION =
        "Notifications when OTPs are sent to the API successfully"

    fun showIncomingMessageNotification(
        context: Context,
        messages: Array<android.telephony.SmsMessage>,
    ) {
        if (messages.isEmpty() || !notificationsAllowed(context)) {
            return
        }

        createChannelIfNeeded(
            context,
            INCOMING_SMS_CHANNEL_ID,
            INCOMING_SMS_CHANNEL_NAME,
            INCOMING_SMS_CHANNEL_DESCRIPTION,
        )

        val pendingIntent = launchPendingIntent(context, messages.first().timestampMillis.toInt())

        val contentTitle = notificationTitle(messages)
        val contentBody = notificationBody(messages)
        val notification =
            NotificationCompat.Builder(context, INCOMING_SMS_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(contentTitle)
                .setContentText(contentBody)
                .setStyle(NotificationCompat.BigTextStyle().bigText(contentBody))
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(pendingIntent)
                .build()

        NotificationManagerCompat.from(context).notify(nextNotificationId(messages), notification)
    }

    fun showApiSuccessNotification(
        context: Context,
        otpCode: String,
        sender: String,
        receivedAtLabel: String,
    ) {
        if (
            otpCode.isBlank() ||
                sender.isBlank() ||
                receivedAtLabel.isBlank() ||
                !notificationsAllowed(context)
        ) {
            return
        }

        createChannelIfNeeded(
            context,
            API_SUCCESS_CHANNEL_ID,
            API_SUCCESS_CHANNEL_NAME,
            API_SUCCESS_CHANNEL_DESCRIPTION,
        )

        val pendingIntent = launchPendingIntent(context, nextNotificationId())
        val contentTitle = "OTP $otpCode sent to API"
        val contentBody = "From $sender • Received $receivedAtLabel"
        val expandedBody =
            "OTP $otpCode from $sender, received on $receivedAtLabel, was sent to the API successfully."
        val notification =
            NotificationCompat.Builder(context, API_SUCCESS_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(contentTitle)
                .setContentText(contentBody)
                .setStyle(NotificationCompat.BigTextStyle().bigText(expandedBody))
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(pendingIntent)
                .build()

        NotificationManagerCompat.from(context).notify(nextNotificationId(), notification)
    }

    private fun notificationsAllowed(context: Context): Boolean {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                    PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    private fun createChannelIfNeeded(
        context: Context,
        channelId: String,
        channelName: String,
        channelDescription: String,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel =
            NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = channelDescription }
        manager.createNotificationChannel(channel)
    }

    private fun launchPendingIntent(context: Context, requestCode: Int): PendingIntent? {
        val launchIntent =
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }

        return launchIntent?.let {
            PendingIntent.getActivity(
                context,
                requestCode,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }

    private fun notificationTitle(messages: Array<android.telephony.SmsMessage>): String {
        if (messages.size > 1) {
            return "${messages.size} new SMS messages"
        }

        return "New SMS from ${messages.first().displayOriginatingAddress ?: messages.first().originatingAddress ?: "Unknown"}"
    }

    private fun notificationBody(messages: Array<android.telephony.SmsMessage>): String {
        if (messages.size > 1) {
            return "Open Mobile Auth Agent to review the latest messages."
        }

        val messageBody = messages.first().messageBody?.trim().orEmpty()
        return if (messageBody.isEmpty()) {
            "Open Mobile Auth Agent to review the latest message."
        } else {
            messageBody
        }
    }

    private fun nextNotificationId(messages: Array<android.telephony.SmsMessage>): Int {
        val timestamp = messages.first().timestampMillis
        return (timestamp and 0x7FFFFFFF).toInt()
    }

    private fun nextNotificationId(): Int = (System.currentTimeMillis() and 0x7FFFFFFF).toInt()
}