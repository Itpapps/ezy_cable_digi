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

    // Mirror of Android MainActivity's `ezy_cable_digi/device_id` channel so the
    // login `imei` field is non-empty on iOS too. Android returns ANDROID_ID;
    // the stable iOS analog is identifierForVendor (a per-vendor UUID).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceIdChannel") {
      let channel = FlutterMethodChannel(
        name: "ezy_cable_digi/device_id",
        binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "getDeviceIdentifier" {
          result(UIDevice.current.identifierForVendor?.uuidString ?? "")
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
