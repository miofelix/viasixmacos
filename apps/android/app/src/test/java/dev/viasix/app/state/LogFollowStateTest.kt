package dev.viasix.app.state

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LogFollowStateTest {
    @Test
    fun defaultsToChronologicalStreamingOrder() {
        val state = LogFollowState()

        assertEquals(LogOrder.OLDEST_FIRST, state.order)
        assertTrue(state.canFollowLatest)
        assertTrue(state.followsLatest)
    }

    @Test
    fun newestFirstDisablesFollowAndReturningResumesIt() {
        val newestFirst = LogFollowState().toggleOrder()

        assertEquals(LogOrder.NEWEST_FIRST, newestFirst.order)
        assertFalse(newestFirst.canFollowLatest)
        assertFalse(newestFirst.followsLatest)
        assertEquals(newestFirst, newestFirst.toggleFollowing())

        val chronological = newestFirst.toggleOrder()
        assertEquals(LogOrder.OLDEST_FIRST, chronological.order)
        assertTrue(chronological.followsLatest)
    }

    @Test
    fun followCanPauseResumeAndResetAfterClear() {
        val paused = LogFollowState().toggleFollowing()
        assertFalse(paused.followsLatest)

        assertTrue(paused.toggleFollowing().followsLatest)
        assertTrue(paused.resetAfterClear().followsLatest)
    }
}
