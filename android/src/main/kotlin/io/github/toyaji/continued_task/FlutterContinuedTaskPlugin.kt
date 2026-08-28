package io.github.toyaji.continued_task

import android.Manifest
import android.app.Activity
import android.app.ForegroundServiceStartNotAllowedException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

class FlutterContinuedTaskPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var myListener: ((String, String) -> Unit)? = null
    private var pendingPermissionResult: Result? = null

    companion object {
        private const val PERMISSION_REQUEST_CODE = 7654

        /**
         * taskId -> slot. A task keeps its slot for as long as it runs, so its
         * notification and Cancel action stay on the same component.
         */
        private val slotByTaskId = linkedMapOf<String, Int>()

        /** Assigns (or reuses) the slot that serves [taskId], or null if full. */
        @Synchronized
        private fun slotFor(taskId: String): Int? {
            slotByTaskId[taskId]?.let { return it }
            val used = slotByTaskId.values.toSet()
            for (slot in 0 until ContinuedTaskForegroundService.SLOT_COUNT) {
                if (!used.contains(slot)) {
                    slotByTaskId[taskId] = slot
                    return slot
                }
            }
            return null
        }

        @Synchronized
        private fun releaseSlot(taskId: String) {
            slotByTaskId.remove(taskId)
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "io.github.toyaji.continued_task/channel")
        channel.setMethodCallHandler(this)

        // The task id travels with every event: with a single listener and no
        // id, whichever task registered last received another task's Cancel.
        val listener: (String, String) -> Unit = { event, taskId ->
            mainHandler.post { channel.invokeMethod(event, mapOf("taskId" to taskId)) }
        }
        myListener = listener
        ContinuedTaskForegroundService.eventListener = listener
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        if (ContinuedTaskForegroundService.eventListener === myListener) {
            ContinuedTaskForegroundService.eventListener = null
        }
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "start" -> {
                val success = startServiceWithAction(ContinuedTaskForegroundService.ACTION_START, call.arguments as? Map<String, Any?>)
                result.success(success)
            }
            "update" -> {
                val args = call.arguments as? Map<String, Any?>
                val taskId = (args?.get("taskId") as? String) ?: "default_task"
                val slot = slotFor(taskId)
                // Update the live instance directly. Going through
                // startForegroundService on every tick made SystemUI rebuild the
                // status bar icon row, which looks like flickering.
                val applied = slot != null &&
                    ContinuedTaskForegroundService.applyUpdate(slot, args)
                val success = if (applied) {
                    true
                } else {
                    startServiceWithAction(ContinuedTaskForegroundService.ACTION_START, args)
                }
                result.success(success)
            }
            "stop" -> {
                val taskId = (call.arguments as? Map<*, *>)?.get("taskId") as? String
                    ?: "default_task"
                stopService(taskId)
                result.success(null)
            }
            "requestNotificationPermission" -> {
                requestNotificationPermission(result)
            }
            "syncState" -> {
                val taskId = (call.arguments as? Map<*, *>)?.get("taskId") as? String
                val ctx = context
                val prefs = ctx?.getSharedPreferences(ContinuedTaskForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                // No task id: the 0.1.x aggregate view.
                val held = if (taskId == null) {
                    ContinuedTaskForegroundService.isAssertionHeld
                } else {
                    ContinuedTaskForegroundService.isAssertionHeldFor(taskId)
                }
                val stopKey = if (taskId == null) {
                    ContinuedTaskForegroundService.KEY_STOP_REQUESTED
                } else {
                    ContinuedTaskForegroundService.stopRequestedKey(taskId)
                }
                val stopRequested = prefs?.getBoolean(stopKey, false) ?: false
                result.success(
                    mapOf(
                        "assertionHeld" to held,
                        "stopRequested" to stopRequested
                    )
                )
            }
            "ackStopRequest" -> {
                val taskId = (call.arguments as? Map<*, *>)?.get("taskId") as? String
                val ctx = context
                val editor = ctx?.getSharedPreferences(ContinuedTaskForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                    ?.edit()
                if (taskId == null) {
                    editor?.remove(ContinuedTaskForegroundService.KEY_STOP_REQUESTED)
                } else {
                    editor?.remove(ContinuedTaskForegroundService.stopRequestedKey(taskId))
                    // Clear the aggregate flag too once every task is acked.
                    editor?.remove(ContinuedTaskForegroundService.KEY_STOP_REQUESTED)
                }
                editor?.apply()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun requestNotificationPermission(result: Result) {
        val ctx = context ?: run {
            result.success(false)
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }

        val currentActivity = activity
        if (currentActivity == null) {
            val isGranted = ContextCompat.checkSelfPermission(
                ctx,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            result.success(isGranted)
            return
        }

        val isGranted = ContextCompat.checkSelfPermission(
            currentActivity,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED

        if (isGranted) {
            result.success(true)
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            currentActivity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            PERMISSION_REQUEST_CODE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val isGranted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(isGranted)
            pendingPermissionResult = null
            return true
        }
        return false
    }

    private fun startServiceWithAction(action: String, args: Map<String, Any?>?): Boolean {
        val ctx = activity ?: context ?: return false
        val taskId = (args?.get("taskId") as? String) ?: "default_task"
        val slot = slotFor(taskId) ?: run {
            android.util.Log.w(
                "ContinuedTaskPlugin",
                "No free slot for task '$taskId' (max ${ContinuedTaskForegroundService.SLOT_COUNT})"
            )
            return false
        }
        val intent = Intent(ctx, ContinuedTaskForegroundService.serviceClassFor(slot)).apply {
            this.action = action
            args?.let { map ->
                (map["taskId"] as? String)?.let { putExtra(ContinuedTaskForegroundService.EXTRA_TASK_ID, it) }
                (map["title"] as? String)?.let { putExtra(ContinuedTaskForegroundService.EXTRA_TITLE, it) }
                (map["subtitle"] as? String)?.let { putExtra(ContinuedTaskForegroundService.EXTRA_SUBTITLE, it) }
                (map["progress"] as? Number)?.let { putExtra(ContinuedTaskForegroundService.EXTRA_PROGRESS, it.toInt()) }
                (map["initialProgress"] as? Number)?.let { putExtra(ContinuedTaskForegroundService.EXTRA_PROGRESS, it.toInt()) }
                (map["maxProgress"] as? Number)?.let { putExtra(ContinuedTaskForegroundService.EXTRA_MAX_PROGRESS, it.toInt()) }
                (map["indeterminate"] as? Boolean)?.let { putExtra(ContinuedTaskForegroundService.EXTRA_INDETERMINATE, it) }
                (map["allowCancel"] as? Boolean)?.let { putExtra(ContinuedTaskForegroundService.EXTRA_ALLOW_CANCEL, it) }
                (map["cancelActionLabel"] as? String)?.let { putExtra(ContinuedTaskForegroundService.EXTRA_CANCEL_LABEL, it) }
                (map["androidNotificationIcon"] as? String)?.let { putExtra(ContinuedTaskForegroundService.EXTRA_ICON, it) }
                (map["androidChannelId"] as? String)?.let { putExtra(ContinuedTaskForegroundService.EXTRA_CHANNEL_ID, it) }
                (map["androidChannelName"] as? String)?.let { putExtra(ContinuedTaskForegroundService.EXTRA_CHANNEL_NAME, it) }
                (map["androidChannelDescription"] as? String)?.let { putExtra(ContinuedTaskForegroundService.EXTRA_CHANNEL_DESC, it) }
            }
        }

        return try {
            ctx.startForegroundService(intent)
            true
        } catch (e: Exception) {
            val isBgBlocked = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    e is ForegroundServiceStartNotAllowedException
            android.util.Log.w("ContinuedTaskPlugin", if (isBgBlocked) "FGS start blocked (app in background)" else "Failed to start FGS", e)
            false
        }
    }

    private fun stopService(taskId: String) {
        val ctx = activity ?: context ?: return
        val slot = slotFor(taskId) ?: 0
        val intent = Intent(ctx, ContinuedTaskForegroundService.serviceClassFor(slot)).apply {
            action = ContinuedTaskForegroundService.ACTION_STOP
            putExtra(ContinuedTaskForegroundService.EXTRA_TASK_ID, taskId)
        }
        try {
            // startForegroundService, not startService: a running foreground
            // service must be reachable while the app itself is in the
            // background, where startService throws on O+ and the task would
            // never stop.
            ctx.startForegroundService(intent)
        } catch (e: Exception) {
            android.util.Log.w("ContinuedTaskPlugin", "Failed to send stop action to service", e)
        } finally {
            releaseSlot(taskId)
        }
    }

    // --- ActivityAware ---
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }
}
