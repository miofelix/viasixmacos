package dev.viasix.app.runtime

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class RuntimeComponentSurfaceTest {
    @Test
    fun installersAndSettingsExposeInspectionAndIndependentRepair() {
        val mihomo =
            resolve(
                "src/main/java/dev/viasix/app/mihomo/MihomoInstaller.kt",
                "app/src/main/java/dev/viasix/app/mihomo/MihomoInstaller.kt",
            ).readText()
        val cfst =
            resolve(
                "src/main/java/dev/viasix/app/cfst/CfstInstaller.kt",
                "app/src/main/java/dev/viasix/app/cfst/CfstInstaller.kt",
            ).readText()
        val settings =
            resolve(
                "src/main/java/dev/viasix/app/ui/screens/SettingsScreen.kt",
                "app/src/main/java/dev/viasix/app/ui/screens/SettingsScreen.kt",
            ).readText()
        val install =
            resolve(
                "src/main/java/dev/viasix/app/runtime/RuntimeBinaryInstall.kt",
                "app/src/main/java/dev/viasix/app/runtime/RuntimeBinaryInstall.kt",
            ).readText()

        assertTrue(mihomo.contains("inspectInstalled"))
        assertTrue(mihomo.contains("fun repair"))
        assertTrue(cfst.contains("inspectInstalled"))
        assertTrue(cfst.contains("fun repair"))
        assertTrue(settings.contains("RuntimeComponentId.MIHOMO"))
        assertTrue(settings.contains("RuntimeComponentId.CFST"))
        assertTrue(settings.contains("错误架构"))
        // Settings copy documents APK-native install; installer still uses atomic replace.
        assertTrue(settings.contains("APK 原生库"))
        assertTrue(settings.contains("libmihomo.so"))
        assertTrue(install.contains("StandardCopyOption.ATOMIC_MOVE"))
        assertTrue(install.contains("0b111_000_000"))
    }

    @Test
    fun repairCannotRaceInstallerOrCrossSectionRuntimeStarts() {
        val mihomo =
            resolve(
                "src/main/java/dev/viasix/app/mihomo/MihomoInstaller.kt",
                "app/src/main/java/dev/viasix/app/mihomo/MihomoInstaller.kt",
            ).readText()
        val cfst =
            resolve(
                "src/main/java/dev/viasix/app/cfst/CfstInstaller.kt",
                "app/src/main/java/dev/viasix/app/cfst/CfstInstaller.kt",
            ).readText()
        val activity =
            resolve(
                "src/main/java/dev/viasix/app/MainActivity.kt",
                "app/src/main/java/dev/viasix/app/MainActivity.kt",
            ).readText()
        val overview =
            resolve(
                "src/main/java/dev/viasix/app/ui/screens/OverviewScreen.kt",
                "app/src/main/java/dev/viasix/app/ui/screens/OverviewScreen.kt",
            ).readText()
        val nodes =
            resolve(
                "src/main/java/dev/viasix/app/ui/screens/NodesScreen.kt",
                "app/src/main/java/dev/viasix/app/ui/screens/NodesScreen.kt",
            ).readText()

        assertTrue(mihomo.contains("@Synchronized\n    fun installIfNeeded"))
        assertTrue(cfst.contains("@Synchronized\n    fun installIfNeeded"))
        assertTrue(activity.contains("repairing == RuntimeComponentId.MIHOMO"))
        assertTrue(activity.contains("repairing == RuntimeComponentId.CFST"))
        assertTrue(activity.contains("mihomo 正在修复，完成后再启动 VPN"))
        assertTrue(activity.contains("CFST 正在修复，完成后再开始测速"))
        assertTrue(overview.contains("内核修复中…"))
        assertTrue(overview.contains("CFST 修复中…"))
        assertTrue(nodes.contains("speed.canStartSpeedTest && !cfstRepairing"))
        assertTrue(nodes.contains("!speed.isRunning && looksValid && !cfstRepairing"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
