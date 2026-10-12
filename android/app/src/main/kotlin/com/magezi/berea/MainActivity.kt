package com.magezi.berea

import android.app.ActivityManager
import android.content.Context
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity shares its engine with the background narration service.
class MainActivity : AudioServiceActivity() {
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
