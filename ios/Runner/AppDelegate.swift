import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deviceIdChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !apiKey.isEmpty {
      GMSServices.provideAPIKey(apiKey)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceIdChannel") else {
      NSLog("[EzyCableDigi] DeviceIdChannel registrar unavailable — channel not registered")
      return
    }

    let channel = FlutterMethodChannel(
      name: "ezy_cable_digi/device_id",
      binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      if call.method == "getDeviceIdentifier" {
        let id = UIDevice.current.identifierForVendor?.uuidString ?? ""
        if id.isEmpty {
          NSLog("[EzyCableDigi] identifierForVendor returned nil")
        }
        result(id)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    deviceIdChannel = channel
  }
}
