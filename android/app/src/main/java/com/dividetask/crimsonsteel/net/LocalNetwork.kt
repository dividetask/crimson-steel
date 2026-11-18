package com.dividetask.crimsonsteel.net

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities

/**
 * Whether a VPN is running on the phone. Firewall apps such as NetGuard work
 * as a VPN, so this is shown in Settings, written to the debug log, and used
 * for the hint on the No server found screen. The app never routes around a
 * VPN: its connections always take the phone's normal route.
 */
object LocalNetwork {
    fun vpnActive(ctx: Context): Boolean = runCatching {
        val cm = ctx.getSystemService(ConnectivityManager::class.java) ?: return false
        @Suppress("DEPRECATION")
        cm.allNetworks.any { n -> cm.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true }
    }.getOrDefault(false)
}
