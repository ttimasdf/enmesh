package com.plugin.vpn_service_plugin

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.VpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayOutputStream

// VPN服务插件类，实现Flutter插件、方法调用处理和Activity感知接口
class VpnServicePlugin: FlutterPlugin, MethodCallHandler, ActivityAware, ActivityResultListener {
    // 方法通道，用于Flutter和原生代码通信
    private lateinit var channel : MethodChannel
    // 事件通道，用于向Flutter发送VPN状态变化事件
    private lateinit var eventChannel: EventChannel
    // Application context is also available to background Flutter engines.
    private lateinit var applicationContext: Context
    // Activity is only required while displaying the initial VPN consent UI.
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPrepareResult: Result? = null
    // 事件接收器
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    // 插件附加到Flutter引擎时调用
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "vpn_service")
        channel.setMethodCallHandler(this)
        
        // 初始化事件通道
        eventChannel = EventChannel(binding.binaryMessenger, "vpn_service_events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                // 设置VPN服务的回调函数
                TauriVpnService.triggerCallback = { event, data ->
                    eventSink?.success(mapOf("event" to event, "data" to data))
                }
                NativeLogger.attachEventCallback { data ->
                    eventSink?.success(mapOf("event" to "diagnostic", "data" to data))
                }
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
                TauriVpnService.triggerCallback = { _, _ -> }
                NativeLogger.detachEventCallback()
            }
        })
    }

    // 处理来自Flutter的方法调用
    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            handleMethodCall(call, result)
        } catch (error: Exception) {
            NativeLogger.error(
                "vpn.plugin.call.failed",
                "VPN plugin method call failed",
                mapOf("method" to call.method),
                error,
            )
            result.error("vpn_native_error", error.message, null)
        }
    }

    private fun handleMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "configureLogging" -> {
                val level = call.argument<String>("minimumLevel") ?: "info"
                NativeLogger.configure(level)
                result.success(null)
            }
            // 准备VPN服务
            "prepareVpn" -> {
                val currentActivity = activity
                val intent = VpnService.prepare(currentActivity ?: applicationContext)
                if (intent != null && currentActivity != null) {
                    if (pendingPrepareResult != null) {
                        result.error("vpn_prepare_pending", "VPN consent is already pending", null)
                        return
                    }
                    pendingPrepareResult = result
                    currentActivity.startActivityForResult(intent, VPN_PREPARE_REQUEST_CODE)
                } else if (intent != null) {
                    result.error("vpn_activity_required", "VPN consent requires a foreground activity", null)
                } else {
                    result.success(mapOf<String, Any>())
                }
            }
            // 启动VPN服务
            "startVpn" -> {
                val args = call.arguments<Map<String, Any>>()
                val serviceContext = activity ?: applicationContext
                val intent = VpnService.prepare(serviceContext)
                if (intent != null) {
                    result.error("vpn_permission_required", "VPN consent has not been granted", null)
                } else {
                    // 配置并启动VPN服务. Starting an existing service replaces
                    // its TUN without treating the refresh as a revocation.
                    val serviceIntent = Intent(serviceContext, TauriVpnService::class.java)
                    
                    // 处理IPv4地址
                    serviceIntent.putExtra("IPV4_ADDR", args?.get("ipv4Addr") as? String)
                    
                    // 处理路由列表 - 从List<Dynamic>转换为Array<String>
                    val routesList = args?.get("routes") as? List<*>
                    if (routesList != null) {
                        val routesArray = routesList.filterIsInstance<String>().toTypedArray()
                        serviceIntent.putExtra("ROUTES", routesArray)
                    }
                    
                    // 处理DNS
                    serviceIntent.putExtra("DNS", args?.get("dns") as? String)
                    
                    // 处理不允许的应用列表 - 从List<Dynamic>转换为Array<String>
                    val disallowedAppsList = args?.get("disallowedApplications") as? List<*>
                    if (disallowedAppsList != null) {
                        val disallowedAppsArray = disallowedAppsList.filterIsInstance<String>().toTypedArray()
                        serviceIntent.putExtra("DISALLOWED_APPLICATIONS", disallowedAppsArray)
                    }

                    // 处理允许的应用列表（白名单模式）
                    val allowedAppsList = args?.get("allowedApplications") as? List<*>
                    if (allowedAppsList != null) {
                        val allowedAppsArray = allowedAppsList.filterIsInstance<String>().toTypedArray()
                        serviceIntent.putExtra("ALLOWED_APPLICATIONS", allowedAppsArray)
                    }
                    
                    // 处理MTU
                    val mtu = args?.get("mtu")
                    if (mtu is Int) {
                        serviceIntent.putExtra("MTU", mtu)
                    }
                    serviceIntent.putExtra(
                        TauriVpnService.CONNECTION_ATTEMPT_ID,
                        args?.get("connectionAttemptId") as? String,
                    )

                    serviceContext.startService(serviceIntent)
                    result.success(mapOf<String, Any>())
                }
            }
            // 停止VPN服务
            "stopVpn" -> {
                val serviceContext = activity ?: applicationContext
                val stopIntent = Intent(serviceContext, TauriVpnService::class.java).apply {
                    action = TauriVpnService.ACTION_STOP
                }
                serviceContext.startService(stopIntent)
                result.success(mapOf<String, Any>())
            }
            // 获取可启动的应用列表（用于分应用 VPN 选择器）
            "getInstalledApps" -> {
                // 枚举与图标编码可能较重，放到后台线程执行。
                Thread {
                    try {
                        result.success(getInstalledApps())
                    } catch (error: Exception) {
                        NativeLogger.error(
                            "vpn.plugin.installed_apps.failed",
                            "Failed to enumerate installed apps",
                            error = error,
                        )
                        mainHandler.post { result.error("vpn_native_error", error.message, null) }
                    }
                }.start()
            }
            else -> result.notImplemented()
        }
    }

    // 插件从Flutter引擎分离时调用
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // The TUN fd belongs to the Rust runtime hosted by this Flutter engine.
        // Once the engine exits, leaving the native VPN alive only creates a
        // stale Android VPN indicator with no usable tunnel behind it.
        applicationContext.stopService(Intent(applicationContext, TauriVpnService::class.java))
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        TauriVpnService.triggerCallback = { _, _ -> }
        NativeLogger.detachEventCallback()
    }

    // 插件附加到Activity时调用
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachActivity(binding)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != VPN_PREPARE_REQUEST_CODE) return false
        val pending = pendingPrepareResult ?: return true
        pendingPrepareResult = null
        if (resultCode == Activity.RESULT_OK) {
            pending.success(mapOf<String, Any>())
        } else {
            pending.error("vpn_permission_denied", "VPN consent was denied", null)
        }
        return true
    }

    // Activity生命周期相关回调
    override fun onDetachedFromActivity() {
        detachActivity()
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachActivity(binding)
    }
    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    private fun attachActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    /** 枚举设备上已安装的应用（排除自身），携带图标、系统标记与安装/更新时间。 */
    private fun getInstalledApps(): List<Map<String, Any?>> {
        val pm = applicationContext.packageManager
        @Suppress("DEPRECATION")
        val packages = pm.getInstalledPackages(0)
        val selfPackage = applicationContext.packageName

        return packages
            .asSequence()
            .mapNotNull { info ->
                val appInfo = info.applicationInfo ?: return@mapNotNull null
                val packageName = info.packageName
                if (packageName == selfPackage) return@mapNotNull null
                val label = try {
                    pm.getApplicationLabel(appInfo)?.toString()
                } catch (_: Exception) {
                    null
                } ?: packageName
                val icon = try {
                    appInfo.loadIcon(pm)
                } catch (_: Exception) {
                    null
                }
                InstalledAppEntry(
                    packageName = packageName,
                    label = label,
                    icon = icon,
                    system = (appInfo.flags and
                        (ApplicationInfo.FLAG_SYSTEM or
                            ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0,
                    installTime = info.firstInstallTime,
                    updateTime = info.lastUpdateTime,
                )
            }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.label })
            .map { entry ->
                mapOf(
                    "packageName" to entry.packageName,
                    "label" to entry.label,
                    "icon" to drawableToPngBytes(entry.icon),
                    "system" to entry.system,
                    "installTime" to entry.installTime,
                    "updateTime" to entry.updateTime,
                )
            }
            .toList()
    }

    private fun drawableToPngBytes(icon: Drawable?): ByteArray? {
        if (icon == null) return null
        return try {
            var bitmap = when (icon) {
                is BitmapDrawable -> icon.bitmap
                else -> {
                    val width = if (icon.intrinsicWidth > 0) icon.intrinsicWidth else 96
                    val height = if (icon.intrinsicHeight > 0) icon.intrinsicHeight else 96
                    Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
                        Canvas(it).also { canvas -> icon.setBounds(0, 0, canvas.width, canvas.height); icon.draw(canvas) }
                    }
                }
            }
            // 统一缩放到 64px 以内，减小编码体积与耗时
            val maxSize = maxOf(bitmap.width, bitmap.height)
            if (maxSize > 64) {
                val scale = 64f / maxSize
                bitmap = Bitmap.createScaledBitmap(
                    bitmap,
                    (bitmap.width * scale).toInt().coerceAtLeast(1),
                    (bitmap.height * scale).toInt().coerceAtLeast(1),
                    true,
                )
            }
            val output = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            output.toByteArray()
        } catch (_: Exception) {
            null
        }
    }

    private data class InstalledAppEntry(
        val packageName: String,
        val label: String,
        val icon: Drawable?,
        val system: Boolean,
        val installTime: Long,
        val updateTime: Long,
    )

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    private companion object {
        const val VPN_PREPARE_REQUEST_CODE = 0x0f
    }
}
