package com.iris.incidentreconstruction

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import androidx.core.app.ActivityCompat
import androidx.exifinterface.media.ExifInterface
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class IrisLocationRuntime(private val context: Context) {
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "readGps" -> readGps(call, result)
            "currentLocation" -> currentLocation(result)
            else -> return false
        }
        return true
    }

    private fun readGps(call: MethodCall, result: MethodChannel.Result) {
        try {
            val path = call.argument<String>("path") ?: return result.success(mapOf("status" to "UNAVAILABLE"))
            val latLong = ExifInterface(path).latLong
            if (latLong == null || !latLong[0].isFinite() || !latLong[1].isFinite()) return result.success(mapOf("status" to "NO_GPS"))
            result.success(mapOf("status" to "AVAILABLE", "latitude" to latLong[0], "longitude" to latLong[1]))
        } catch (_: Exception) { result.success(mapOf("status" to "UNAVAILABLE")) }
    }

    private fun currentLocation(result: MethodChannel.Result) {
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED && ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            (context as? Activity)?.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 4101)
            result.success(mapOf("status" to "PERMISSION_REQUIRED")); return
        }
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val location = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER).asSequence().mapNotNull { provider -> try { manager.getLastKnownLocation(provider) } catch (_: SecurityException) { null } }.maxByOrNull { it.time }
        if (location == null || !location.latitude.isFinite() || !location.longitude.isFinite()) result.success(mapOf("status" to "UNAVAILABLE")) else result.success(mapOf("status" to "AVAILABLE", "latitude" to location.latitude, "longitude" to location.longitude))
    }
}
