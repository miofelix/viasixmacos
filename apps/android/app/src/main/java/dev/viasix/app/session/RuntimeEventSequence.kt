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

/** Finds the newest persisted VPN event that a UI clear action must suppress on recreation. */
internal object RuntimeEventCursor {
    fun latestId(eventsJson: String): Long {
        var latest = 0L
        var index = 0
        while (index < eventsJson.length) {
            if (eventsJson[index] != '"') {
                index += 1
                continue
            }

            val valueStart = index + 1
            var cursor = valueStart
            var escaped = false
            var hasEscape = false
            while (cursor < eventsJson.length) {
                val char = eventsJson[cursor]
                if (escaped) {
                    escaped = false
                } else if (char == '\\') {
                    escaped = true
                    hasEscape = true
                } else if (char == '"') {
                    break
                }
                cursor += 1
            }
            if (cursor >= eventsJson.length) return latest

            val isId =
                !hasEscape &&
                    cursor - valueStart == 2 &&
                    eventsJson[valueStart] == 'i' &&
                    eventsJson[valueStart + 1] == 'd'
            index = cursor + 1
            if (!isId) continue

            while (index < eventsJson.length && eventsJson[index].isWhitespace()) index += 1
            if (index >= eventsJson.length || eventsJson[index] != ':') continue
            index += 1
            while (index < eventsJson.length && eventsJson[index].isWhitespace()) index += 1

            val numberStart = index
            if (index < eventsJson.length && eventsJson[index] == '-') index += 1
            while (index < eventsJson.length && eventsJson[index].isDigit()) index += 1
            if (index == numberStart || (index == numberStart + 1 && eventsJson[numberStart] == '-')) {
                continue
            }
            val eventId = eventsJson.substring(numberStart, index).toLongOrNull() ?: continue
            latest = maxOf(latest, eventId)
        }
        return latest
    }
}
