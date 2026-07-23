package dev.viasix.core.speedtest

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.nio.file.Path

class SpeedTestValidationTest {
    @Test
    fun defaultsForRangeValidateClean() {
        val p = SpeedTestParameters.defaultsForRange()
        assertNull(p.validationMessage())
        p.validated()
    }

    @Test
    fun missingSourceFailsWithMacosMessage() {
        val err =
            assertThrows(SpeedTestValidationError.MissingIPSource::class.java) {
                SpeedTestParameters().validated()
            }
        assertEquals("请选择 IP 文件或填写 IP 段", err.message)
    }

    @Test
    fun threadBounds() {
        val err =
            assertThrows(SpeedTestValidationError.OutOfRange::class.java) {
                SpeedTestParameters(ipRange = "2001:db8::/32", threads = 0).validated()
            }
        assertTrue(err.message!!.contains("线程"))
    }

    @Test
    fun latencyBounds() {
        val err =
            assertThrows(SpeedTestValidationError.OutOfRange::class.java) {
                SpeedTestParameters(
                    ipRange = "2001:db8::/32",
                    latencyLowerBound = 50,
                    latencyUpperBound = 10,
                ).validated()
            }
        assertTrue(err.message!!.contains("延迟"))
    }

    @Test
    fun invalidUrl() {
        assertThrows(SpeedTestValidationError.InvalidURL::class.java) {
            SpeedTestParameters(
                ipRange = "2001:db8::/32",
                url = "ftp://example.com",
            ).validated()
        }
    }

    @Test
    fun invalidIpRange() {
        assertThrows(SpeedTestValidationError.InvalidIPRange::class.java) {
            SpeedTestParameters(ipRange = "not-an-ip").validated()
        }
        assertThrows(SpeedTestValidationError.InvalidIPRange::class.java) {
            SpeedTestParameters(ipRange = "2001:db8::/200").validated()
        }
    }

    @Test
    fun validCidrList() {
        SpeedTestParameters(
            ipRange = "2606:4700::/32,2400:cb00::/32",
        ).validated()
    }

    @Test
    fun ipFileExistenceOptionalUnlessRequested(@TempDir dir: Path) {
        val missing = File(dir.toFile(), "gone.txt").absolutePath
        val withMissing = SpeedTestParameters.defaultsForFile(missing)
        // Without existence check, pure shape validation may pass for empty range + file path.
        assertNull(withMissing.validationMessage(checkIpFileExists = false))
        assertThrows(SpeedTestValidationError.IpFileNotFound::class.java) {
            withMissing.validated(checkIpFileExists = true)
        }

        val present = File(dir.toFile(), "list.txt")
        present.writeText("2001:db8::1\n")
        SpeedTestParameters.defaultsForFile(present.absolutePath)
            .validated(checkIpFileExists = true)
    }

    @Test
    fun commandLineArgumentsUsesValidated() {
        assertThrows(SpeedTestValidationError::class.java) {
            SpeedTestParameters(ipRange = "2001:db8::/32", port = 0)
                .commandLineArguments("r.csv")
        }
    }
}
