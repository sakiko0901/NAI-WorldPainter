package com.naihuishi.nai_huishi

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(SuperResolutionPlugin())
        flutterEngine.plugins.add(AppUpdatePlugin())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "worldpainter/online_gallery")
            .setMethodCallHandler { call, result ->
                if (call.method != "openUrl") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val url = call.argument<String>("url")
                val uri = url?.let { Uri.parse(it) }
                if (uri == null || uri.scheme != "https" || uri.host.isNullOrBlank() || !uri.userInfo.isNullOrEmpty()) {
                    result.error("INVALID_URL", "Unsupported source URL", null)
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    result.error("NO_BROWSER", "No browser available", null)
                } catch (_: SecurityException) {
                    result.error("OPEN_FAILED", "Cannot open source URL", null)
                }
            }
    }
}
