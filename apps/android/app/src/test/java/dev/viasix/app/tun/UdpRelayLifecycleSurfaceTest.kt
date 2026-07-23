package dev.viasix.app.tun

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class UdpRelayLifecycleSurfaceTest {
    @Test
    fun idleRelaysAreClosedWithoutWaitingForAnotherDatagram() {
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()
        val table =
            resolve(
                "src/main/java/dev/viasix/app/tun/UdpClientEndpointTable.kt",
                "app/src/main/java/dev/viasix/app/tun/UdpClientEndpointTable.kt",
            ).readText()
        val reactor =
            resolve(
                "src/main/java/dev/viasix/app/tun/UdpRelayReactor.kt",
                "app/src/main/java/dev/viasix/app/tun/UdpRelayReactor.kt",
            ).readText()

        assertTrue(engine.contains("maintenanceExecutor.scheduleWithFixedDelay"))
        assertTrue(engine.contains("purgeIdleUdpClients()"))
        assertTrue(engine.contains("UDP_IDLE_CLEANUP_INTERVAL_MS"))
        assertTrue(engine.contains("udpClients.purgeExpired(::closeExpiredUdpRelay)"))
        assertTrue(engine.contains("udpRelays.remove(clientRelay.endpoint.key(), clientRelay)"))
        assertTrue(engine.contains("clientRelay.publishRelay(relay)"))
        assertTrue(engine.contains("private val udpRelayReactor = UdpRelayReactor()"))
        assertTrue(engine.contains("udpRelayReactor.register("))
        assertFalse(engine.contains("startUdpReceiver"))
        assertFalse(engine.contains("relay.receive(200)"))
        assertTrue(reactor.contains("Selector.open()"))
        assertTrue(reactor.contains("MAX_DATAGRAMS_PER_TURN"))
        assertTrue(reactor.contains("probeControlConnection()"))
        assertTrue(table.contains("System.nanoTime() / 1_000_000L"))
        assertTrue(table.contains("purgeExpired(onExpired: (Endpoint) -> Unit = {})"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
