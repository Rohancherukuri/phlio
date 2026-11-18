package com.example.phlio

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Google Places from Dart (Notes location): the Maps key that is
        // already in the manifest, plus this app's package name and signing
        // certificate SHA-1, which Google checks for Android-restricted keys
        // (X-Android-Package / X-Android-Cert headers).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "phlio/maps_identity")
            .setMethodCallHandler { call, result ->
                if (call.method != "get") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
                    val key = info.metaData?.getString("com.google.android.geo.API_KEY") ?: ""
                    result.success(mapOf("key" to key, "package" to packageName, "sha1" to signingSha1()))
                } catch (e: Exception) {
                    result.error("unavailable", e.message, null)
                }
            }
    }

    private fun signingSha1(): String {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            info.signingInfo?.apkContentsSigners
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures
        }
        val cert = signatures?.firstOrNull() ?: return ""
        val digest = MessageDigest.getInstance("SHA-1").digest(cert.toByteArray())
        return digest.joinToString("") { "%02X".format(it) }
    }
}
