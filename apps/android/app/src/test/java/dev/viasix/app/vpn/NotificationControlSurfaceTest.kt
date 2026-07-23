package dev.viasix.app.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class NotificationControlSurfaceTest {
    @Test
    fun foregroundNotificationHasQuietDisconnectAction() {
        val source =
            resolve(
                "src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
                "app/src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
            ).readText()

        assertTrue(source.contains("PendingIntent.getService"))
        assertTrue(source.contains("setAction(ACTION_STOP)"))
        assertTrue(source.contains(".addAction(disconnectAction)"))
        assertTrue(source.contains(".setOnlyAlertOnce(true)"))
        assertTrue(source.contains("NotificationManager.IMPORTANCE_LOW"))
        assertFalse(source.contains("if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
