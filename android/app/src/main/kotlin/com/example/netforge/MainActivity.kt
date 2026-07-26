package com.example.netforge

import android.Manifest
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.location.LocationManager
import android.provider.Settings
import android.text.format.Formatter
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.NetworkInterface

class MainActivity : FlutterActivity() {
    private val channelName = "netforge/device_status"
    private val permissionRequestCode = 7412
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> result.success(readStatus())
                    "requestPermissions" -> requestStatusPermissions(result)
                    "getNearbyAccessPoints" -> getNearbyAccessPoints(result)
                    "openLocationSettings" -> {
                        startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION", "MissingPermission")
    private fun getNearbyAccessPoints(result: MethodChannel.Result) {
        if (requiredWifiPermissions().isNotEmpty()) {
            result.error(
                "permissions_required",
                "Location and nearby Wi-Fi permissions are required.",
                null,
            )
            return
        }
        val location = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        if (Build.VERSION.SDK_INT >= 28 && !location.isLocationEnabled) {
            result.error(
                "location_disabled",
                "Turn on Location Services to view nearby access points.",
                null,
            )
            return
        }
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (!wifi.isWifiEnabled) {
            result.error("wifi_disabled", "Turn on Wi-Fi to scan nearby access points.", null)
            return
        }
        val scanStarted = wifi.startScan()
        Handler(Looper.getMainLooper()).postDelayed(
            { result.success(readNearbyAccessPoints(wifi)) },
            if (scanStarted) 1800L else 0L,
        )
    }

    @Suppress("DEPRECATION", "MissingPermission")
    private fun readNearbyAccessPoints(wifi: WifiManager): List<Map<String, Any>> =
        wifi.scanResults
            .sortedByDescending { it.level }
            .map { accessPoint ->
                mapOf(
                    "ssid" to accessPoint.SSID,
                    "bssid" to accessPoint.BSSID.uppercase(),
                    "level" to accessPoint.level,
                    "frequency" to accessPoint.frequency,
                    "channel" to wifiChannel(accessPoint.frequency),
                    "security" to accessPoint.capabilities
                        .removePrefix("[")
                        .removeSuffix("]")
                        .replace("][", " · "),
                )
            }

    private fun wifiChannel(frequency: Int): Int =
        when {
            frequency == 2484 -> 14
            frequency in 2412..2472 -> (frequency - 2407) / 5
            frequency in 5000..5895 -> (frequency - 5000) / 5
            frequency in 5955..7115 -> (frequency - 5950) / 5
            else -> 0
        }

    private fun requiredWifiPermissions(): List<String> {
        val permissions = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION)
        if (Build.VERSION.SDK_INT >= 33) {
            permissions.add(Manifest.permission.NEARBY_WIFI_DEVICES)
        }
        return permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestStatusPermissions(result: MethodChannel.Result) {
        val missing = requiredWifiPermissions()
        if (missing.isEmpty()) {
            result.success(readStatus())
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_pending", "A permission request is already open.", null)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), permissionRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            pendingPermissionResult?.success(readStatus())
            pendingPermissionResult = null
        }
    }

    @Suppress("DEPRECATION", "MissingPermission")
    private fun readStatus(): Map<String, Any?> {
        val status = mutableMapOf<String, Any?>()
        status["permissionsRequired"] = requiredWifiPermissions().isNotEmpty()
        val location = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        status["locationEnabled"] =
            if (Build.VERSION.SDK_INT >= 28) location.isLocationEnabled else true

        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        status["wifiEnabled"] = wifi.isWifiEnabled
        val modernConnection = if (Build.VERSION.SDK_INT >= 31) {
            val connectivity =
                getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            connectivity.getNetworkCapabilities(connectivity.activeNetwork)
                ?.transportInfo as? WifiInfo
        } else {
            null
        }
        val legacyConnection = wifi.connectionInfo
        val connection = listOfNotNull(modernConnection, legacyConnection).firstOrNull {
            !it.ssid.isNullOrBlank() && it.ssid != "<unknown ssid>"
        } ?: modernConnection ?: legacyConnection
        val rawSsid = connection?.ssid
        if (!rawSsid.isNullOrBlank() && rawSsid != "<unknown ssid>") {
            status["ssid"] = rawSsid.trim('"')
        }
        val bssid = connection?.bssid
        if (!bssid.isNullOrBlank() && bssid != "02:00:00:00:00:00") {
            status["bssid"] = bssid.uppercase()
        }
        val gateway = Formatter.formatIpAddress(wifi.dhcpInfo?.gateway ?: 0)
        if (gateway != "0.0.0.0") status["gateway"] = gateway

        try {
            val localMac = NetworkInterface.getNetworkInterfaces().asSequence().toList()
                .firstOrNull { it.name == "wlan0" }
                ?.hardwareAddress
                ?.joinToString(":") { "%02X".format(it) }
            if (!localMac.isNullOrBlank() && localMac != "02:00:00:00:00:00") {
                status["localMac"] = localMac
            }
        } catch (_: Exception) {
            // Android may intentionally hide the interface MAC.
        }

        if (Build.VERSION.SDK_INT < 31 ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_CONNECT,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            try {
                val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                val devices = manager.getConnectedDevices(BluetoothProfile.GATT).map {
                    mapOf(
                        "name" to (it.name ?: "Bluetooth device"),
                        "address" to it.address,
                    )
                }
                status["bluetooth"] = devices
            } catch (_: Exception) {
                // Bluetooth may be unavailable or disabled.
            }
        }
        return status
    }
}
