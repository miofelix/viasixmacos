package dev.viasix.core.speedtest

/**
 * CFST CLI parameters aligned with macOS [SpeedTestParameters] (authoritative).
 * Windows may lag; do not treat Windows defaults as the Android target.
 */
data class SpeedTestParameters(
    val ipFile: String = "",
    val ipRange: String = "",
    val threads: Int = DEFAULT_THREADS,
    val pingCount: Int = DEFAULT_PING_COUNT,
    val downloadCount: Int = DEFAULT_DOWNLOAD_COUNT,
    val downloadTime: Int = DEFAULT_DOWNLOAD_TIME,
    val latencyUpperBound: Int = DEFAULT_LATENCY_UPPER,
    val latencyLowerBound: Int = DEFAULT_LATENCY_LOWER,
    val lossRateUpperBound: Double = DEFAULT_LOSS_RATE_UPPER,
    val speedLowerBound: Double = DEFAULT_SPEED_LOWER,
    val colo: String = "",
    val port: Int = DEFAULT_PORT,
    val url: String = "",
    val httping: Boolean = true,
    val httpingCode: Int = 0,
    val disableDownload: Boolean = false,
    val allIP: Boolean = false,
    val debug: Boolean = false,
) {
    fun hasIpSource(): Boolean =
        ipRange.trim().isNotEmpty() || ipFile.trim().isNotEmpty()

    /**
     * macOS [SpeedTestParameters.validated] — Chinese messages for UI.
     * @param checkIpFileExists when true, verify [ipFile] is a non-empty regular file
     *   if range is empty (used after resolveForRun with real paths).
     */
    fun validated(checkIpFileExists: Boolean = false): SpeedTestParameters {
        if (!hasIpSource()) {
            throw SpeedTestValidationError.MissingIPSource
        }
        if (ipRange.trim().isEmpty()) {
            if (checkIpFileExists) {
                validateIpFile(ipFile.trim())
            }
        } else {
            validateIpRange(ipRange)
        }
        if (threads !in 1..1_000) {
            throw SpeedTestValidationError.OutOfRange("线程数应在 1 到 1000 之间")
        }
        if (pingCount !in 1..100) {
            throw SpeedTestValidationError.OutOfRange("Ping 次数应在 1 到 100 之间")
        }
        if (downloadCount !in 0..100) {
            throw SpeedTestValidationError.OutOfRange("下载测速数量应在 0 到 100 之间")
        }
        if (downloadTime !in 1..3_600) {
            throw SpeedTestValidationError.OutOfRange("单 IP 下载时长应在 1 到 3600 秒之间")
        }
        if (latencyLowerBound !in 0..999_999 ||
            latencyUpperBound !in 1..999_999 ||
            latencyLowerBound > latencyUpperBound
        ) {
            throw SpeedTestValidationError.OutOfRange("延迟上下限不合法")
        }
        if (lossRateUpperBound !in 0.0..1.0) {
            throw SpeedTestValidationError.OutOfRange("丢包率应在 0 到 1 之间")
        }
        if (!speedLowerBound.isFinite() || speedLowerBound < 0) {
            throw SpeedTestValidationError.OutOfRange("速度下限不合法")
        }
        if (port !in 1..65_535) {
            throw SpeedTestValidationError.OutOfRange("端口应在 1 到 65535 之间")
        }
        if (httpingCode != 0 && httpingCode !in 100..599) {
            throw SpeedTestValidationError.OutOfRange("HTTP 状态码应为 0 或 100 到 599")
        }
        if (url.trim().isNotEmpty()) {
            validateUrl(url.trim())
        }
        return this
    }

    /** Null if [validated] succeeds; otherwise the macOS-style message. */
    fun validationMessage(checkIpFileExists: Boolean = false): String? =
        try {
            validated(checkIpFileExists)
            null
        } catch (error: SpeedTestValidationError) {
            error.message
        }

    /**
     * Build CFST argv after the executable path (no binary name).
     * Runs [validated] (without requiring the IP file to exist — caller may
     * pre-check after resolve).
     */
    fun commandLineArguments(resultPath: String): List<String> {
        validated(checkIpFileExists = false)

        val args =
            mutableListOf(
                "-o",
                resultPath,
                "-tp",
                port.toString(),
                "-n",
                threads.toString(),
                "-t",
                pingCount.toString(),
                "-dn",
                downloadCount.toString(),
                "-dt",
                downloadTime.toString(),
                "-tl",
                latencyUpperBound.toString(),
                "-tll",
                latencyLowerBound.toString(),
                "-tlr",
                String.format(java.util.Locale.US, "%.2f", lossRateUpperBound),
                "-sl",
                String.format(java.util.Locale.US, "%.2f", speedLowerBound),
                // Suppress interactive table so CSV is the sole result channel.
                "-p",
                "0",
            )

        val range = ipRange.trim()
        if (range.isNotEmpty()) {
            val normalized =
                range
                    .split(",")
                    .joinToString(",") { it.trim() }
                    .trim(',')
            args += listOf("-ip", normalized)
        } else {
            args += listOf("-f", ipFile.trim())
        }

        if (httping) {
            args += "-httping"
            if (httpingCode > 0) {
                args += listOf("-httping-code", httpingCode.toString())
            }
        }
        val coloTrim = colo.trim()
        if (coloTrim.isNotEmpty()) {
            args += listOf("-cfcolo", coloTrim)
        }
        val urlTrim = url.trim()
        if (urlTrim.isNotEmpty()) {
            args += listOf("-url", urlTrim)
        }
        if (disableDownload) args += "-dd"
        if (allIP) args += "-allip"
        if (debug) args += "-debug"
        return args
    }

    companion object {
        const val DEFAULT_THREADS = 200
        const val DEFAULT_PING_COUNT = 4
        const val DEFAULT_DOWNLOAD_COUNT = 10
        const val DEFAULT_DOWNLOAD_TIME = 10
        const val DEFAULT_LATENCY_UPPER = 9_999
        const val DEFAULT_LATENCY_LOWER = 0
        const val DEFAULT_LOSS_RATE_UPPER = 1.0
        const val DEFAULT_SPEED_LOWER = 0.0
        const val DEFAULT_PORT = 443

        /** Default Cloudflare IPv6 main prefix used when no custom range is set. */
        const val DEFAULT_IPV6_RANGE = "2606:4700::/32"

        fun defaultsForRange(ipRange: String = DEFAULT_IPV6_RANGE): SpeedTestParameters =
            SpeedTestParameters(ipRange = ipRange)

        fun defaultsForFile(ipFile: String): SpeedTestParameters =
            SpeedTestParameters(ipFile = ipFile)
    }

    /**
     * macOS [AppModel.currentConfigurationTestParameters]: single-node check keeps
     * transport/performance settings but drops result filters so a reachable node
     * is not discarded as "no results". Forces [ipRange] to the selected address.
     */
    fun forCurrentNodeConfigurationTest(selectedIp: String): SpeedTestParameters {
        val ip = selectedIp.trim()
        require(ip.isNotEmpty()) { "selected IP required" }
        return copy(
            ipFile = "",
            ipRange = ip,
            allIP = false,
            latencyUpperBound = 999_999,
            latencyLowerBound = 0,
            lossRateUpperBound = 1.0,
            speedLowerBound = 0.0,
            colo = "",
            debug = true,
        )
    }

    private fun validateIpFile(path: String) {
        if (path.isEmpty()) {
            throw SpeedTestValidationError.MissingIPSource
        }
        val file = java.io.File(path)
        if (!file.exists()) {
            throw SpeedTestValidationError.IpFileNotFound(path)
        }
        if (!file.isFile || !file.canRead()) {
            throw SpeedTestValidationError.IpFileUnreadable(path)
        }
        if (file.length() == 0L) {
            throw SpeedTestValidationError.IpFileEmpty(path)
        }
    }

    private fun validateIpRange(value: String) {
        val entries = value.split(",")
        for (rawEntry in entries) {
            val entry = rawEntry.trim()
            if (entry.isEmpty()) {
                throw SpeedTestValidationError.InvalidIPRange(value)
            }
            val pieces = entry.split("/")
            if (pieces.size > 2 || pieces.any { it.trim().isEmpty() }) {
                throw SpeedTestValidationError.InvalidIPRange(entry)
            }
            val address = pieces[0].trim()
            val maxPrefix =
                when {
                    isStrictIpv4(address) -> 32
                    looksLikeIpv6(address) -> 128
                    else -> throw SpeedTestValidationError.InvalidIPRange(entry)
                }
            if (pieces.size == 2) {
                val prefix = pieces[1].trim().toIntOrNull()
                if (prefix == null || prefix !in 0..maxPrefix) {
                    throw SpeedTestValidationError.InvalidIPRange(entry)
                }
            }
        }
    }

    private fun validateUrl(value: String) {
        val uri =
            try {
                java.net.URI(value)
            } catch (_: Exception) {
                throw SpeedTestValidationError.InvalidURL
            }
        val scheme = uri.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") {
            throw SpeedTestValidationError.InvalidURL
        }
        if (uri.host.isNullOrBlank()) {
            throw SpeedTestValidationError.InvalidURL
        }
    }

    private fun isStrictIpv4(value: String): Boolean {
        val octets = value.split(".")
        if (octets.size != 4) return false
        return octets.all { octet ->
            if (octet.isEmpty() || !octet.all { it.isDigit() }) return@all false
            if (octet.length > 1 && octet.startsWith('0')) return@all false
            val n = octet.toIntOrNull() ?: return@all false
            n in 0..255
        }
    }

    private fun looksLikeIpv6(value: String): Boolean {
        if (value.contains('%')) return false
        return try {
            val addr = java.net.InetAddress.getByName(value)
            addr is java.net.Inet6Address
        } catch (_: Exception) {
            // Allow compressed forms that the local resolver rejects but CFST accepts.
            value.contains(':') && value.all {
                it.isDigit() || it in 'a'..'f' || it in 'A'..'F' || it == ':'
            }
        }
    }
}

/**
 * macOS [SpeedTestParameterError] messages (Chinese).
 */
sealed class SpeedTestValidationError(override val message: String) : Exception(message) {
    data object MissingIPSource : SpeedTestValidationError("请选择 IP 文件或填写 IP 段")

    data class IpFileNotFound(val path: String) :
        SpeedTestValidationError("找不到 IP 地址文件：$path")

    data class IpFileUnreadable(val path: String) :
        SpeedTestValidationError("无法读取 IP 地址文件：$path")

    data class IpFileEmpty(val path: String) :
        SpeedTestValidationError("IP 地址文件为空：$path")

    data class InvalidIPRange(val value: String) :
        SpeedTestValidationError("IP 段格式无效：$value")

    data object InvalidURL :
        SpeedTestValidationError("测速 URL 必须是有效的 HTTP 或 HTTPS 地址")

    data class OutOfRange(val detail: String) : SpeedTestValidationError(detail)
}

/** Convenience CIDR chips derived from macOS bundled `ipv6.txt` core prefixes. */
data class Ipv6IpPreset(
    val id: String,
    val title: String,
    val description: String,
    val ipRange: String,
)

object Ipv6IpPresets {
    val all: List<Ipv6IpPreset> =
        listOf(
            Ipv6IpPreset(
                id = "cf-main",
                title = "Cloudflare 主段",
                description = "2606:4700::/32",
                ipRange = "2606:4700::/32",
            ),
            Ipv6IpPreset(
                id = "cf-bundle",
                title = "Cloudflare 常用 IPv6 段",
                description = "macOS 默认 ipv6 列表核心段",
                ipRange =
                    listOf(
                        "2400:cb00::/32",
                        "2606:4700::/32",
                        "2803:f800::/32",
                        "2405:b500::/32",
                        "2405:8100::/32",
                        "2a06:98c0::/29",
                        "2c0f:f248::/32",
                    ).joinToString(","),
            ),
            Ipv6IpPreset(
                id = "cf-apac",
                title = "亚太相关段",
                description = "2400:cb00 + 2405 段",
                ipRange = "2400:cb00::/32,2405:b500::/32,2405:8100::/32",
            ),
        )
}
