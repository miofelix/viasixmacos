package dev.viasix.app.tun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException
import java.io.InputStream
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class Socks5UdpRelayLifecycleTest {
    @Test
    fun protectsControlBeforeConnectAndClosesAssociation() {
        val loopback = InetAddress.getLoopbackAddress()
        DatagramSocket(0, loopback).use { udpTarget ->
            ServerSocket(0, 1, loopback).use { server ->
                val controlClosed = AtomicBoolean(false)
                val accepted =
                    thread(start = true, isDaemon = true) {
                        server.accept().use { socket ->
                            val input = socket.getInputStream()
                            val output = socket.getOutputStream()
                            assertEquals(listOf(5, 1, 0), readFully(input, 3).map { it.toInt() })
                            output.write(byteArrayOf(0x05, 0x00))
                            output.flush()
                            assertEquals(0x03, readFully(input, 10)[1].toInt())
                            output.write(
                                byteArrayOf(
                                    0x05,
                                    0x00,
                                    0x00,
                                    0x01,
                                    127,
                                    0,
                                    0,
                                    1,
                                    ((udpTarget.localPort ushr 8) and 0xff).toByte(),
                                    (udpTarget.localPort and 0xff).toByte(),
                                ),
                            )
                            output.flush()
                            controlClosed.set(input.read() == -1)
                        }
                    }
                var protectedBeforeConnect = false
                var datagramProtected = false

                Socks5UdpRelay.open(
                    proxyHost = loopback.hostAddress ?: "127.0.0.1",
                    proxyPort = server.localPort,
                    protect = { socket ->
                        protectedBeforeConnect = !socket.isConnected && !socket.isClosed
                        true
                    },
                    protectDatagram = { socket ->
                        datagramProtected = !socket.isClosed
                        true
                    },
                ).use { relay ->
                    assertTrue(relay.isOpen)
                }

                accepted.join(2_000)
                assertFalse(accepted.isAlive)
                assertTrue(protectedBeforeConnect)
                assertTrue(datagramProtected)
                assertTrue(controlClosed.get())
            }
        }
    }

    @Test
    fun controlProtectFailureClosesWithoutConnecting() {
        var rejectedSocket: Socket? = null
        try {
            Socks5UdpRelay.open(
                proxyHost = InetAddress.getLoopbackAddress().hostAddress ?: "127.0.0.1",
                proxyPort = 53,
                protect = { socket ->
                    rejectedSocket = socket
                    false
                },
            )
            fail("expected protect failure")
        } catch (error: IOException) {
            assertTrue(error.message.orEmpty().contains("protect"))
        }
        assertTrue(rejectedSocket?.isClosed == true)
        assertFalse(rejectedSocket?.isConnected == true)
    }

    private fun readFully(input: InputStream, count: Int): ByteArray {
        val bytes = ByteArray(count)
        var offset = 0
        while (offset < count) {
            val read = input.read(bytes, offset, count - offset)
            if (read < 0) error("unexpected EOF")
            offset += read
        }
        return bytes
    }
}
