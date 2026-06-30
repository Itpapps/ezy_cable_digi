package com.example.ezi_cable_digi

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.provider.Settings
import android.telephony.TelephonyManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "ezy_cable_digi/device_id"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getDeviceIdentifier") {
                val identifier = getDeviceIdentifier()
                result.success(identifier ?: "")
            } else {
                result.notImplemented()
            }
        }
    }

    @SuppressLint("HardwareIds")
    private fun getDeviceIdentifier(): String? {
        return if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
            val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            telephonyManager?.deviceId
        } else {
            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        }
    }
}
