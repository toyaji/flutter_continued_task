package dev.flutter.continued_task

import android.app.Activity
import android.app.ForegroundServiceStartNotAllowedException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FlutterContinuedTaskPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var myListener: ((String) -> Unit)? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "dev.flutter.continued_task/channel")
        channel.setMethodCallHandler(this)

        val listener: (String) -> Unit = { event ->
            mainHandler.post { channel.invokeMethod(event, null) }
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
                val success = startServiceWithAction(ContinuedTaskForegroundService.ACTION_UPDATE, call.arguments as? Map<String, Any?>)
                result.success(success)
            }
            "stop" -> {
                stopService()
                result.success(null)
            }
            "syncState" -> {
                val ctx = context
                val prefs = ctx?.getSharedPreferences(ContinuedTaskForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                val stopRequested = prefs?.getBoolean(ContinuedTaskForegroundService.KEY_STOP_REQUESTED, false) ?: false
                result.success(
                    mapOf(
                        "assertionHeld" to ContinuedTaskForegroundService.isAssertionHeld,
                        "stopRequested" to stopRequested
                    )
                )
            }
            "ackStopRequest" -> {
                val ctx = context
                ctx?.getSharedPreferences(ContinuedTaskForegroundService.PREFS_NAME, Context.MODE_PRIVATE)
                    ?.edit()
                    ?.remove(ContinuedTaskForegroundService.KEY_STOP_REQUESTED)
                    ?.apply()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startServiceWithAction(action: String, args: Map<String, Any?>?): Boolean {
        val ctx = activity ?: context ?: return false
        val intent = Intent(ctx, ContinuedTaskForegroundService::class.java).apply {
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

    private fun stopService() {
        val ctx = activity ?: context ?: return
        val intent = Intent(ctx, ContinuedTaskForegroundService::class.java).apply {
            action = ContinuedTaskForegroundService.ACTION_STOP
        }
        try {
            ctx.startService(intent)
        } catch (e: Exception) {
            android.util.Log.w("ContinuedTaskPlugin", "Failed to send stop action to service", e)
        }
    }

    // --- ActivityAware ---
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
