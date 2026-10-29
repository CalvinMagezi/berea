import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Lets the daily verse show while Berea is open, and is where the notification plugin listens.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
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
        } else if call.method == "excludeFromBackup", let path = call.arguments as? String {
          // Keeps notes, studies and imports out of iCloud backups. Everything inside the folder
          // inherits the flag.
          var url = URL(fileURLWithPath: path)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          do {
            try url.setResourceValues(values)
            result(true)
          } catch {
            result(FlutterError(code: "backup", message: error.localizedDescription, details: nil))
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
