import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // The bundle is named berea; the window carries the product's name.
    self.title = "Berea"

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Total RAM lets the app recommend a model and size its context. Nothing leaves the device.
    let channel = FlutterMethodChannel(
      name: "berea/device", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "totalMemory" {
        result(Int(ProcessInfo.processInfo.physicalMemory))
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
