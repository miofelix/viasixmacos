package dev.viasix.app.state

enum class LogOrder {
    OLDEST_FIRST,
    NEWEST_FIRST,
}

/** Presentation state for a streaming log list whose latest item is at the bottom. */
data class LogFollowState(
    val order: LogOrder = LogOrder.OLDEST_FIRST,
    val followsLatest: Boolean = true,
) {
    val canFollowLatest: Boolean
        get() = order == LogOrder.OLDEST_FIRST

    fun toggleOrder(): LogFollowState =
        when (order) {
            LogOrder.OLDEST_FIRST ->
                copy(
                    order = LogOrder.NEWEST_FIRST,
                    followsLatest = false,
                )
            LogOrder.NEWEST_FIRST ->
                copy(
                    order = LogOrder.OLDEST_FIRST,
                    followsLatest = true,
                )
        }

    fun toggleFollowing(): LogFollowState =
        if (canFollowLatest) {
            copy(followsLatest = !followsLatest)
        } else {
            this
        }

    fun resetAfterClear(): LogFollowState =
        copy(followsLatest = canFollowLatest)
}
