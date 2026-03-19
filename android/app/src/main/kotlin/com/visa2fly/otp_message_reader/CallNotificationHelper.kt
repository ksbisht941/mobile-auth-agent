package com.visa2fly.otp_message_reader

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telecom.Call
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.util.concurrent.ConcurrentHashMap

internal object CallControlRegistry {
    private val callsById = ConcurrentHashMap<String, Call>()

    fun register(call: Call): String {
        val callId = callIdFor(call)
        callsById[callId] = call
        return callId
    }

    fun unregister(call: Call) {
        callsById.remove(callIdFor(call))
    }

    fun findCall(callId: String?): Call? = callId?.let(callsById::get)

    fun callIdFor(call: Call): String = Integer.toHexString(System.identityHashCode(call))
}

object CallNotificationHelper {
    private const val INCOMING_CALL_CHANNEL_ID = "incoming_calls"
    private const val INCOMING_CALL_CHANNEL_NAME = "Incoming calls"
    private const val INCOMING_CALL_CHANNEL_DESCRIPTION =
        "Incoming call controls for answer and reject actions"

    fun showIncomingCallNotification(context: Context, call: Call) {
        if (call.state != Call.STATE_RINGING || !notificationsAllowed(context)) {
            return
        }

        createChannelIfNeeded(context)

        val callId = CallControlRegistry.register(call)
        val notificationId = notificationIdFor(callId)
        val title = "Incoming call"
        val body = call.details.handle?.schemeSpecificPart ?: "Unknown caller"

        val answerIntent =
            PendingIntent.getBroadcast(
                context,
                notificationId * 2,
                Intent(context, CallActionReceiver::class.java)
                    .setAction(CallActionReceiver.ACTION_ANSWER)
                    .putExtra(CallActionReceiver.EXTRA_CALL_ID, callId),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        val rejectIntent =
            PendingIntent.getBroadcast(
                context,
                notificationId * 2 + 1,
                Intent(context, CallActionReceiver::class.java)
                    .setAction(CallActionReceiver.ACTION_REJECT)
                    .putExtra(CallActionReceiver.EXTRA_CALL_ID, callId),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        val contentIntent = launchPendingIntent(context, notificationId)

        val notification =
            NotificationCompat.Builder(context, INCOMING_CALL_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.sym_call_incoming)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .setContentIntent(contentIntent)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Reject", rejectIntent)
                .addAction(android.R.drawable.ic_menu_call, "Answer", answerIntent)
                .build()

        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    fun cancelIncomingCallNotification(context: Context, call: Call) {
        cancelIncomingCallNotification(context, CallControlRegistry.callIdFor(call))
    }

    fun cancelIncomingCallNotification(context: Context, callId: String?) {
        if (callId.isNullOrBlank()) {
            return
        }

        NotificationManagerCompat.from(context).cancel(notificationIdFor(callId))
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

    private fun createChannelIfNeeded(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel =
            NotificationChannel(
                INCOMING_CALL_CHANNEL_ID,
                INCOMING_CALL_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = INCOMING_CALL_CHANNEL_DESCRIPTION
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
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

    private fun notificationIdFor(callId: String): Int = callId.hashCode() and 0x7FFFFFFF
}
