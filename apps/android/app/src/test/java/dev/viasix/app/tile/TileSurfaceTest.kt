package dev.viasix.app.tile

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Structural guard: Quick Settings tile (Clash/NekoBox-style) is registered and present.
 */
class TileSurfaceTest {
    @Test
    fun tileServiceAndManifestPresent() {
        val service =
            resolve(
                "src/main/java/dev/viasix/app/tile/ViaSixTileService.kt",
                "app/src/main/java/dev/viasix/app/tile/ViaSixTileService.kt",
                "apps/android/app/src/main/java/dev/viasix/app/tile/ViaSixTileService.kt",
            )
        val manifest =
            resolve(
                "src/main/AndroidManifest.xml",
                "app/src/main/AndroidManifest.xml",
                "apps/android/app/src/main/AndroidManifest.xml",
            )
        val serviceText = service.readText()
        val manifestText = manifest.readText()
        assertTrue(serviceText.contains("class ViaSixTileService"))
        assertTrue(serviceText.contains("VpnSessionCommands"))
        assertTrue(manifestText.contains("ViaSixTileService"))
        assertTrue(manifestText.contains("QS_TILE"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
