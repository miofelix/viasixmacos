package dev.viasix.core.speedtest

/**
 * Address source for CFST, aligned with macOS [IPSourceMode].
 * Android Nodes mirrors macOS available modes (no IPv4 list in the picker).
 */
enum class IPSourceMode(val wire: String, val title: String) {
    IPV6("ipv6", "内置 IPv6"),
    RANGE("range", "自定义 CIDR"),
    FILE("file", "自定义文件"),
    ;

    companion object {
        /** Modes shown in the Nodes source picker (macOS filters out `.ipv4`). */
        val nodesPickerModes: List<IPSourceMode> = listOf(IPV6, RANGE, FILE)

        fun parse(raw: String?): IPSourceMode {
            val n =
                raw
                    ?.trim()
                    ?.lowercase()
                    .orEmpty()
            return when (n) {
                "ipv6", "v6", "ip6", "builtinipv6" -> IPV6
                "range", "cidr", "customrange", "custom-range", "custom_range" -> RANGE
                "file", "customfile", "custom-file", "custom_file", "path" -> FILE
                // Legacy Android prefs used a boolean "use bundled list".
                "true", "bundled", "1" -> IPV6
                "false", "0" -> RANGE
                else -> IPV6
            }
        }
    }
}

/**
 * Resolves [base] + [mode] into a runnable [SpeedTestParameters] for CFST,
 * matching macOS [AppModel.normalizeBundledSourcePath] + validated args.
 *
 * @param bundledIpv6ListPath absolute path to installed bundled `ipv6.txt`
 * @param customIpFilePath optional user-selected list path when [mode] is [IPSourceMode.FILE]
 */
fun SpeedTestParameters.resolveForRun(
    mode: IPSourceMode,
    bundledIpv6ListPath: String,
    customIpFilePath: String = "",
    validate: Boolean = true,
    checkIpFileExists: Boolean = true,
): SpeedTestParameters {
    val resolved =
        when (mode) {
            IPSourceMode.IPV6 ->
                copy(
                    ipFile = bundledIpv6ListPath,
                    ipRange = "",
                )
            IPSourceMode.RANGE -> {
                val range = ipRange.trim()
                if (range.isEmpty()) {
                    throw SpeedTestValidationError.MissingIPSource
                }
                copy(ipFile = "", ipRange = range)
            }
            IPSourceMode.FILE -> {
                val path =
                    customIpFilePath.trim().ifEmpty { ipFile.trim() }
                if (path.isEmpty()) {
                    throw SpeedTestValidationError.MissingIPSource
                }
                copy(ipFile = path, ipRange = "")
            }
        }
    return if (validate) {
        resolved.validated(checkIpFileExists = checkIpFileExists && mode != IPSourceMode.RANGE)
    } else {
        resolved
    }
}

/**
 * Preview validation for UI without requiring a real bundled file path yet.
 * RANGE validates fully; IPV6/FILE only check non-path fields unless paths provided.
 */
fun SpeedTestParameters.previewValidationMessage(
    mode: IPSourceMode,
    customIpFilePath: String = "",
): String? {
    return try {
        when (mode) {
            IPSourceMode.RANGE ->
                copy(ipFile = "").validated(checkIpFileExists = false)
            IPSourceMode.IPV6 ->
                // Source path filled at run time; still validate numeric/mode fields.
                copy(ipFile = "/preview/ipv6.txt", ipRange = "").validated(checkIpFileExists = false)
            IPSourceMode.FILE -> {
                val path = customIpFilePath.trim().ifEmpty { ipFile.trim() }
                if (path.isEmpty()) throw SpeedTestValidationError.MissingIPSource
                copy(ipFile = path, ipRange = "").validated(checkIpFileExists = false)
            }
        }
        null
    } catch (error: SpeedTestValidationError) {
        error.message
    }
}

fun SpeedTestParameters.parameterSummary(mode: IPSourceMode): String {
    val source =
        when (mode) {
            IPSourceMode.IPV6 -> "内置 IPv6 列表"
            IPSourceMode.RANGE ->
                if (ipRange.isBlank()) "自定义 CIDR" else ipRange
            IPSourceMode.FILE ->
                if (ipFile.isBlank()) "自定义文件" else ipFile.substringAfterLast('/')
        }
    val modeLabel = if (httping) "HTTPing" else "TCPing"
    return "$source · $modeLabel · 端口 $port · 线程 $threads"
}
