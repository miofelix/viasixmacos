package dev.viasix.app.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class VpnStartRequestCoalescingSurfaceTest {
    @Test
    fun startupWorkerAppliesLatestRequestInsteadOfDroppingIt() {
        val service =
            resolve(
                "src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
                "app/src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
            ).readText()

        assertTrue(service.contains("LatestRequestGate<StartRequest>()"))
        assertTrue(service.contains("if (!startRequests.submit(request))"))
        assertTrue(service.contains("已有启动任务进行中，已合并为最新请求"))
        assertTrue(service.contains("val request = startRequests.takeNext() ?: break"))
        assertTrue(service.contains("startRequests.cancelPending()"))
        assertFalse(service.contains("忽略重复请求"))
        assertFalse(service.contains("starting.compareAndSet(false, true)"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
