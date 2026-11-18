package com.dividetask.crimsonsteel.net

import com.dividetask.crimsonsteel.debug.DebugLog
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.net.SocketTimeoutException

/** A Crimson Steel server found on the network. */
data class ServerInfo(val host: String, val port: Int, val name: String) {
    val baseUrl: String get() = "http://$host:$port"
}

/**
 * Finds the Crimson Steel server on the same Wi-Fi network without asking for
 * an IP address.
 *
 * [discover] broadcasts a UDP probe and takes the first valid reply
 * (lib/lan_discovery.rb on the server). The reply's source address is the
 * server's address; the reply body carries its HTTP port. There is no
 * fallback that probes other devices on the network.
 *
 * Every step is written to the debug log.
 */
object ServerLocator {
    const val PORT = 47567
    const val DEFAULT_HTTP_PORT = 4567
    const val PROBE = "CRIMSON_STEEL_DISCOVER 1"
    const val SERVICE = "crimson-steel"
    private const val TAG = "discovery"

    /** Parse a discovery reply; null if it is not from a Crimson Steel server. */
    fun parseReply(body: String, fromHost: String): ServerInfo? = runCatching {
        val j = JSONObject(body)
        if (j.optString("service") != SERVICE) return null
        val port = j.getInt("http_port")
        if (port !in 1..65535) return null
        ServerInfo(fromHost, port, j.optString("name"))
    }.getOrNull()

    /** This phone's IPv4 addresses with their prefix length and broadcast address (for the log and Settings). */
    data class LocalNet(val nic: String, val address: Inet4Address, val prefix: Int, val broadcast: InetAddress?)

    fun localNetworks(): List<LocalNet> = runCatching {
        NetworkInterface.getNetworkInterfaces().toList()
            .filter { it.isUp && !it.isLoopback }
            .flatMap { nic ->
                nic.interfaceAddresses.mapNotNull { ia ->
                    (ia.address as? Inet4Address)?.let { LocalNet(nic.name, it, ia.networkPrefixLength.toInt(), ia.broadcast) }
                }
            }
    }.onFailure { DebugLog.e(TAG, "listing network interfaces failed", it) }.getOrDefault(emptyList())

    /** Blocking. Call from a background thread. */
    fun discover(attempts: Int = 3, listenMs: Long = 1200): ServerInfo? {
        val probe = PROBE.toByteArray()
        val nets = localNetworks()
        if (nets.isEmpty()) DebugLog.i(TAG, "no active IPv4 network interface (is Wi-Fi on?)")
        nets.forEach { DebugLog.i(TAG, "interface ${it.nic}: ${it.address.hostAddress}/${it.prefix} broadcast ${it.broadcast?.hostAddress}") }
        val targets = (nets.mapNotNull { it.broadcast } + InetAddress.getByName("255.255.255.255")).distinct()
        try {
            DatagramSocket().use { socket ->
                socket.broadcast = true
                socket.soTimeout = 250
                val buf = ByteArray(1024)
                for (attempt in 1..attempts) {
                    for (t in targets) {
                        runCatching { socket.send(DatagramPacket(probe, probe.size, t, PORT)) }
                            .onSuccess { DebugLog.i(TAG, "attempt $attempt: probe sent to ${t.hostAddress}:$PORT") }
                            .onFailure { DebugLog.e(TAG, "attempt $attempt: probe to ${t.hostAddress}:$PORT failed", it) }
                    }
                    val deadline = System.currentTimeMillis() + listenMs
                    while (System.currentTimeMillis() < deadline) {
                        val packet = DatagramPacket(buf, buf.size)
                        try {
                            socket.receive(packet)
                        } catch (_: SocketTimeoutException) {
                            continue
                        }
                        val body = String(packet.data, 0, packet.length, Charsets.UTF_8)
                        val host = packet.address?.hostAddress ?: continue
                        val found = parseReply(body, host)
                        DebugLog.i(TAG, "reply from $host: ${body.take(200)}${if (found == null) " (ignored)" else ""}")
                        if (found != null) return found
                    }
                    DebugLog.i(TAG, "attempt $attempt: no reply within ${listenMs}ms")
                }
            }
        } catch (e: Exception) {
            DebugLog.e(TAG, "UDP discovery failed", e)
        }
        return null
    }
}
