package dev.viasix.app.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class RuntimeEventSequenceSurfaceTest {
    @Test
    fun servicePersistsMonotonicIdsBeforePublishingEventArray() {
        val service =
            resolve(
                "src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
                "app/src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
            ).readText()

        assertTrue(service.contains("RuntimeEventSequence.next("))
        assertTrue(service.contains("prefs.getLong(KEY_EVENT_SEQUENCE, 0L)"))
        assertTrue(service.contains("array.optJSONObject(i)?.optLong(\"id\", 0L)"))
        assertTrue(service.contains(".putLong(KEY_EVENT_SEQUENCE, eventId)"))
        assertFalse(service.contains(".put(\"id\", System.currentTimeMillis())"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
