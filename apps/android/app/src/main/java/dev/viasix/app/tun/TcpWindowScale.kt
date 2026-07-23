package dev.viasix.app.tun

internal object TcpWindowScale {
    const val MAX_SHIFT = 14

    fun normalize(receivedShift: Int): Int {
        require(receivedShift >= 0) { "receivedShift must not be negative" }
        return receivedShift.coerceAtMost(MAX_SHIFT)
    }

    fun expand(
        advertisedWindow: Int,
        shift: Int,
    ): Int {
        require(advertisedWindow in 0..65_535) { "advertisedWindow must be 0..65535" }
        require(shift in 0..MAX_SHIFT) { "shift must be 0..$MAX_SHIFT" }
        return (advertisedWindow.toLong() shl shift).toInt()
    }
}
