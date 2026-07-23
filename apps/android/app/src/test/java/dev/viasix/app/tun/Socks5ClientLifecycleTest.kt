package dev.viasix.app.tun

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.io.InputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class Socks5ClientLifecycleTest {
    private val loopback = InetAddress.getLoopbackAddress()

    @Test
    fun completesHandshakeThenRestoresBlockingReadTimeout() {
        ServerSocket(0, 1, loopback).use { server ->
            val serverWorker = Executors.newSingleThreadExecutor()
            try {
                val controlClosed =
                    serverWorker.submit<Boolean> {
                        server.accept().use { socket ->
                            val input = socket.getInputStream()
                            val output = socket.getOutputStream()
                            assertArrayEquals(byteArrayOf(0x05, 0x01, 0x00), readFully(input, 3))
                            output.write(byteArrayOf(0x05, 0x00))
                            output.flush()
                            val request = readFully(input, 10)
                            assertEquals(0x01, request[1].toInt())
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
                                    0x1f,
                                    0x90.toByte(),
                                ),
                            )
                            output.flush()
                            input.read() == -1
                        }
                    }

                Socks5Client.connect(
                    proxyHost = loopback.hostAddress ?: "127.0.0.1",
                    proxyPort = server.localPort,
                    targetHost = InetAddress.getByName("1.1.1.1"),
                    targetPort = 443,
                    connectTimeoutMs = 1_000,
                    handshakeTimeoutMs = 1_000,
                ).use { socket ->
                    assertTrue(socket.isConnected)
                    assertEquals(0, socket.soTimeout)
                }

                assertTrue(controlClosed.get(2, TimeUnit.SECONDS))
            } finally {
                serverWorker.shutdownNow()
            }
        }
    }

    @Test
    fun stalledGreetingTimesOutAndClosesSocket() {
        ServerSocket(0, 1, loopback).use { server ->
            val serverWorker = Executors.newSingleThreadExecutor()
            try {
                val controlClosed =
                    serverWorker.submit<Boolean> {
                        server.accept().use { socket ->
                            assertArrayEquals(
                                byteArrayOf(0x05, 0x01, 0x00),
                                readFully(socket.getInputStream(), 3),
                            )
                            socket.getInputStream().read() == -1
                        }
                    }

                assertThrows(IOException::class.java) {
                    Socks5Client.connect(
                        proxyHost = loopback.hostAddress ?: "127.0.0.1",
                        proxyPort = server.localPort,
                        targetHost = InetAddress.getByName("1.1.1.1"),
                        targetPort = 443,
                        connectTimeoutMs = 1_000,
                        handshakeTimeoutMs = 100,
                    )
                }
                assertTrue(controlClosed.get(2, TimeUnit.SECONDS))
            } finally {
                serverWorker.shutdownNow()
            }
        }
    }

    @Test
    fun closingSuppliedSocketCancelsStalledGreeting() {
        ServerSocket(0, 1, loopback).use { server ->
            val serverWorker = Executors.newSingleThreadExecutor()
            val clientWorker = Executors.newSingleThreadExecutor()
            val greetingRead = CountDownLatch(1)
            try {
                val controlClosed =
                    serverWorker.submit<Boolean> {
                        server.accept().use { accepted ->
                            assertArrayEquals(
                                byteArrayOf(0x05, 0x01, 0x00),
                                readFully(accepted.getInputStream(), 3),
                            )
                            greetingRead.countDown()
                            accepted.getInputStream().read() == -1
                        }
                    }
                val socket = Socket()
                val failure =
                    clientWorker.submit<Throwable?> {
                        try {
                            Socks5Client.connectWithSocket(
                                socket = socket,
                                proxyHost = loopback.hostAddress ?: "127.0.0.1",
                                proxyPort = server.localPort,
                                targetHost = InetAddress.getByName("1.1.1.1"),
                                targetPort = 443,
                                connectTimeoutMs = 1_000,
                                handshakeTimeoutMs = 10_000,
                            )
                            null
                        } catch (error: Throwable) {
                            error
                        }
                    }
                assertTrue(greetingRead.await(2, TimeUnit.SECONDS))

                socket.close()

                assertTrue(failure.get(2, TimeUnit.SECONDS) is IOException)
                assertTrue(controlClosed.get(2, TimeUnit.SECONDS))
            } finally {
                clientWorker.shutdownNow()
                serverWorker.shutdownNow()
            }
        }
    }

    @Test
    fun rejectsInvalidTargetBeforeOpeningProxySocket() {
        assertThrows(IllegalArgumentException::class.java) {
            Socks5Client.connect(
                proxyHost = loopback.hostAddress ?: "127.0.0.1",
                proxyPort = 1,
                targetHost = InetAddress.getByName("1.1.1.1"),
                targetPort = 0,
            )
        }
    }

    @Test
    fun validationFailureClosesSuppliedSocket() {
        val socket = Socket()

        assertThrows(IllegalArgumentException::class.java) {
            Socks5Client.connectWithSocket(
                socket = socket,
                proxyHost = loopback.hostAddress ?: "127.0.0.1",
                proxyPort = 1,
                targetHost = InetAddress.getByName("1.1.1.1"),
                targetPort = 0,
            )
        }

        assertTrue(socket.isClosed)
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
