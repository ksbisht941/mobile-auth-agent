package com.visa2fly.otp_message_reader

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.provider.BaseColumns
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null

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
                "ensureNotificationPermission" -> {
                    ensureNotificationPermission()
                    result.success(null)
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
        const val CHANNEL_NAME = "otp_message_reader/sms_reader"
        const val EVENTS_CHANNEL_NAME = "otp_message_reader/sms_events"
        const val READ_SMS_PERMISSION_REQUEST_CODE = 4010
        const val NOTIFICATION_PERMISSION_REQUEST_CODE = 4011
    }
}