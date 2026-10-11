import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Total RAM lets the app recommend a model and size its context. Nothing leaves the device.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BereaDevice") {
      let channel = FlutterMethodChannel(name: "berea/device", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "totalMemory" {
          result(Int(ProcessInfo.processInfo.physicalMemory))
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
