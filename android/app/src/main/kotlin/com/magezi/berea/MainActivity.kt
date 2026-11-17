package com.magezi.berea

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "berea/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // The installed app's own file, so it can be handed to the share sheet and passed on.
                    "apkPath" -> result.success(applicationInfo.sourceDir)
                    // Hands a downloaded update to Android's installer, which asks the reader to confirm
                    // and refuses a file not signed with this app's own key.
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("no_path", "No file was given.", null)
                        } else {
                            result.success(installApk(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installApk(path: String): String {
        // Since Android 8 each app is allowed to install apps by the reader, once.
        if (!packageManager.canRequestPackageInstalls()) {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            return "needsPermission"
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(path))
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        return "started"
    }
}
