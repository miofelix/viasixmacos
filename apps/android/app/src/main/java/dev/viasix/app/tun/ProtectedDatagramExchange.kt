package dev.viasix.app.tun

import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress

/** Executes one protected, source-bound UDP request/response exchange. */
internal object ProtectedDatagramExchange {
    fun exchange(
        target: InetAddress,
        targetPort: Int,
        request: ByteArray,
        protect: (DatagramSocket) -> Boolean,
        timeoutMs: Int = 5_000,
        maxResponseBytes: Int = MAX_UDP_DATAGRAM_BYTES,
    ): ByteArray {
        require(targetPort in 1..0xffff) { "UDP target port must be 1..65535" }
        require(timeoutMs >= 0) { "UDP timeout must not be negative" }
        require(maxResponseBytes in 1..MAX_UDP_DATAGRAM_BYTES) {
            "UDP response capacity must be 1..$MAX_UDP_DATAGRAM_BYTES"
        }
        return DatagramSocket().use { socket ->
            if (!protect(socket)) throw IOException("VpnService.protect(datagram) failed")
            socket.soTimeout = timeoutMs
            socket.connect(InetSocketAddress(target, targetPort))
            socket.send(DatagramPacket(request, request.size))

            val responseBytes = ByteArray(maxResponseBytes)
            val response = DatagramPacket(responseBytes, responseBytes.size)
            socket.receive(response)
            response.data.copyOfRange(response.offset, response.offset + response.length)
        }
    }

    private const val MAX_UDP_DATAGRAM_BYTES = 65_535
}
