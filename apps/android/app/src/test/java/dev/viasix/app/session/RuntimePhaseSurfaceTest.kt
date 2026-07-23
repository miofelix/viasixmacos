package dev.viasix.app.session

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class RuntimePhaseSurfaceTest {
    @Test
    fun serviceActivityAndTileSharePersistedConnectionPhase() {
        val service =
            resolve(
                "src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
                "app/src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
            ).readText()
        val store =
            resolve(
                "src/main/java/dev/viasix/app/session/SessionRuntimeStore.kt",
                "app/src/main/java/dev/viasix/app/session/SessionRuntimeStore.kt",
            ).readText()
        val activity =
            resolve(
                "src/main/java/dev/viasix/app/MainActivity.kt",
                "app/src/main/java/dev/viasix/app/MainActivity.kt",
            ).readText()
        val tile =
            resolve(
                "src/main/java/dev/viasix/app/tile/ViaSixTileService.kt",
                "app/src/main/java/dev/viasix/app/tile/ViaSixTileService.kt",
            ).readText()

        assertTrue(service.contains("phase = ConnectionPhase.STARTING"))
        assertTrue(service.contains("phase = ConnectionPhase.RUNNING"))
        assertTrue(service.contains("phase = ConnectionPhase.STOPPING"))
        assertTrue(service.contains("phase = ConnectionPhase.STOPPED"))
        assertTrue(service.contains(".putString(KEY_PHASE, phase.wire)"))
        assertTrue(store.contains("ConnectionPhase.parse"))
        assertTrue(store.contains("phase.isActiveOrTransitioning"))
        assertTrue(activity.contains("runtimePhase = initialRuntime.phase"))
        assertTrue(activity.contains("runtimeStatus.phase"))
        assertTrue(tile.contains("VpnSessionCommands.runtimePhase(this)"))
        assertTrue(tile.contains("正在连接 · 点按取消"))
        assertTrue(tile.contains("正在断开…"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
