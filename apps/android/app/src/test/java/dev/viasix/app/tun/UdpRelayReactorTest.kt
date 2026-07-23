package dev.viasix.app.tun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.InputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

class UdpRelayReactorTest {
    @Test
    fun multiplexesMultipleRelaysOnOneReactorThread() {
        FakeSocks5UdpServer(expectedAssociations = 2).use { proxy ->
            val first = proxy.openRelay()
            val second = proxy.openRelay()
            val reactor = UdpRelayReactor(controlProbeIntervalMs = 25L)
            val received = Collections.synchronizedList(mutableListOf<String>())
            val callbackThreads = ConcurrentHashMap.newKeySet<String>()
            val callbacks = CountDownLatch(2)
            try {
                reactor.start()
                for (relay in listOf(first, second)) {
                    assertTrue(
                        reactor.register(
                            relay = relay,
                            onDatagram = { datagram ->
                                received += String(datagram.payload, Charsets.UTF_8)
                                callbackThreads += Thread.currentThread().name
                                callbacks.countDown()
                            },
                            onClosed = {},
                        ),
                    )
                }

                first.send(
                    remote = InetAddress.getByName("192.0.2.10"),
                    remotePort = 443,
                    payload = "first".toByteArray(),
                )
                second.send(
                    remote = InetAddress.getByName("2001:db8::20"),
                    remotePort = 53,
                    payload = "second".toByteArray(),
                )

                assertTrue("UDP callbacks timed out", callbacks.await(2, TimeUnit.SECONDS))
                assertEquals(setOf("first", "second"), received.toSet())
                assertEquals(setOf("viasix-udp-relay-reactor"), callbackThreads)
                proxy.assertHealthy()
            } finally {
                reactor.close()
                first.close()
                second.close()
            }
        }
    }

    @Test
    fun closedControlConnectionClosesRelayAndNotifiesOnce() {
        FakeSocks5UdpServer(expectedAssociations = 1).use { proxy ->
            val relay = proxy.openRelay()
            val reactor = UdpRelayReactor(controlProbeIntervalMs = 25L)
            val closed = CountDownLatch(1)
            val closeCount = AtomicInteger(0)
            try {
                reactor.start()
                assertTrue(
                    reactor.register(
                        relay = relay,
                        onDatagram = {},
                        onClosed = {
                            closeCount.incrementAndGet()
                            closed.countDown()
                        },
                    ),
                )

                proxy.closeControl(0)

                assertTrue("control EOF was not detected", closed.await(2, TimeUnit.SECONDS))
                assertFalse(relay.isOpen)
                assertEquals(1, closeCount.get())
                proxy.assertHealthy()
            } finally {
                reactor.close()
                relay.close()
            }
            assertEquals(1, closeCount.get())
        }
    }

    private class FakeSocks5UdpServer(
        expectedAssociations: Int,
    ) : AutoCloseable {
        private val loopback = InetAddress.getLoopbackAddress()
        private val closed = AtomicBoolean(false)
        private val failure = AtomicReference<Throwable?>(null)
        private val udp = DatagramSocket(0, loopback)
        private val controlServer = ServerSocket(0, expectedAssociations, loopback)
        private val controls = Collections.synchronizedList(mutableListOf<Socket>())
        private val acceptThread =
            thread(start = true, isDaemon = true, name = "test-socks5-udp-control") {
                try {
                    repeat(expectedAssociations) {
                        val socket = controlServer.accept()
                        performHandshake(socket)
                        controls += socket
                    }
                } catch (error: Throwable) {
                    if (!closed.get()) failure.compareAndSet(null, error)
                }
            }
        private val echoThread =
            thread(start = true, isDaemon = true, name = "test-socks5-udp-echo") {
                val buffer = ByteArray(65_535)
                try {
                    while (!closed.get()) {
                        val packet = DatagramPacket(buffer, buffer.size)
                        udp.receive(packet)
                        val reply = DatagramPacket(packet.data.copyOf(packet.length), packet.length)
                        reply.socketAddress = packet.socketAddress
                        udp.send(reply)
                    }
                } catch (error: SocketException) {
                    if (!closed.get()) failure.compareAndSet(null, error)
                } catch (error: Throwable) {
                    if (!closed.get()) failure.compareAndSet(null, error)
                }
            }

        fun openRelay(): Socks5UdpRelay =
            Socks5UdpRelay.open(
                proxyHost = loopback.hostAddress ?: "127.0.0.1",
                proxyPort = controlServer.localPort,
            )

        fun closeControl(index: Int) {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
            while (controls.size <= index && System.nanoTime() < deadline) {
                Thread.yield()
            }
            controls[index].close()
        }

        fun assertHealthy() {
            failure.get()?.let { throw AssertionError("fake SOCKS5 server failed", it) }
        }

        private fun performHandshake(socket: Socket) {
            val input = socket.getInputStream()
            val output = socket.getOutputStream()
            require(readFully(input, 3).contentEquals(byteArrayOf(0x05, 0x01, 0x00)))
            output.write(byteArrayOf(0x05, 0x00))
            output.flush()
            val associate = readFully(input, 10)
            require(associate[0] == 0x05.toByte() && associate[1] == 0x03.toByte())
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
                    ((udp.localPort ushr 8) and 0xff).toByte(),
                    (udp.localPort and 0xff).toByte(),
                ),
            )
            output.flush()
        }

        override fun close() {
            if (!closed.compareAndSet(false, true)) return
            try {
                controlServer.close()
            } catch (_: Exception) {
            }
            try {
                udp.close()
            } catch (_: Exception) {
            }
            synchronized(controls) {
                controls.forEach {
                    try {
                        it.close()
                    } catch (_: Exception) {
                    }
                }
            }
            acceptThread.join(2_000)
            echoThread.join(2_000)
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
}
