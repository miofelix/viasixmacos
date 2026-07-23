package dev.viasix.core.speedtest

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class IPSourceModeTest {
    @Test
    fun parseToleratesMacosAndLegacySpellings() {
        assertEquals(IPSourceMode.IPV6, IPSourceMode.parse("ipv6"))
        assertEquals(IPSourceMode.IPV6, IPSourceMode.parse("builtinipv6"))
        assertEquals(IPSourceMode.RANGE, IPSourceMode.parse("cidr"))
        assertEquals(IPSourceMode.FILE, IPSourceMode.parse("custom-file"))
        assertEquals(IPSourceMode.IPV6, IPSourceMode.parse("true"))
        assertEquals(IPSourceMode.RANGE, IPSourceMode.parse("false"))
        assertEquals(IPSourceMode.IPV6, IPSourceMode.parse(null))
    }

    @Test
    fun nodesPickerExcludesIpv4LikeMacos() {
        assertEquals(
            listOf(IPSourceMode.IPV6, IPSourceMode.RANGE, IPSourceMode.FILE),
            IPSourceMode.nodesPickerModes,
        )
    }

    @Test
    fun resolveIpv6UsesBundledPathAndClearsRange() {
        val base =
            SpeedTestParameters(
                ipRange = "2606:4700::/32",
                threads = 100,
                httping = true,
            )
        val resolved =
            base.resolveForRun(
                mode = IPSourceMode.IPV6,
                bundledIpv6ListPath = "/data/files/cfst/ipv6.txt",
                checkIpFileExists = false,
            )
        assertEquals("/data/files/cfst/ipv6.txt", resolved.ipFile)
        assertEquals("", resolved.ipRange)
        assertEquals(100, resolved.threads)
        val args = resolved.commandLineArguments("/tmp/r.csv")
        assertEquals("/data/files/cfst/ipv6.txt", args[args.indexOf("-f") + 1])
        assertFalse(args.contains("-ip"))
    }

    @Test
    fun resolveRangeRequiresNonEmptyAndClearsFile() {
        val base = SpeedTestParameters(ipFile = "/x", ipRange = "2400:cb00::/32")
        val resolved =
            base.resolveForRun(
                mode = IPSourceMode.RANGE,
                bundledIpv6ListPath = "/bundled",
            )
        assertEquals("", resolved.ipFile)
        assertEquals("2400:cb00::/32", resolved.ipRange)
        assertThrows(SpeedTestValidationError.MissingIPSource::class.java) {
            SpeedTestParameters(ipRange = "  ").resolveForRun(
                IPSourceMode.RANGE,
                "/bundled",
            )
        }
    }

    @Test
    fun resolveFileUsesCustomPath() {
        val base = SpeedTestParameters(ipRange = "ignore")
        val resolved =
            base.resolveForRun(
                mode = IPSourceMode.FILE,
                bundledIpv6ListPath = "/bundled",
                customIpFilePath = "/sdcard/list.txt",
                checkIpFileExists = false,
            )
        assertEquals("/sdcard/list.txt", resolved.ipFile)
        assertEquals("", resolved.ipRange)
        assertTrue(resolved.commandLineArguments("o.csv").contains("-f"))
    }

    @Test
    fun parameterSummaryMentionsMode() {
        val s =
            SpeedTestParameters(threads = 200, port = 443, httping = false)
                .parameterSummary(IPSourceMode.IPV6)
        assertTrue(s.contains("内置 IPv6"))
        assertTrue(s.contains("TCPing"))
        assertTrue(s.contains("200"))
    }
}
