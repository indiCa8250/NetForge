package com.example.netforge

import android.Manifest
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.ActivityNotFoundException
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
import java.io.File
import java.net.NetworkInterface

class MainActivity : FlutterActivity() {
    private val channelName = "netforge/device_status"
    private val permissionRequestCode = 7412
    private val saveNetworkRequestCode = 7413
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveContent: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> result.success(readStatus())
                    "requestPermissions" -> requestStatusPermissions(result)
                    "getNearbyAccessPoints" -> getNearbyAccessPoints(result)
                    "connectToAccessPoint" -> connectToAccessPoint(call, result)
                    "getNeighborMacs" -> result.success(readNeighborMacs())
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url == null ||
                            (!url.startsWith("https://github.com/indiCa8250/NetForge/") &&
                                !url.startsWith(
                                    "https://api.github.com/repos/indiCa8250/NetForge/",
                                ))
                        ) {
                            result.error("invalid_url", "This link is not a NetForge update.", null)
                        } else {
                            startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)))
                            result.success(null)
                        }
                    }
                    "saveNetForgeFile" -> {
                        val name = call.argument<String>("name")
                        val content = call.argument<String>("content")
                        if (name.isNullOrBlank() || content == null) {
                            result.error("invalid_file", "The network export is invalid.", null)
                        } else if (pendingSaveResult != null) {
                            result.error("save_pending", "A save window is already open.", null)
                        } else {
                            pendingSaveResult = result
                            pendingSaveContent = content
                            startActivityForResult(
                                Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "application/json"
                                    putExtra(Intent.EXTRA_TITLE, name)
                                },
                                saveNetworkRequestCode,
                            )
                        }
                    }
                    "openLocationSettings" -> {
                        startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION", "MissingPermission")
    private fun connectToAccessPoint(call: MethodCall, result: MethodChannel.Result) {
        val ssid = call.argument<String>("ssid")?.trim().orEmpty()
        val requestedBssid = call.argument<String>("bssid")?.trim().orEmpty()
        if (ssid.isEmpty()) {
            result.error(
                "hidden_network",
                "Hidden networks must be connected from Android Wi-Fi settings.",
                null,
            )
            return
        }

        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        try {
            val current = wifi.connectionInfo
            val currentSsid = current?.ssid?.trim('"').orEmpty()
            val currentBssid = current?.bssid.orEmpty()
            val exactBssidRequested =
                requestedBssid.isNotEmpty() && requestedBssid != "02:00:00:00:00:00"
            if (currentSsid == ssid &&
                (!exactBssidRequested || currentBssid.equals(requestedBssid, ignoreCase = true))
            ) {
                result.success(
                    mapOf(
                        "status" to "already_connected",
                        "confirmationRequired" to false,
                        "message" to "Already connected to $ssid.",
                    ),
                )
                return
            }
        } catch (_: Exception) {
            // Android can withhold current connection details. The system Wi-Fi
            // UI below remains the authoritative and user-controlled fallback.
        }

        val actions = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                add(Settings.Panel.ACTION_WIFI)
            }
            add(Settings.ACTION_WIFI_SETTINGS)
        }
        for (action in actions) {
            try {
                startActivity(Intent(action))
                result.success(
                    mapOf(
                        "status" to "settings_opened",
                        "confirmationRequired" to true,
                        "message" to
                            "Android Wi-Fi controls opened. Select $ssid and confirm to connect.",
                    ),
                )
                return
            } catch (_: ActivityNotFoundException) {
                // Try the full Wi-Fi Settings activity next.
            } catch (_: SecurityException) {
                // An OEM can restrict a panel action; try the standard fallback.
            }
        }
        result.error(
            "wifi_settings_unavailable",
            "Android Wi-Fi settings could not be opened.",
            null,
        )
    }

    /**
     * Best-effort legacy neighbor-cache read.
     *
     * Android 10 and newer blocks regular apps from /proc/net, and Android has
     * no public replacement API that exposes arbitrary LAN peers' MAC
     * addresses. Returning an empty map is therefore expected and must not be
     * interpreted as proof that the peers have no MAC address.
     */
    private fun readNeighborMacs(): Map<String, String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return emptyMap()
        return try {
            val addresses = mutableMapOf<String, String>()
            File("/proc/net/arp").useLines { lines ->
                lines.drop(1).forEach { line ->
                    val columns = line.trim().split(Regex("\\s+"))
                    if (columns.size < 4 || !isIpv4Address(columns[0])) return@forEach
                    val flags =
                        columns[2].removePrefix("0x").toIntOrNull(16) ?: return@forEach
                    if ((flags and 0x2) == 0) return@forEach
                    val mac = columns[3].replace('-', ':').uppercase()
                    if (isUsableNeighborMac(mac)) addresses[columns[0]] = mac
                }
            }
            addresses
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun isIpv4Address(value: String): Boolean {
        val octets = value.split('.')
        return octets.size == 4 && octets.all {
            val octet = it.toIntOrNull()
            octet != null && octet in 0..255
        }
    }

    private fun isUsableNeighborMac(value: String): Boolean {
        if (!Regex("^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$").matches(value)) return false
        if (value == "00:00:00:00:00:00" || value == "FF:FF:FF:FF:FF:FF") return false
        val firstOctet = value.substring(0, 2).toInt(16)
        return (firstOctet and 1) == 0
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != saveNetworkRequestCode) return
        val result = pendingSaveResult
        val content = pendingSaveContent
        pendingSaveResult = null
        pendingSaveContent = null
        if (resultCode != RESULT_OK || data?.data == null || content == null) {
            result?.success(false)
            return
        }
        try {
            contentResolver.openOutputStream(data.data!!)?.bufferedWriter().use { writer ->
                writer?.write(content)
            }
            result?.success(true)
        } catch (exception: Exception) {
            result?.error("save_failed", exception.message ?: "Could not save network.", null)
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
