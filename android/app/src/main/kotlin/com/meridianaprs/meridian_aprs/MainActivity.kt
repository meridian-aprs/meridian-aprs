package com.meridianaprs.meridian_aprs

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var appContext: Context
    private var pendingNavCallsign: String? = null

    companion object {
        const val MAIN_ENGINE_ID = "meridian_main_engine"
        const val CHANNEL = "meridian/notifications"
        private const val CHANNEL_ID_MESSAGES = "messages"
        private const val GROUP_KEY = "meridian_messages"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appContext = applicationContext

        // Capture callsign if the process was cold-started by a notification tap.
        intent?.getStringExtra(MeridianNotificationActionReceiver.EXTRA_CALLSIGN)
            ?.takeIf { it.isNotEmpty() }
            ?.let { pendingNavCallsign = it }

        FlutterEngineCache.getInstance().put(MAIN_ENGINE_ID, flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "postMessageNotification" -> {
                        @Suppress("UNCHECKED_CAST")
                        handlePostMessageNotification(call.arguments as Map<String, Any?>)
                        result.success(null)
                    }
                    "getPendingNavigation" -> {
                        result.success(pendingNavCallsign)
                        pendingNavCallsign = null
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        FlutterEngineCache.getInstance().remove(MAIN_ENGINE_ID)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // Handles notification tap while the app is already running (singleTop reuse).
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val callsign = intent.getStringExtra(MeridianNotificationActionReceiver.EXTRA_CALLSIGN)
        if (callsign.isNullOrEmpty()) return

        val engine = FlutterEngineCache.getInstance().get(MAIN_ENGINE_ID)
        if (engine != null) {
            try {
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("navigateToThread", mapOf("callsign" to callsign))
            } catch (e: Exception) { /* engine detached */ }
        } else {
            pendingNavCallsign = callsign
        }
    }

    private fun handlePostMessageNotification(args: Map<String, Any?>) {
        val callsign = args["callsign"] as? String ?: return
        val notifId = (args["notificationId"] as? Int) ?: return
        @Suppress("UNCHECKED_CAST")
        val messages = args["messages"] as? List<Map<String, Any?>> ?: emptyList()
        val withSound = args["withSound"] as? Boolean ?: true
        val alertOnce = args["alertOnce"] as? Boolean ?: false

        val mePerson = Person.Builder().setName("You").setBot(true).build()
        val peerPerson = Person.Builder().setName(callsign).setBot(true).build()
        val style = NotificationCompat.MessagingStyle(mePerson)
        for (msg in messages) {
            val sender = msg["sender"] as? String
            val text = msg["text"] as? String ?: continue
            val tsMs = when (val ts = msg["timestampMs"]) {
                is Int -> ts.toLong()
                is Long -> ts
                else -> System.currentTimeMillis()
            }
            style.addMessage(text, tsMs, if (sender != null) peerPerson else null)
        }

        // Tap → bring the app to foreground and navigate to the conversation.
        val tapIntent = appContext.packageManager
            .getLaunchIntentForPackage(appContext.packageName)
            ?.apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra(MeridianNotificationActionReceiver.EXTRA_CALLSIGN, callsign)
            } ?: return
        val tapPi = PendingIntent.getActivity(
            appContext, notifId, tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )

        // Inline reply with RemoteInput (FLAG_MUTABLE required for Android 12+).
        val remoteInput = RemoteInput.Builder(MeridianNotificationActionReceiver.KEY_REPLY)
            .setLabel("Reply")
            .build()
        val replyIntent = Intent(MeridianNotificationActionReceiver.ACTION_REPLY).apply {
            setClass(appContext, MeridianNotificationActionReceiver::class.java)
            putExtra(MeridianNotificationActionReceiver.EXTRA_CALLSIGN, callsign)
            putExtra(MeridianNotificationActionReceiver.EXTRA_NOTIFICATION_ID, notifId)
        }
        val replyPi = PendingIntent.getBroadcast(
            appContext, notifId, replyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag()
        )

        // Mark-as-read (request code offset prevents PendingIntent collision with reply PI).
        val markReadIntent = Intent(MeridianNotificationActionReceiver.ACTION_MARK_READ).apply {
            setClass(appContext, MeridianNotificationActionReceiver::class.java)
            putExtra(MeridianNotificationActionReceiver.EXTRA_CALLSIGN, callsign)
            putExtra(MeridianNotificationActionReceiver.EXTRA_NOTIFICATION_ID, notifId)
        }
        val markReadPi = PendingIntent.getBroadcast(
            appContext, notifId + 200_000, markReadIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )

        // Delete intent — fired when the user swipes the notification away.
        val dismissedIntent = Intent(MeridianNotificationActionReceiver.ACTION_DISMISSED).apply {
            setClass(appContext, MeridianNotificationActionReceiver::class.java)
            putExtra(MeridianNotificationActionReceiver.EXTRA_CALLSIGN, callsign)
            putExtra(MeridianNotificationActionReceiver.EXTRA_NOTIFICATION_ID, notifId)
        }
        val dismissedPi = PendingIntent.getBroadcast(
            appContext, notifId + 400_000, dismissedIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )

        val notification = NotificationCompat.Builder(appContext, CHANNEL_ID_MESSAGES)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setStyle(style)
            .setContentIntent(tapPi)
            .setDeleteIntent(dismissedPi)
            .setAutoCancel(false)
            .setGroup(GROUP_KEY)
            .setOnlyAlertOnce(alertOnce)
            .setSilent(!withSound)
            .addAction(NotificationCompat.Action.Builder(0, "Mark as read", markReadPi).build())
            .addAction(
                NotificationCompat.Action.Builder(0, "Reply", replyPi)
                    .addRemoteInput(remoteInput)
                    .setAllowGeneratedReplies(false)
                    .build()
            )
            .build()

        NotificationManagerCompat.from(appContext).notify(notifId, notification)
    }

    private fun immutableFlag() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

    private fun mutableFlag() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
}
