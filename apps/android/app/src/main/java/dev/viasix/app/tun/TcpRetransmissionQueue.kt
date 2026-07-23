package dev.viasix.app.tun

class TcpRetransmissionQueue(
    private val baseRtoMs: Long = 1_000L,
    private val maxRtoMs: Long = 8_000L,
    private val maxRetransmissions: Int = 5,
    private val maxRetainedBytes: Int = DEFAULT_MAX_RETAINED_BYTES,
) {
    sealed class PollResult {
        data class Retransmit(
            val sequence: Long,
            val flags: Int,
            val payload: ByteArray,
            val attempt: Int,
        ) : PollResult()

        object Exhausted : PollResult()
    }

    private data class Segment(
        val id: Long,
        var sequence: Long,
        val flags: Int,
        var payload: ByteArray,
        var sequenceLength: Int,
        var queuedAtMs: Long? = null,
        var retransmissions: Int = 0,
    )

    private val monitor = Object()
    private val segments = ArrayDeque<Segment>()
    private var retainedBytes = 0
    private var nextId = 1L
    private var cancelled = false
    private var duplicateAcknowledgement: Long? = null
    private var duplicateAcknowledgementCount = 0
    private var fastRetransmittedSequence: Long? = null

    init {
        require(baseRtoMs > 0L) { "baseRtoMs must be positive" }
        require(maxRtoMs >= baseRtoMs) { "maxRtoMs must cover baseRtoMs" }
        require(maxRetransmissions > 0) { "maxRetransmissions must be positive" }
        require(maxRetainedBytes > 0) { "maxRetainedBytes must be positive" }
    }

    fun reserve(
        sequence: Long,
        flags: Int,
        payload: ByteArray,
    ): Long? =
        synchronized(monitor) {
            val sequenceLength =
                payload.size +
                    (if (flags and Packet.SYN != 0) 1 else 0) +
                    (if (flags and Packet.FIN != 0) 1 else 0)
            if (cancelled || sequenceLength <= 0) return@synchronized null
            if (retainedBytes + sequenceLength > maxRetainedBytes) return@synchronized null
            val previous = segments.lastOrNull()
            if (
                previous != null &&
                    sequence !=
                    TcpSequence.advance(previous.sequence, payloadLength = previous.sequenceLength)
            ) {
                return@synchronized null
            }
            val id = nextId++
            segments.addLast(
                Segment(
                    id = id,
                    sequence = sequence,
                    flags = flags,
                    payload = payload.copyOf(),
                    sequenceLength = sequenceLength,
                ),
            )
            retainedBytes += sequenceLength
            id
        }

    fun markQueued(
        reservationId: Long,
        nowMs: Long,
    ): Boolean =
        synchronized(monitor) {
            val segment = segments.firstOrNull { it.id == reservationId } ?: return@synchronized false
            if (segment.queuedAtMs == null) segment.queuedAtMs = nowMs
            true
        }

    fun discard(reservationId: Long): Boolean =
        synchronized(monitor) {
            val segment = segments.lastOrNull() ?: return@synchronized false
            if (segment.id != reservationId || segment.queuedAtMs != null) return@synchronized false
            segments.removeLast()
            retainedBytes -= segment.sequenceLength
            if (segments.isEmpty()) resetDuplicateAcknowledgements()
            monitor.notifyAll()
            true
        }

    fun acknowledge(
        acknowledgement: Long,
        nowMs: Long,
    ): Boolean =
        synchronized(monitor) {
            if (cancelled) return@synchronized false
            var advanced = false
            while (true) {
                val segment = segments.firstOrNull() ?: break
                val end =
                    TcpSequence.advance(
                        segment.sequence,
                        payloadLength = segment.sequenceLength,
                    )
                if (acknowledgement == segment.sequence) break
                if (acknowledgement == end || TcpSequence.isAfter(acknowledgement, end)) {
                    segments.removeFirst()
                    retainedBytes -= segment.sequenceLength
                    advanced = true
                    continue
                }
                if (TcpSequence.isAfter(acknowledgement, segment.sequence)) {
                    val consumed =
                        TcpSequence.forwardDistance(segment.sequence, acknowledgement).toInt()
                    if (consumed in 1 until segment.sequenceLength) {
                        segment.sequence = acknowledgement
                        segment.sequenceLength -= consumed
                        segment.payload =
                            segment.payload.copyOfRange(
                                minOf(consumed, segment.payload.size),
                                segment.payload.size,
                            )
                        retainedBytes -= consumed
                        segment.retransmissions = 0
                        if (segment.queuedAtMs != null) segment.queuedAtMs = nowMs
                        advanced = true
                    }
                }
                break
            }
            if (advanced) {
                resetDuplicateAcknowledgements()
                segments.firstOrNull()?.let { first ->
                    first.retransmissions = 0
                    if (first.queuedAtMs != null) first.queuedAtMs = nowMs
                }
                monitor.notifyAll()
            }
            advanced
        }

    fun noteDuplicateAcknowledgement(
        acknowledgement: Long,
        nowMs: Long,
    ): PollResult.Retransmit? =
        synchronized(monitor) {
            if (cancelled) return@synchronized null
            val segment = segments.firstOrNull() ?: return@synchronized null
            if (segment.queuedAtMs == null || acknowledgement != segment.sequence) {
                resetDuplicateAcknowledgements()
                return@synchronized null
            }
            if (duplicateAcknowledgement == acknowledgement) {
                duplicateAcknowledgementCount += 1
            } else {
                duplicateAcknowledgement = acknowledgement
                duplicateAcknowledgementCount = 1
                fastRetransmittedSequence = null
            }
            if (
                duplicateAcknowledgementCount < FAST_RETRANSMIT_DUPLICATE_ACKS ||
                    fastRetransmittedSequence == segment.sequence ||
                    segment.retransmissions >= maxRetransmissions
            ) {
                return@synchronized null
            }
            segment.retransmissions += 1
            segment.queuedAtMs = nowMs
            fastRetransmittedSequence = segment.sequence
            PollResult.Retransmit(
                sequence = segment.sequence,
                flags = segment.flags,
                payload = segment.payload.copyOf(),
                attempt = segment.retransmissions,
            )
        }

    fun pollDue(nowMs: Long): PollResult? =
        synchronized(monitor) {
            if (cancelled) return@synchronized null
            val segment = segments.firstOrNull() ?: return@synchronized null
            val queuedAtMs = segment.queuedAtMs ?: return@synchronized null
            if (nowMs - queuedAtMs < retransmissionTimeout(segment.retransmissions)) {
                return@synchronized null
            }
            if (segment.retransmissions >= maxRetransmissions) {
                return@synchronized PollResult.Exhausted
            }
            segment.retransmissions += 1
            segment.queuedAtMs = nowMs
            PollResult.Retransmit(
                sequence = segment.sequence,
                flags = segment.flags,
                payload = segment.payload.copyOf(),
                attempt = segment.retransmissions,
            )
        }

    fun awaitEmpty(timeoutMs: Long): Boolean =
        synchronized(monitor) {
            val timeoutNanos = timeoutMs.coerceAtLeast(0L) * 1_000_000L
            val deadline = System.nanoTime() + timeoutNanos
            while (!cancelled && segments.isNotEmpty()) {
                val remainingNanos = deadline - System.nanoTime()
                if (remainingNanos <= 0L) return@synchronized false
                val waitMs = remainingNanos / 1_000_000L
                val waitNanos = (remainingNanos % 1_000_000L).toInt()
                try {
                    monitor.wait(waitMs, waitNanos)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return@synchronized false
                }
            }
            !cancelled && segments.isEmpty()
        }

    fun cancel() {
        synchronized(monitor) {
            cancelled = true
            segments.clear()
            retainedBytes = 0
            resetDuplicateAcknowledgements()
            monitor.notifyAll()
        }
    }

    private fun resetDuplicateAcknowledgements() {
        duplicateAcknowledgement = null
        duplicateAcknowledgementCount = 0
        fastRetransmittedSequence = null
    }

    private fun retransmissionTimeout(retransmissions: Int): Long {
        var timeout = baseRtoMs
        repeat(retransmissions) {
            if (timeout >= maxRtoMs) return maxRtoMs
            timeout = minOf(maxRtoMs, timeout * 2L)
        }
        return timeout
    }

    companion object {
        const val DEFAULT_MAX_RETAINED_BYTES = 131_070

        private const val FAST_RETRANSMIT_DUPLICATE_ACKS = 3
    }
}
