import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Maps SDK for iOS needs the key at launch; the google_maps_flutter plugin
    // does NOT read Info.plist itself, so we pass the GMSApiKey we already store
    // there (single source of truth — same key as Android's manifest).
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !apiKey.isEmpty {
      GMSServices.provideAPIKey(apiKey)
    }
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
