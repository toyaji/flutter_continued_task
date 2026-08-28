package io.github.toyaji.continued_task

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
import androidx.core.app.NotificationManagerCompat

/**
 * Foreground Service that holds process lifecycle continuation
 * and displays an ongoing notification during long-running tasks.
 */
open class ContinuedTaskForegroundService : Service() {

    companion object {
        const val ACTION_START = "io.github.toyaji.continued_task.START"
        const val ACTION_UPDATE = "io.github.toyaji.continued_task.UPDATE"
        const val ACTION_STOP = "io.github.toyaji.continued_task.STOP"
        const val ACTION_USER_CANCEL = "io.github.toyaji.continued_task.USER_CANCEL"

        const val ACTION_NOTIFICATION_DISMISSED =
            "io.github.toyaji.continued_task.NOTIFICATION_DISMISSED"

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

        /** Slot 0 keeps the id 0.1.x used; each further slot gets its own. */
        private const val NOTIFICATION_ID_BASE = 54321

        const val PREFS_NAME = "continued_task_prefs"
        const val KEY_STOP_REQUESTED = "stop_requested_while_detached"

        /** Number of service components declared in the plugin manifest. */
        const val SLOT_COUNT = 4

        /**
         * Service -> Dart event listener. The task id travels with the event:
         * with a single listener and no id, whichever task registered last
         * received the Cancel meant for another task's notification.
         */
        @JvmStatic
        var eventListener: ((event: String, taskId: String) -> Unit)? = null

        /** Task ids whose slot currently holds a foreground assertion. */
        private val heldTaskIds = java.util.Collections.synchronizedSet(mutableSetOf<String>())

        /** Whether ANY slot holds an assertion (0.1.x aggregate view). */
        @JvmStatic
        val isAssertionHeld: Boolean
            get() = heldTaskIds.isNotEmpty()

        /** Whether the slot running [taskId] holds an assertion. */
        @JvmStatic
        fun isAssertionHeldFor(taskId: String): Boolean = heldTaskIds.contains(taskId)

        /** Stop requests are recorded per task so a restart knows which one. */
        @JvmStatic
        fun stopRequestedKey(taskId: String): String = "$KEY_STOP_REQUESTED::$taskId"

        /**
         * Live service instances by slot.
         *
         * Progress updates go straight to the instance instead of starting the
         * service again. Re-entering the foreground state on every tick made
         * SystemUI rebuild the status bar icon row, which reads as flicker once
         * more than one task is running.
         */
        private val instances = mutableMapOf<Int, ContinuedTaskForegroundService>()

        /** Applies a progress update in-process. Returns false if the slot is idle. */
        @JvmStatic
        fun applyUpdate(slot: Int, args: Map<String, Any?>?): Boolean {
            val service = instances[slot] ?: return false
            service.applyUpdateArgs(args)
            return true
        }

        /** The component that owns [slot]. */
        @JvmStatic
        fun serviceClassFor(slot: Int): Class<*> = when (slot) {
            1 -> ContinuedTaskForegroundServiceSlot1::class.java
            2 -> ContinuedTaskForegroundServiceSlot2::class.java
            3 -> ContinuedTaskForegroundServiceSlot3::class.java
            else -> ContinuedTaskForegroundService::class.java
        }
    }

    /**
     * Which of the manifest-declared components this instance is.
     *
     * A foreground service owns exactly one notification, so concurrent tasks
     * need one component each. Subclasses below only override this.
     */
    protected open val slot: Int get() = 0

    private val notificationId: Int get() = NOTIFICATION_ID_BASE + slot

    /** The task currently occupying this slot. */
    private var currentTaskId: String = "default_task"

    /** Set when the user swiped this slot's notification away (Android 13+). */
    private var notificationDismissed: Boolean = false

    /** Whether this slot already entered the foreground state. */
    private var isForegroundStarted: Boolean = false

    /**
     * When this slot's run began. Every rebuild reuses it.
     *
     * The default `when` is "now", stamped afresh on each progress update, and
     * the status bar orders icons by it — so two concurrent tasks kept swapping
     * places on every tick, which reads as flicker. A fixed timestamp plus a
     * per-slot sort key keeps the row still.
     */
    private var startedAtMillis: Long = 0L

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

    override fun onCreate() {
        super.onCreate()
        instances[slot] = this
    }

    override fun onDestroy() {
        if (instances[slot] === this) instances.remove(slot)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /** In-process progress update — no Intent, no service start. */
    private fun applyUpdateArgs(args: Map<String, Any?>?) {
        (args?.get("taskId") as? String)?.let { currentTaskId = it }
        (args?.get("title") as? String)?.let { currentTitle = it }
        currentSubtitle = args?.get("subtitle") as? String ?: currentSubtitle
        (args?.get("progress") as? Number)?.let { currentProgress = it.toInt() }
        (args?.get("maxProgress") as? Number)?.let { currentMaxProgress = it.toInt() }
        if (notificationDismissed) {
            heldTaskIds.add(currentTaskId)
            return
        }
        postUpdate(buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                // A new run always shows its notification again, even if the
                // previous one had been swiped away.
                notificationDismissed = false
                startedAtMillis = System.currentTimeMillis()
                extractIntentData(intent)
                startForegroundCompat(buildNotification())
            }

            ACTION_UPDATE -> {
                extractIntentData(intent)
                // Swiping away is not a stop request — the notification carries
                // an explicit Cancel action for that. Keep running, but do not
                // re-post: reposting on every progress tick is what made a
                // dismissed notification pop back up.
                if (notificationDismissed) {
                    heldTaskIds.add(currentTaskId)
                } else {
                    postUpdate(buildNotification())
                }
            }

            ACTION_USER_CANCEL -> {
                // The task id rides on the intent: each slot's notification has
                // its own component, so the extra always belongs to this slot.
                intent.getStringExtra(EXTRA_TASK_ID)?.let { currentTaskId = it }
                val listener = eventListener
                if (listener != null) {
                    listener.invoke("stopRequested", currentTaskId)
                } else {
                    // Record in preferences to recover on next launch if activity was destroyed
                    getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean(stopRequestedKey(currentTaskId), true)
                        // Keep the 0.1.x key in sync so an app that still reads
                        // the aggregate state recovers exactly as before.
                        .putBoolean(KEY_STOP_REQUESTED, true)
                        .apply()
                    stopSelfCompat()
                }
            }

            ACTION_NOTIFICATION_DISMISSED -> {
                // Android 13+ lets people swipe a foreground service notification
                // away. That hides the notification; it is NOT a stop request —
                // the Cancel action is. The work continues silently until it
                // finishes or the user stops it from inside the app.
                intent.getStringExtra(EXTRA_TASK_ID)?.let { currentTaskId = it }
                notificationDismissed = true
                eventListener?.invoke("notificationDismissed", currentTaskId)
            }

            ACTION_STOP -> stopSelfCompat()
            else -> stopSelfCompat()
        }

        return START_NOT_STICKY
    }

    private fun extractIntentData(intent: Intent) {
        intent.getStringExtra(EXTRA_TASK_ID)?.let { currentTaskId = it }
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
        eventListener?.invoke("timeout", currentTaskId)
        stopSelfCompat()
    }

    override fun onTimeout(startId: Int) {
        eventListener?.invoke("timeout", currentTaskId)
        stopSelfCompat()
    }

    /**
     * Refreshes an already-posted notification.
     *
     * Re-entering the foreground state on every progress tick made the status
     * bar replay its icon-entry animation, so two concurrent tasks produced two
     * icons blinking a few times a second. Once the service is foreground, the
     * notification is updated like any other.
     */
    private fun postUpdate(notification: Notification) {
        if (!isForegroundStarted) {
            startForegroundCompat(notification)
            return
        }
        try {
            ensureChannel()
            NotificationManagerCompat.from(this).notify(notificationId, notification)
            heldTaskIds.add(currentTaskId)
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS denied — the service keeps running without a
            // visible notification, exactly as the platform intends.
            android.util.Log.w("ContinuedTaskFgs", "Notification update not permitted", e)
        }
    }

    private fun startForegroundCompat(notification: Notification) {
        try {
            ensureChannel()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    notificationId,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(notificationId, notification)
            }
        } catch (e: Exception) {
            android.util.Log.w("ContinuedTaskFgs", "Failed to start foreground service", e)
            stopSelfCompat()
            return
        }

        isForegroundStarted = true
        heldTaskIds.add(currentTaskId)
        eventListener?.invoke("assertionAcquired", currentTaskId)
    }

    private fun stopSelfCompat() {
        isForegroundStarted = false
        startedAtMillis = 0L
        stopForeground(STOP_FOREGROUND_REMOVE)
        heldTaskIds.remove(currentTaskId)
        eventListener?.invoke("assertionLost", currentTaskId)
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

        if (startedAtMillis == 0L) startedAtMillis = System.currentTimeMillis()

        val builder = NotificationCompat.Builder(this, currentChannelId)
            .setSmallIcon(resolveNotificationIcon())
            .setContentTitle(currentTitle)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            // Stable ordering across updates — see [startedAtMillis].
            .setWhen(startedAtMillis)
            .setShowWhen(false)
            .setSortKey(slot.toString())
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

        // Each slot is its own component, so PendingIntent matching
        // (Intent.filterEquals) already keeps these apart — extras alone would
        // not, since they are excluded from matching.
        if (currentAllowCancel) {
            val cancelIntent = PendingIntent.getService(
                this,
                1,
                Intent(this, javaClass)
                    .setAction(ACTION_USER_CANCEL)
                    .putExtra(EXTRA_TASK_ID, currentTaskId),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(0, currentCancelLabel, cancelIntent)
        }

        builder.setDeleteIntent(
            PendingIntent.getService(
                this,
                2,
                Intent(this, javaClass)
                    .setAction(ACTION_NOTIFICATION_DISMISSED)
                    .putExtra(EXTRA_TASK_ID, currentTaskId),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )

        return builder.build()
    }
}

/**
 * Slot components for concurrent tasks.
 *
 * A foreground service owns exactly one notification, so a task that wants its
 * own notification and its own Cancel action needs its own component. These are
 * declared in the plugin manifest and stay dormant until an app opts into
 * concurrent tasks; a single-task app only ever uses slot 0.
 */
class ContinuedTaskForegroundServiceSlot1 : ContinuedTaskForegroundService() {
    override val slot: Int get() = 1
}

class ContinuedTaskForegroundServiceSlot2 : ContinuedTaskForegroundService() {
    override val slot: Int get() = 2
}

class ContinuedTaskForegroundServiceSlot3 : ContinuedTaskForegroundService() {
    override val slot: Int get() = 3
}
