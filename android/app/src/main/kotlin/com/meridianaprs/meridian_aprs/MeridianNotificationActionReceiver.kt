package com.meridianaprs.meridian_aprs

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MeridianNotificationActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_REPLY = "com.meridianaprs.meridian_aprs.NOTIFICATION_REPLY"
        const val ACTION_MARK_READ = "com.meridianaprs.meridian_aprs.NOTIFICATION_MARK_READ"
        const val ACTION_DISMISSED = "com.meridianaprs.meridian_aprs.NOTIFICATION_DISMISSED"
        const val EXTRA_CALLSIGN = "callsign"
        const val EXTRA_NOTIFICATION_ID = "notification_id"
        const val KEY_REPLY = "reply_text"
        const val MAIN_ENGINE_ID = "meridian_main_engine"
        const val CHANNEL = "meridian/notifications"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val callsign = intent.getStringExtra(EXTRA_CALLSIGN) ?: return
        val notifId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        if (notifId < 0) return

        when (intent.action) {
            ACTION_REPLY -> handleReply(intent, callsign, notifId)
            ACTION_MARK_READ -> handleMarkRead(context, callsign, notifId)
            ACTION_DISMISSED -> relayToEngine("handleDismissed", mapOf("callsign" to callsign))
        }
    }

    private fun handleReply(intent: Intent, callsign: String, notifId: Int) {
        val bundle = RemoteInput.getResultsFromIntent(intent) ?: return
        val replyText = bundle.getCharSequence(KEY_REPLY)?.toString()?.trim() ?: return
        if (replyText.isEmpty()) return
        relayToEngine(
            "handleReply",
            mapOf("callsign" to callsign, "text" to replyText, "notificationId" to notifId),
        )
    }

    private fun handleMarkRead(context: Context, callsign: String, notifId: Int) {
        NotificationManagerCompat.from(context).cancel(notifId)
        relayToEngine("handleMarkRead", mapOf("callsign" to callsign))
    }

    private fun relayToEngine(method: String, args: Map<String, Any>) {
        val engine = try {
            FlutterEngineCache.getInstance().get(MAIN_ENGINE_ID) ?: return
        } catch (e: Exception) { return }

        try {
            val messenger = engine.dartExecutor.binaryMessenger
            Handler(Looper.getMainLooper()).post {
                try {
                    MethodChannel(messenger, CHANNEL).invokeMethod(method, args)
                } catch (e: Exception) { /* Engine detached */ }
            }
        } catch (e: Exception) { /* Engine detached */ }
    }
}
