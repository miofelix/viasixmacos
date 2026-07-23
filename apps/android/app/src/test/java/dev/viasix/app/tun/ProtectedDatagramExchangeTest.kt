package dev.viasix.app.tun

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ProtectedDatagramExchangeTest {
    private val loopback = InetAddress.getLoopbackAddress()

    @Test
    fun protectsBeforeConnectFiltersSpoofedSourceAndKeepsLargeResponse() {
        DatagramSocket(0, loopback).use { server ->
            DatagramSocket(0, loopback).use { attacker ->
                val serverWorker = Executors.newSingleThreadExecutor()
                try {
                    val request = byteArrayOf(1, 2, 3, 4)
                    val legitimate = ByteArray(8_192) { (it and 0xff).toByte() }
                    val handled =
                        serverWorker.submit<Boolean> {
                            val receivedBytes = ByteArray(512)
                            val received = DatagramPacket(receivedBytes, receivedBytes.size)
                            server.receive(received)
                            val spoof = byteArrayOf(9, 9, 9)
                            attacker.send(
                                DatagramPacket(
                                    spoof,
                                    spoof.size,
                                    received.socketAddress,
                                ),
                            )
                            server.send(
                                DatagramPacket(
                                    legitimate,
                                    legitimate.size,
                                    received.socketAddress,
                                ),
                            )
                            request.contentEquals(received.data.copyOf(received.length))
                        }
                    var protectedBeforeConnect = false

                    val response =
                        ProtectedDatagramExchange.exchange(
                            target = loopback,
                            targetPort = server.localPort,
                            request = request,
                            protect = { socket ->
                                protectedBeforeConnect = !socket.isConnected && !socket.isClosed
                                true
                            },
                            timeoutMs = 1_000,
                        )

                    assertTrue(handled.get(2, TimeUnit.SECONDS))
                    assertTrue(protectedBeforeConnect)
                    assertArrayEquals(legitimate, response)
                } finally {
                    serverWorker.shutdownNow()
                }
            }
        }
    }

    @Test
    fun protectFailureClosesSocketBeforeConnecting() {
        var rejectedSocket: DatagramSocket? = null

        assertThrows(IOException::class.java) {
            ProtectedDatagramExchange.exchange(
                target = loopback,
                targetPort = 53,
                request = byteArrayOf(1),
                protect = { socket ->
                    rejectedSocket = socket
                    false
                },
            )
        }

        assertTrue(rejectedSocket?.isClosed == true)
        assertFalse(rejectedSocket?.isConnected == true)
    }

    @Test
    fun validationFailureClosesSuppliedSocket() {
        val socket = DatagramSocket()

        assertThrows(IllegalArgumentException::class.java) {
            ProtectedDatagramExchange.exchangeWithSocket(
                socket = socket,
                target = loopback,
                targetPort = 0,
                request = byteArrayOf(1),
                protect = { true },
            )
        }

        assertTrue(socket.isClosed)
    }
}
