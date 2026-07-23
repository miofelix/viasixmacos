package dev.viasix.core.speedtest

/**
 * Parses XIU2/CloudflareSpeedTest stdout for live progress.
 * Aligned with macOS [CfstOutputParser]: CFST redraws bars with `\r` and embeds
 * snippets like `400 / 16640 [` — often without a trailing newline.
 */
object CfstOutputParser {
    data class Progress(
        val current: Int,
        val total: Int,
    ) {
        val fraction: Float
            get() =
                if (total <= 0) {
                    0f
                } else {
                    (current.toFloat() / total.toFloat()).coerceIn(0f, 1f)
                }

        val percent: Int
            get() = (fraction * 100f).toInt().coerceIn(0, 100)

        /** Compact status for the Nodes card. */
        fun statusMessage(phaseHint: String? = null): String {
            val base = "$current / $total（$percent%）"
            return if (phaseHint.isNullOrBlank()) {
                "测速进度 $base"
            } else {
                "$phaseHint $base"
            }
        }
    }

    private val progressRegex = Regex("""(\d+)\s*/\s*(\d+)\s*\[""")
    private val ansiRegex = Regex("""\u001B\[[0-9;]*[a-zA-Z]""")
    private val downloadPhaseRegex = Regex("""开始下载测速""")
    private val latencyPhaseRegex = Regex("""开始延迟测速""")

    fun parseProgress(text: String): Progress? {
        val match = progressRegex.findAll(text).lastOrNull() ?: return null
        val current = match.groupValues[1].toIntOrNull() ?: return null
        val total = match.groupValues[2].toIntOrNull() ?: return null
        if (total <= 0 || current < 0) return null
        return Progress(current = current.coerceAtMost(total), total = total)
    }

    fun stripAnsi(text: String): String = ansiRegex.replace(text, "")

    fun detectPhaseHint(text: String): String? =
        when {
            downloadPhaseRegex.containsMatchIn(text) -> "下载测速"
            latencyPhaseRegex.containsMatchIn(text) -> "延迟测速"
            else -> null
        }

    /**
     * Incremental consumer for CFST's mixed `\r`/`\n` progress stream.
     * Emits a [Progress] only when current/total changes.
     */
    class Stream {
        private val carry = StringBuilder()
        private var lastProgress: Progress? = null
        private var phaseHint: String? = null

        fun lastPhaseHint(): String? = phaseHint

        fun consume(chunk: String): Progress? {
            if (chunk.isEmpty()) return null
            carry.append(stripAnsi(chunk))
            detectPhaseHint(chunk)?.let { phaseHint = it }
            if (carry.length > 16_384) {
                carry.delete(0, carry.length - 4_096)
            }
            val progress = parseProgress(carry.toString()) ?: return null
            if (progress == lastProgress) return null
            lastProgress = progress
            return progress
        }

        fun finish(): Progress? {
            if (carry.isEmpty()) return null
            val progress = parseProgress(carry.toString())
            carry.setLength(0)
            if (progress == null || progress == lastProgress) return null
            lastProgress = progress
            return progress
        }
    }
}
