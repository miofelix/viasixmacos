package dev.viasix.app.session

/** Produces event IDs that stay strictly increasing across equal or rolled-back wall clocks. */
internal object RuntimeEventSequence {
    fun next(
        previousId: Long,
        wallClockMillis: Long,
    ): Long {
        if (previousId == Long.MAX_VALUE) return Long.MAX_VALUE
        return maxOf(previousId + 1L, wallClockMillis.coerceAtLeast(1L))
    }
}
