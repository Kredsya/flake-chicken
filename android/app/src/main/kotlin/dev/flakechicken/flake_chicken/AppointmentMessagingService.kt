package dev.flakechicken.flake_chicken

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import androidx.work.*
import java.util.concurrent.TimeUnit
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

class AppointmentMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        getSharedPreferences("push", MODE_PRIVATE).edit().putString("token", token).apply()
        WorkManager.getInstance(this).enqueueUniqueWork("push-registration", ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequest.Builder(PushRegistrationWorker::class.java)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS).build())
        AppEvents.changed()
    }
    override fun onMessageReceived(message: RemoteMessage) {
        AppEvents.changed()
        if (!getSharedPreferences("push", MODE_PRIVATE).getBoolean("enabled", false)) return
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("appointment_changes", "약속 파토 알림", NotificationManager.IMPORTANCE_HIGH))
        val tag = message.data["notificationId"] ?: message.messageId ?: return
        val pending = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "appointment_changes") else Notification.Builder(this)
        manager.notify(tag, 0, builder.setSmallIcon(R.drawable.ic_stat_notification)
            .setContentTitle(message.notification?.title ?: message.data["title"] ?: "약속이 파토났어요")
            .setContentText(message.notification?.body ?: message.data["body"] ?: "")
            .setContentIntent(pending).setAutoCancel(true).setOnlyAlertOnce(true).build())
    }
}

class PushRegistrationWorker(context: android.content.Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences("push", android.content.Context.MODE_PRIVATE)
        if (!prefs.getBoolean("enabled", false)) return Result.success()
        val token = prefs.getString("token", null) ?: return Result.success()
        return try {
            val id = InstallationIdentity.identity(applicationContext)
            val challenge = post("/api/auth/challenge", JSONObject(id))
            val session = post("/api/auth/verify", JSONObject().put("id", challenge.getString("id")).put("signature", InstallationIdentity.sign(challenge.getString("payload"))))
            // Read preference again: disabling notifications while authenticating must win.
            if (!prefs.getBoolean("enabled", false)) return Result.success()
            post("/api/push", JSONObject().put("kind", "android").put("payload", JSONObject().put("token", token)), session.getString("token"), "PUT")
            Result.success()
        } catch (_: Exception) { Result.retry() }
    }
    private fun post(path: String, body: JSONObject, token: String? = null, method: String = "POST"): JSONObject {
        val connection = URL(BuildConfig.API_ORIGIN + path).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method; connection.connectTimeout = 15000; connection.readTimeout = 15000
            connection.setRequestProperty("Content-Type", "application/json"); connection.doOutput = true
            if (token != null) connection.setRequestProperty("Authorization", "Bearer $token")
            connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            check(connection.responseCode in 200..299)
            return JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
        } finally { connection.disconnect() }
    }
}
