package com.dividetask.crimsonsteel.net

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import com.dividetask.crimsonsteel.debug.DebugLog

/**
 * The phone's Wi-Fi network, so the app can talk to the server on the LAN even
 * when a VPN is on. With a VPN, Android sends ordinary traffic into the tunnel,
 * which usually can't reach 192.168.x.x addresses at home; a connection opened
 * on the Wi-Fi [Network] goes straight to the LAN instead (unless the VPN is
 * set to block that).
 */
object LocalNetwork {
    private const val TAG = "network"

    private fun cm(ctx: Context) = ctx.getSystemService(ConnectivityManager::class.java)

    /** The connected Wi-Fi network, or null (no Wi-Fi). */
    fun wifi(ctx: Context): Network? = runCatching {
        val cm = cm(ctx) ?: return null
        @Suppress("DEPRECATION")
        cm.allNetworks.firstOrNull { n ->
            val caps = cm.getNetworkCapabilities(n) ?: return@firstOrNull false
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) && !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        }
    }.onFailure { DebugLog.e(TAG, "could not look up the Wi-Fi network", it) }.getOrNull()

    /** True when a VPN is running on the phone. */
    fun vpnActive(ctx: Context): Boolean = runCatching {
        val cm = cm(ctx) ?: return false
        @Suppress("DEPRECATION")
        cm.allNetworks.any { n -> cm.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true }
    }.getOrDefault(false)

    /** A connection opener bound to the Wi-Fi network, or null to use the default route. */
    fun opener(ctx: Context): ((java.net.URL) -> java.net.URLConnection)? {
        val wifi = wifi(ctx)
        val vpn = vpnActive(ctx)
        DebugLog.i(TAG, "Wi-Fi network: ${if (wifi != null) "found" else "none"}; VPN: ${if (vpn) "ON" else "off"}" +
            if (wifi != null) " — connecting to the server over Wi-Fi directly" else "")
        return wifi?.let { n -> { url: java.net.URL -> n.openConnection(url) } }
    }
}
