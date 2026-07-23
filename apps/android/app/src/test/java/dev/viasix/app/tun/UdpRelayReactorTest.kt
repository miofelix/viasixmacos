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
import java.nio.channels.ClosedSelectorException
import java.nio.channels.Selector
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
    fun explicitCloseDoesNotNotifyOwner() {
        val fatalCount = AtomicInteger(0)
        val reactor = UdpRelayReactor(onFatal = { fatalCount.incrementAndGet() })

        reactor.start()
        reactor.close()

        assertEquals(0, fatalCount.get())
    }

    @Test
    fun selectorFailureNotifiesOwner() {
        val selector = Selector.open().also { it.close() }
        val fatal = AtomicReference<Throwable?>(null)
        val notified = CountDownLatch(1)
        val reactor =
            UdpRelayReactor(
                controlProbeIntervalMs = 25L,
                onFatal = { error ->
                    fatal.set(error)
                    notified.countDown()
                },
                selectorFactory = { selector },
            )
        try {
            reactor.start()

            assertTrue("selector failure was not reported", notified.await(2, TimeUnit.SECONDS))
            assertTrue(fatal.get() is ClosedSelectorException)
        } finally {
            reactor.close()
        }
    }

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

                assertEquals(
                    UdpRelayReactor.SendResult.QUEUED,
                    reactor.send(
                        relay = first,
                        remote = InetAddress.getByName("192.0.2.10"),
                        remotePort = 443,
                        payload = "first".toByteArray(),
                    ),
                )
                assertEquals(
                    UdpRelayReactor.SendResult.QUEUED,
                    reactor.send(
                        relay = second,
                        remote = InetAddress.getByName("2001:db8::20"),
                        remotePort = 53,
                        payload = "second".toByteArray(),
                    ),
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
    fun boundsQueuedWritesWithoutClosingRelay() {
        FakeSocks5UdpServer(expectedAssociations = 1).use { proxy ->
            val relay = proxy.openRelay()
            val reactor =
                UdpRelayReactor(
                    controlProbeIntervalMs = 25L,
                    maxQueuedDatagrams = 2,
                    maxQueuedBytes = 1_024,
                )
            val callbackEntered = CountDownLatch(1)
            val releaseCallback = CountDownLatch(1)
            try {
                reactor.start()
                assertTrue(
                    reactor.register(
                        relay = relay,
                        onDatagram = {
                            callbackEntered.countDown()
                            releaseCallback.await(2, TimeUnit.SECONDS)
                        },
                        onClosed = {},
                    ),
                )
                assertEquals(
                    UdpRelayReactor.SendResult.QUEUED,
                    reactor.send(relay, InetAddress.getByName("192.0.2.1"), 443, byteArrayOf(1)),
                )
                assertTrue("reactor callback did not block", callbackEntered.await(2, TimeUnit.SECONDS))

                assertEquals(
                    UdpRelayReactor.SendResult.QUEUED,
                    reactor.send(relay, InetAddress.getByName("192.0.2.2"), 443, byteArrayOf(2)),
                )
                assertEquals(
                    UdpRelayReactor.SendResult.QUEUED,
                    reactor.send(relay, InetAddress.getByName("192.0.2.3"), 443, byteArrayOf(3)),
                )
                assertEquals(
                    UdpRelayReactor.SendResult.QUEUE_FULL,
                    reactor.send(relay, InetAddress.getByName("192.0.2.4"), 443, byteArrayOf(4)),
                )
                assertTrue(relay.isOpen)
            } finally {
                releaseCallback.countDown()
                reactor.close()
                relay.close()
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

    @Test
    fun explicitUnregisterRemovesRelayWithoutLifecycleCallback() {
        FakeSocks5UdpServer(expectedAssociations = 1).use { proxy ->
            val relay = proxy.openRelay()
            val reactor = UdpRelayReactor(controlProbeIntervalMs = 25L)
            val closeCount = AtomicInteger(0)
            try {
                reactor.start()
                assertTrue(
                    reactor.register(
                        relay = relay,
                        onDatagram = {},
                        onClosed = { closeCount.incrementAndGet() },
                    ),
                )
                assertEquals(1, reactor.registrationCount)

                assertTrue(reactor.unregister(relay))

                assertEquals(0, reactor.registrationCount)
                assertFalse(relay.isOpen)
                assertEquals(0, closeCount.get())
                assertEquals(
                    UdpRelayReactor.SendResult.UNAVAILABLE,
                    reactor.send(relay, InetAddress.getByName("192.0.2.1"), 443, byteArrayOf(1)),
                )
            } finally {
                reactor.close()
                relay.close()
            }
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
