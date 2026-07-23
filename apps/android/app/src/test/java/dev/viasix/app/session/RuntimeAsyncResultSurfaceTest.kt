package dev.viasix.app.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class RuntimeAsyncResultSurfaceTest {
    @Test
    fun activityRejectsResultsFromEarlierRuntimeSessions() {
        val activity =
            resolve(
                "src/main/java/dev/viasix/app/MainActivity.kt",
                "app/src/main/java/dev/viasix/app/MainActivity.kt",
            ).readText()

        assertTrue(activity.contains("private var trafficSessionKey: RuntimeSessionKey? = null"))
        assertTrue(activity.contains("val sampleKey = runtimeStatus.sessionKey()"))
        assertTrue(activity.contains("val latestRuntime = runtimeStore.load()"))
        assertTrue(
            activity.contains("if (latestKey == sampleKey && trafficSampler === sampler)"),
        )
        assertFalse(activity.contains("private var wasRunning"))

        assertTrue(
            activity.contains("val detectionSessionKey = runtimeStore.load().sessionKey()"),
        )
        assertTrue(
            activity.contains("runtimeStore.load().sessionKey() == detectionSessionKey"),
        )

        assertTrue(activity.contains("val delaySessionKey = runtime.sessionKey()"))
        assertTrue(activity.contains("runtimeStore.load().sessionKey() != delaySessionKey"))
        assertTrue(activity.contains("it.profileSummary.primary?.name != name"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
