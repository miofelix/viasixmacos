package dev.viasix.app.backup

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class BackupPolicySurfaceTest {
    @Test
    fun manifestAndRulesKeepPrivateStateOutOfBackupAndDeviceTransfer() {
        val manifest = resolve("src/main/AndroidManifest.xml", "app/src/main/AndroidManifest.xml").readText()
        val legacy = resolve("src/main/res/xml/backup_rules.xml", "app/src/main/res/xml/backup_rules.xml").readText()
        val modern =
            resolve(
                "src/main/res/xml/data_extraction_rules.xml",
                "app/src/main/res/xml/data_extraction_rules.xml",
            ).readText()

        assertTrue(manifest.contains("android:allowBackup=\"false\""))
        assertTrue(manifest.contains("android:fullBackupContent=\"@xml/backup_rules\""))
        assertTrue(manifest.contains("android:dataExtractionRules=\"@xml/data_extraction_rules\""))
        assertExcludesEveryPrivateDomain(legacy)
        assertTrue(modern.contains("<cloud-backup>"))
        assertTrue(modern.contains("<device-transfer>"))
        assertExcludesEveryPrivateDomain(modern.substringBefore("</cloud-backup>"))
        assertExcludesEveryPrivateDomain(modern.substringAfter("<device-transfer>"))
        assertTrue(legacy.contains("viasix_session.xml"))
        assertTrue(legacy.contains("viasix_runtime.xml"))
        assertTrue(modern.contains("viasix_session.xml"))
        assertTrue(modern.contains("viasix_runtime.xml"))
        assertTrue(modern.contains("profiles/YAML"))
        assertTrue(modern.contains("controller secrets"))
    }

    private fun assertExcludesEveryPrivateDomain(xml: String) {
        listOf(
            "root",
            "file",
            "database",
            "sharedpref",
            "external",
            "device_root",
            "device_file",
            "device_database",
            "device_sharedpref",
        ).forEach { domain ->
            assertTrue(
                "Backup policy must exclude the $domain domain",
                xml.contains("<exclude domain=\"$domain\" path=\".\" />"),
            )
        }
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
