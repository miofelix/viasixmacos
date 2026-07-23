package dev.viasix.app.mihomo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TrafficSamplerTest {
    @Test
    fun parseConnectionsTotalsBody_readsTotalsCountAndMemory() {
        val totals =
            ControllerClient.parseConnectionsTotalsBody(
                """
                {
                  "uploadTotal": 1024,
                  "downloadTotal": 4096,
                  "connections": [{}, {}],
                  "memory": 54374400
                }
                """.trimIndent(),
            )

        assertTrue(totals.live)
        assertEquals(1024L, totals.uploadTotal)
        assertEquals(4096L, totals.downloadTotal)
        assertEquals(2, totals.connectionCount)
        assertEquals(54_374_400L, totals.memoryInUse)
    }

    @Test
    fun parseConnectionsTotalsBody_missingMemoryAndConnectionsDefaults() {
        val totals =
            ControllerClient.parseConnectionsTotalsBody(
                """{"uploadTotal":1,"downloadTotal":2}""",
            )

        assertTrue(totals.live)
        assertEquals(1L, totals.uploadTotal)
        assertEquals(2L, totals.downloadTotal)
        assertEquals(0, totals.connectionCount)
        assertEquals(0L, totals.memoryInUse)
    }

    @Test
    fun idleSnapshot_isNotLive() {
        assertFalse(TrafficSnapshot.Idle.live)
        assertEquals(0, TrafficSnapshot.Idle.connectionCount)
    }

    @Test
    fun samplerSourceDoesNotCallStreamingMemoryEndpoint() {
        // Guard against reintroducing GET /memory (chunked stream that never EOF's —
        // readBody() hangs until the UI withTimeout fires and traffic stays Idle).
        val source =
            resolve(
                "src/main/java/dev/viasix/app/mihomo/ControllerClient.kt",
                "app/src/main/java/dev/viasix/app/mihomo/ControllerClient.kt",
            ).readText()
        assertFalse(source.contains("http://\$host:\$port/memory"))
        assertFalse(source.contains("fun memoryInUse("))
        assertTrue(source.contains("parseConnectionsTotalsBody"))
        assertTrue(source.contains("totals.memoryInUse"))
    }

    private fun resolve(vararg paths: String): java.io.File =
        paths.map { java.io.File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${java.io.File(".").absolutePath}: ${paths.toList()}")
}
