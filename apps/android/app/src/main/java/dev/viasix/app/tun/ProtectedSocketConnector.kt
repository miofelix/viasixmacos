package dev.viasix.app.tun

import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket

/** Opens a direct TCP socket only after the VPN service has excluded it from the tunnel. */
internal object ProtectedSocketConnector {
    fun connect(
        targetHost: InetAddress,
        targetPort: Int,
        protect: (Socket) -> Boolean,
        connectTimeoutMs: Int = 10_000,
    ): Socket =
        connectWithSocket(
            socket = Socket(),
            targetHost = targetHost,
            targetPort = targetPort,
            protect = protect,
            connectTimeoutMs = connectTimeoutMs,
        )

    fun connectWithSocket(
        socket: Socket,
        targetHost: InetAddress,
        targetPort: Int,
        protect: (Socket) -> Boolean,
        connectTimeoutMs: Int = 10_000,
    ): Socket =
        try {
            socket.tcpNoDelay = true
            if (!protect(socket)) {
                throw IOException("VpnService.protect(socket) failed")
            }
            socket.connect(InetSocketAddress(targetHost, targetPort), connectTimeoutMs)
            socket
        } catch (error: Exception) {
            try {
                socket.close()
            } catch (_: Exception) {
            }
            throw error
        }
}
