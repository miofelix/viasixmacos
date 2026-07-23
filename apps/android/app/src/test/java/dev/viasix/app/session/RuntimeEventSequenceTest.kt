package dev.viasix.app.session

import org.junit.Assert.assertEquals
import org.junit.Test

class RuntimeEventSequenceTest {
    @Test
    fun advancesWhenMultipleEventsShareOneMillisecond() {
        assertEquals(
            1_001L,
            RuntimeEventSequence.next(previousId = 1_000L, wallClockMillis = 1_000L),
        )
    }

    @Test
    fun advancesAcrossWallClockRollback() {
        assertEquals(1_001L, RuntimeEventSequence.next(previousId = 1_000L, wallClockMillis = 900L))
    }

    @Test
    fun adoptsNewerWallClockWhenItIsAlreadyAhead() {
        assertEquals(2_000L, RuntimeEventSequence.next(previousId = 1_000L, wallClockMillis = 2_000L))
    }

    @Test
    fun clearCursorFindsNewestEventRegardlessOfArrayOrder() {
        assertEquals(
            42L,
            RuntimeEventCursor.latestId(
                """[{"id":40},{"id":42},{"id":41}]""",
            ),
        )
    }

    @Test
    fun malformedOrNegativeEventsCannotMoveClearCursorBackward() {
        assertEquals(0L, RuntimeEventCursor.latestId("not-json"))
        assertEquals(0L, RuntimeEventCursor.latestId("""[{"id":-1},{}]"""))
        assertEquals(
            7L,
            RuntimeEventCursor.latestId(
                """[{"message":"escaped \"id\":999","id":7}]""",
            ),
        )
    }
}
