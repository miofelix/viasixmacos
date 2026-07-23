package dev.viasix.app.state

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class LogsExperienceSurfaceTest {
    @Test
    fun logsScreenFollowsLatestAndConfirmsDestructiveClear() {
        val source =
            resolve(
                "src/main/java/dev/viasix/app/ui/screens/LogsScreen.kt",
                "app/src/main/java/dev/viasix/app/ui/screens/LogsScreen.kt",
            ).readText()

        assertTrue(source.contains("var followState by remember { mutableStateOf(LogFollowState()) }"))
        assertTrue(source.contains("val listState = rememberLazyListState()"))
        assertTrue(source.contains("listState.scrollToItem(filtered.lastIndex)"))
        assertTrue(source.contains("followState = followState.toggleFollowing()"))
        assertTrue(source.contains("暂停跟随最新日志"))
        assertTrue(source.contains("恢复跟随最新日志"))
        assertTrue(source.contains("AlertDialog("))
        assertTrue(source.contains("清空日志？"))
        assertTrue(source.contains("followState = followState.resetAfterClear()"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
