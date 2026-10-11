package com.magezi.berea

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Total RAM lets the app recommend a model and size its context. Nothing leaves the device.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "berea/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "totalMemory") {
                    val info = ActivityManager.MemoryInfo()
                    (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(info)
                    result.success(info.totalMem)
                } else {
                    result.notImplemented()
                }
            }
    }
}
