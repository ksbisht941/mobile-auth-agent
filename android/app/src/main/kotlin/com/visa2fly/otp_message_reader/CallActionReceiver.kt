package com.visa2fly.otp_message_reader

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telecom.VideoProfile
import android.util.Log

class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) {
            return
        }

        val callId = intent.getStringExtra(EXTRA_CALL_ID)
        val call = CallControlRegistry.findCall(callId)

        if (call == null) {
            CallNotificationHelper.cancelIncomingCallNotification(context, callId)
            return
        }

        try {
            when (intent.action) {
                ACTION_ANSWER -> {
                    Log.i(AUTO_ANSWER_TAG, "${buildCallLogPrefix(call)} Answer action tapped from notification.")
                    call.answer(VideoProfile.STATE_AUDIO_ONLY)
                }
                ACTION_REJECT -> {
                    Log.i(AUTO_ANSWER_TAG, "${buildCallLogPrefix(call)} Reject action tapped from notification.")
                    call.reject(false, null)
                }
            }
        } catch (error: SecurityException) {
            Log.e(AUTO_ANSWER_TAG, "${buildCallLogPrefix(call)} Call action failed due to permissions.", error)
        } catch (error: Exception) {
            Log.e(AUTO_ANSWER_TAG, "${buildCallLogPrefix(call)} Call action failed.", error)
        } finally {
            CallNotificationHelper.cancelIncomingCallNotification(context, call)
        }
    }

    companion object {
        const val ACTION_ANSWER = "com.visa2fly.otp_message_reader.ACTION_ANSWER_CALL"
        const val ACTION_REJECT = "com.visa2fly.otp_message_reader.ACTION_REJECT_CALL"
        const val EXTRA_CALL_ID = "call_id"
    }
}
