package dev.flutter.continued_task

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground Service that holds process lifecycle continuation
 * and displays an ongoing notification during long-running tasks.
 */
class ContinuedTaskForegroundService : Service() {

    companion object {
        const val ACTION_START = "dev.flutter.continued_task.START"
        const val ACTION_UPDATE = "dev.flutter.continued_task.UPDATE"
        const val ACTION_STOP = "dev.flutter.continued_task.STOP"
        const val ACTION_USER_CANCEL = "dev.flutter.continued_task.USER_CANCEL"

        const val EXTRA_TASK_ID = "taskId"
        const val EXTRA_TITLE = "title"
        const val EXTRA_SUBTITLE = "subtitle"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_MAX_PROGRESS = "maxProgress"
        const val EXTRA_INDETERMINATE = "indeterminate"
        const val EXTRA_ALLOW_CANCEL = "allowCancel"
        const val EXTRA_CANCEL_LABEL = "cancelActionLabel"
        const val EXTRA_ICON = "iconResource"
        const val EXTRA_CHANNEL_ID = "channelId"
        const val EXTRA_CHANNEL_NAME = "channelName"
        const val EXTRA_CHANNEL_DESC = "channelDescription"

        private const val NOTIFICATION_ID = 54321

        const val PREFS_NAME = "continued_task_prefs"
        const val KEY_STOP_REQUESTED = "stop_requested_while_detached"

        /** Service -> Dart event listener */
        @JvmStatic
        var eventListener: ((String) -> Unit)? = null

        /** Whether the FGS process assertion is currently held */
        @JvmStatic
        var isAssertionHeld: Boolean = false
            private set
    }

    private var currentTitle: String = "Task in progress"
    private var currentSubtitle: String? = null
    private var currentProgress: Int = 0
    private var currentMaxProgress: Int = 100
    private var currentIndeterminate: Boolean = false
    private var currentAllowCancel: Boolean = true
    private var currentCancelLabel: String = "Cancel"
    private var currentIconName: String? = null
    private var currentChannelId: String = "continued_task_channel"
    private var currentChannelName: String = "Background Task"
    private var currentChannelDesc: String = "Shows progress for long-running tasks"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START, ACTION_UPDATE -> {
                extractIntentData(intent)
                startForegroundCompat(buildNotification())
            }

            ACTION_USER_CANCEL -> {
                val listener = eventListener
                if (listener != null) {
                    listener.invoke("stopRequested")
                } else {
                    // Record in preferences to recover on next launch if activity was destroyed
                    getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean(KEY_STOP_REQUESTED, true)
                        .apply()
                    stopSelfCompat()
                }
            }

            ACTION_STOP -> stopSelfCompat()
            else -> stopSelfCompat()
        }

        return START_NOT_STICKY
    }

    private fun extractIntentData(intent: Intent) {
        intent.getStringExtra(EXTRA_TITLE)?.let { currentTitle = it }
        currentSubtitle = intent.getStringExtra(EXTRA_SUBTITLE)
        currentProgress = intent.getIntExtra(EXTRA_PROGRESS, currentProgress)
        currentMaxProgress = intent.getIntExtra(EXTRA_MAX_PROGRESS, currentMaxProgress)
        currentIndeterminate = intent.getBooleanExtra(EXTRA_INDETERMINATE, currentIndeterminate)
        currentAllowCancel = intent.getBooleanExtra(EXTRA_ALLOW_CANCEL, currentAllowCancel)
        intent.getStringExtra(EXTRA_CANCEL_LABEL)?.let { currentCancelLabel = it }
        intent.getStringExtra(EXTRA_ICON)?.let { currentIconName = it }
        intent.getStringExtra(EXTRA_CHANNEL_ID)?.let { currentChannelId = it }
        intent.getStringExtra(EXTRA_CHANNEL_NAME)?.let { currentChannelName = it }
        intent.getStringExtra(EXTRA_CHANNEL_DESC)?.let { currentChannelDesc = it }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelfCompat()
        super.onTaskRemoved(rootIntent)
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        eventListener?.invoke("timeout")
        stopSelfCompat()
    }

    override fun onTimeout(startId: Int) {
        eventListener?.invoke("timeout")
        stopSelfCompat()
    }

    private fun startForegroundCompat(notification: Notification) {
        try {
            ensureChannel()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            android.util.Log.w("ContinuedTaskFgs", "Failed to start foreground service", e)
            stopSelfCompat()
            return
        }

        isAssertionHeld = true
        eventListener?.invoke("assertionAcquired")
    }

    private fun stopSelfCompat() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        isAssertionHeld = false
        eventListener?.invoke("assertionLost")
        stopSelf()
    }

    private fun ensureChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(currentChannelId) != null) return

        val channel = NotificationChannel(
            currentChannelId,
            currentChannelName,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = currentChannelDesc
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun resolveNotificationIcon(): Int {
        val targetName = when (currentIconName?.lowercase()) {
            "upload" -> "ic_continued_task_upload"
            "download" -> "ic_continued_task_download"
            "sync" -> "ic_continued_task_sync"
            "processing" -> "ic_continued_task_processing"
            else -> currentIconName
        }

        if (targetName != null) {
            val resId = resources.getIdentifier(targetName, "drawable", packageName)
            if (resId != 0) return resId
        }

        // Fallback: bundled sync icon -> app launcher icon -> android system upload icon
        val defaultSyncId = resources.getIdentifier("ic_continued_task_sync", "drawable", packageName)
        if (defaultSyncId != 0) return defaultSyncId

        val appIcon = applicationInfo.icon
        if (appIcon != 0) return appIcon
        return android.R.drawable.stat_sys_upload
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val contentIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null

        val builder = NotificationCompat.Builder(this, currentChannelId)
            .setSmallIcon(resolveNotificationIcon())
            .setContentTitle(currentTitle)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        contentIntent?.let { builder.setContentIntent(it) }

        if (currentSubtitle != null) {
            builder.setContentText(currentSubtitle)
        }

        if (currentIndeterminate) {
            builder.setProgress(0, 0, true)
        } else {
            builder.setProgress(currentMaxProgress.coerceAtLeast(1), currentProgress, false)
        }

        if (currentAllowCancel) {
            val cancelIntent = PendingIntent.getService(
                this,
                1,
                Intent(this, ContinuedTaskForegroundService::class.java).setAction(ACTION_USER_CANCEL),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(0, currentCancelLabel, cancelIntent)
        }

        return builder.build()
    }
}
