package com.astrotransit.astrotransit

import android.app.Activity
import android.content.Intent
import com.google.android.gms.common.api.ResolvableApiException
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.LocationSettingsRequest
import com.google.android.gms.location.Priority
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes the Play Services "turn on device location" dialog to Dart, so the
 * app can ask for GPS *in place* instead of sending the user to the system
 * settings screen (astrotransit/location_settings # requestEnable -> Boolean).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "astrotransit/location_settings"
    private val requestCheckSettings = 8471
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "requestEnable") {
                    requestLocationEnable(result)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun requestLocationEnable(result: MethodChannel.Result) {
        val locationRequest = LocationRequest
            .Builder(Priority.PRIORITY_HIGH_ACCURACY, 10_000L)
            .build()
        val settingsRequest = LocationSettingsRequest.Builder()
            .addLocationRequest(locationRequest)
            .build()

        LocationServices.getSettingsClient(this)
            .checkLocationSettings(settingsRequest)
            .addOnSuccessListener { result.success(true) }
            .addOnFailureListener { e ->
                if (e is ResolvableApiException) {
                    // Shows the native in-app dialog; answer arrives in
                    // onActivityResult.
                    pendingResult = result
                    try {
                        e.startResolutionForResult(this, requestCheckSettings)
                    } catch (_: Exception) {
                        pendingResult = null
                        result.success(false)
                    }
                } else {
                    // No Play Services / policy-blocked: caller falls back to
                    // the settings screen flow.
                    result.success(false)
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == requestCheckSettings) {
            pendingResult?.success(resultCode == Activity.RESULT_OK)
            pendingResult = null
        }
    }
}
