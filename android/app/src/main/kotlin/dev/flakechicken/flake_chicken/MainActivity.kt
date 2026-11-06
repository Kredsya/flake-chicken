package dev.flakechicken.flake_chicken

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.Executors

object AppEvents {
    var sink: EventChannel.EventSink? = null
    fun changed() { Handler(Looper.getMainLooper()).post { sink?.success("changed") } }
}

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private val executor = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.flakechicken/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { AppEvents.sink = events }
            override fun onCancel(arguments: Any?) { AppEvents.sink = null }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.flakechicken/platform").setMethodCallHandler { call, result ->
            when (call.method) {
                "identity", "sign" -> executor.execute {
                    try {
                        val value = if (call.method == "identity") InstallationIdentity.identity(this) else InstallationIdentity.sign(call.arguments as String)
                        runOnUiThread { result.success(value) }
                    } catch (_: Exception) { runOnUiThread { result.error("identity", "기기 인증에 실패했어요.", null) } }
                }
                "notifications" -> {
                    val request = call.argument<Boolean>("request") == true
                    if (request && Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null) result.error("busy", "알림 권한을 확인 중이에요.", null)
                        else { permissionResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 701) }
                    } else notificationStatus(result, request)
                }
                "disableNotifications" -> {
                    getSharedPreferences("push", MODE_PRIVATE).edit().putBoolean("enabled", false).apply()
                    (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).cancelAll()
                    result.success(null)
                }
                "openUrl" -> {
                    val uri = Uri.parse(call.arguments as String)
                    if (uri.scheme == "https" && uri.host == "35.212.249.154") {
                        try { startActivity(Intent(Intent.ACTION_VIEW, uri)); result.success(null) }
                        catch (_: Exception) { result.error("browser", "브라우저를 열지 못했어요.", null) }
                    } else result.error("url", "허용되지 않은 주소예요.", null)
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= 26) (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(
            NotificationChannel("appointment_changes", "약속 파토 알림", NotificationManager.IMPORTANCE_HIGH))
    }
    private fun notificationStatus(result: MethodChannel.Result, enable: Boolean) {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val granted = (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) && manager.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel("appointment_changes")?.importance != NotificationManager.IMPORTANCE_NONE)
        val prefs = getSharedPreferences("push", MODE_PRIVATE)
        if (enable && granted) prefs.edit().putBoolean("enabled", true).apply()
        val enabled = granted && prefs.getBoolean("enabled", false)
        if (!enabled) {
            result.success(mapOf("supported" to true, "enabled" to false, "message" to if (!granted) "Android 설정에서 알림 권한을 허용해주세요." else "시스템 알림으로 받기")); return
        }
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                prefs.edit().putString("token", task.result).apply()
                result.success(mapOf("supported" to true, "enabled" to true, "kind" to "android", "payload" to mapOf("token" to task.result)))
            } else result.error("push", "푸시 연결을 확인하지 못했어요.", null)
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 701) { val result = permissionResult; permissionResult = null; if (result != null) notificationStatus(result, true) }
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); AppEvents.changed() }
    override fun onDestroy() { AppEvents.sink = null; executor.shutdown(); super.onDestroy() }
}
