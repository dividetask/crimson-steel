package com.dividetask.crimsonsteel.net

import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.NetworkInterface
import java.net.SocketTimeoutException

/** A Crimson Steel server found on the network. */
data class ServerInfo(val host: String, val port: Int, val name: String) {
    val baseUrl: String get() = "http://$host:$port"
}

/**
 * Finds the Crimson Steel server on the same Wi-Fi network without asking for
 * an IP address: broadcasts a UDP probe and takes the first valid reply
 * (lib/lan_discovery.rb on the server). The reply's source address is the
 * server's address; the reply body carries its HTTP port.
 */
object ServerLocator {
    const val PORT = 47567
    const val PROBE = "CRIMSON_STEEL_DISCOVER 1"
    const val SERVICE = "crimson-steel"

    /** Parse a discovery reply; null if it is not from a Crimson Steel server. */
    fun parseReply(body: String, fromHost: String): ServerInfo? = runCatching {
        val j = JSONObject(body)
        if (j.optString("service") != SERVICE) return null
        val port = j.getInt("http_port")
        if (port !in 1..65535) return null
        ServerInfo(fromHost, port, j.optString("name"))
    }.getOrNull()

    /** Blocking. Call from a background thread. */
    fun discover(attempts: Int = 3, listenMs: Long = 1200): ServerInfo? {
        val probe = PROBE.toByteArray()
        DatagramSocket().use { socket ->
            socket.broadcast = true
            socket.soTimeout = 250
            val targets = (broadcastAddresses() + InetAddress.getByName("255.255.255.255")).distinct()
            val buf = ByteArray(1024)
            repeat(attempts) {
                for (t in targets) runCatching { socket.send(DatagramPacket(probe, probe.size, t, PORT)) }
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
                    parseReply(body, host)?.let { return it }
                }
            }
        }
        return null
    }

    /** The subnet broadcast address of every active, non-loopback interface (e.g. 192.168.1.255). */
    private fun broadcastAddresses(): List<InetAddress> = runCatching {
        NetworkInterface.getNetworkInterfaces().toList()
            .filter { it.isUp && !it.isLoopback }
            .flatMap { nic -> nic.interfaceAddresses.mapNotNull { it.broadcast } }
    }.getOrDefault(emptyList())
}
