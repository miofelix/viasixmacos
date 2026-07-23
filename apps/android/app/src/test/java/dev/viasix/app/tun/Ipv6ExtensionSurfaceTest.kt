package dev.viasix.app.tun

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class Ipv6ExtensionSurfaceTest {
    @Test
    fun parserWalksExtensionsBeforeEngineDispatchesTransport() {
        val packet =
            resolve(
                "src/main/java/dev/viasix/app/tun/Packet.kt",
                "app/src/main/java/dev/viasix/app/tun/Packet.kt",
            ).readText()
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()

        assertTrue(packet.contains("while (isIpv6ExtensionHeader(nextHeader))"))
        assertTrue(packet.contains("MAX_IPV6_EXTENSION_HEADERS"))
        assertTrue(packet.contains("fragmentOffset != 0 || reservedBits != 0 || moreFragments"))
        assertTrue(packet.contains("headerLength = payloadOffset - start"))
        assertTrue(engine.contains("when (ip.nextHeader)"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
