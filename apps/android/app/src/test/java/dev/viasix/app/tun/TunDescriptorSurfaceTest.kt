package dev.viasix.app.tun

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TunDescriptorSurfaceTest {
    @Test
    fun fullTunnelUsesBlockingDescriptorForFileChannelReader() {
        val service =
            resolve(
                "src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
                "app/src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
            ).readText()
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()

        assertTrue(service.contains(".setBlocking(fullTunnel)"))
        assertTrue(service.contains("non-blocking TUN descriptor"))
        assertTrue(engine.contains("input.read(buffer)"))
        assertTrue(engine.contains("FileInputStream(tun.fileDescriptor).channel"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
