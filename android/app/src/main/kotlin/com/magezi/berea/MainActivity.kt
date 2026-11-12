package com.magezi.berea

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The installed app's own file, so it can be handed to the share sheet and passed on.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "berea/app")
            .setMethodCallHandler { call, result ->
                if (call.method == "apkPath") result.success(applicationInfo.sourceDir)
                else result.notImplemented()
            }
    }
}
