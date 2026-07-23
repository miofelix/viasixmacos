package dev.viasix.core.speedtest

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class SpeedTestParametersTest {
    @Test
    fun defaultRangeProducesExpectedCliFlags() {
        val params = SpeedTestParameters.defaultsForRange()
        val args = params.commandLineArguments("/data/result.csv")

        assertTrue(params.hasIpSource())
        assertEquals(SpeedTestParameters.DEFAULT_IPV6_RANGE, params.ipRange)
        assertEquals(200, params.threads)
        assertEquals(4, params.pingCount)
        assertEquals(10, params.downloadCount)
        assertEquals(10, params.downloadTime)
        assertEquals(443, params.port)
        assertTrue(params.httping)

        // Flag pairs used by macOS CfstRunner / SpeedTestParameters.commandLineArguments.
        assertEquals("/data/result.csv", args[args.indexOf("-o") + 1])
        assertEquals("443", args[args.indexOf("-tp") + 1])
        assertEquals("200", args[args.indexOf("-n") + 1])
        assertEquals("4", args[args.indexOf("-t") + 1])
        assertEquals("10", args[args.indexOf("-dn") + 1])
        assertEquals("10", args[args.indexOf("-dt") + 1])
        assertEquals("0", args[args.indexOf("-p") + 1])
        assertEquals(SpeedTestParameters.DEFAULT_IPV6_RANGE, args[args.indexOf("-ip") + 1])
        assertTrue(args.contains("-httping"))
        assertFalse(args.contains("-dd"))
        assertFalse(args.contains("-f"))
    }

    @Test
    fun ipFilePreferredWhenRangeEmpty() {
        val params = SpeedTestParameters.defaultsForFile("/files/ipv6.txt")
        val args = params.commandLineArguments("out.csv")
        assertEquals("/files/ipv6.txt", args[args.indexOf("-f") + 1])
        assertFalse(args.contains("-ip"))
    }

    @Test
    fun rangeWinsOverFileWhenBothSet() {
        val params =
            SpeedTestParameters(
                ipFile = "/files/ipv6.txt",
                ipRange = "2400:cb00::/32, 2606:4700::/32 ",
            )
        val args = params.commandLineArguments("out.csv")
        assertEquals("2400:cb00::/32,2606:4700::/32", args[args.indexOf("-ip") + 1])
        assertFalse(args.contains("-f"))
    }

    @Test
    fun disableDownloadAndOptionalFlags() {
        val params =
            SpeedTestParameters(
                ipRange = "2001:db8::/32",
                disableDownload = true,
                httping = false,
                allIP = true,
                debug = true,
                colo = "SJC",
                url = "https://speed.cloudflare.com/__down",
                httpingCode = 200,
            )
        val args = params.commandLineArguments("r.csv")
        assertTrue(args.contains("-dd"))
        assertTrue(args.contains("-allip"))
        assertTrue(args.contains("-debug"))
        assertEquals("SJC", args[args.indexOf("-cfcolo") + 1])
        assertEquals("https://speed.cloudflare.com/__down", args[args.indexOf("-url") + 1])
        assertFalse(args.contains("-httping"))
    }

    @Test
    fun httpingCodeOnlyWhenHttpingEnabled() {
        val params =
            SpeedTestParameters(
                ipRange = "2001:db8::/32",
                httping = true,
                httpingCode = 204,
            )
        val args = params.commandLineArguments("r.csv")
        assertTrue(args.contains("-httping"))
        assertEquals("204", args[args.indexOf("-httping-code") + 1])
    }

    @Test
    fun requiresIpSource() {
        assertThrows(SpeedTestValidationError.MissingIPSource::class.java) {
            SpeedTestParameters().commandLineArguments("r.csv")
        }
    }

    @Test
    fun rejectsOutOfRangeThreads() {
        assertThrows(SpeedTestValidationError.OutOfRange::class.java) {
            SpeedTestParameters(ipRange = "1::/64", threads = 0).commandLineArguments("r.csv")
        }
    }

    @Test
    fun presetsMatchMacosBundledIpv6Core() {
        assertTrue(Ipv6IpPresets.all.isNotEmpty())
        val main = Ipv6IpPresets.all.first { it.id == "cf-main" }
        assertEquals("2606:4700::/32", main.ipRange)
        val bundle = Ipv6IpPresets.all.first { it.id == "cf-bundle" }
        assertTrue(bundle.ipRange.contains("2606:4700::/32"))
        assertTrue(bundle.ipRange.contains("2400:cb00::/32"))
    }

    @Test
    fun configurationTestMatchesMacosFilterRelaxation() {
        val base =
            SpeedTestParameters(
                ipFile = "/tmp/ipv6.txt",
                ipRange = "2606:4700::/32",
                threads = 200,
                latencyUpperBound = 100,
                lossRateUpperBound = 0.1,
                speedLowerBound = 5.0,
                colo = "SJC",
                disableDownload = true,
            )
        val cfg = base.forCurrentNodeConfigurationTest("2001:db8::1")
        assertEquals("", cfg.ipFile)
        assertEquals("2001:db8::1", cfg.ipRange)
        assertEquals(200, cfg.threads)
        assertTrue(cfg.disableDownload)
        assertEquals(999_999, cfg.latencyUpperBound)
        assertEquals(0, cfg.latencyLowerBound)
        assertEquals(1.0, cfg.lossRateUpperBound)
        assertEquals(0.0, cfg.speedLowerBound)
        assertEquals("", cfg.colo)
        assertTrue(cfg.debug)
        assertFalse(cfg.allIP)
        val args = cfg.commandLineArguments("r.csv")
        assertEquals("2001:db8::1", args[args.indexOf("-ip") + 1])
        assertTrue(args.contains("-debug"))
    }
}
