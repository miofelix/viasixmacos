package dev.viasix.app.runtime

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Pure contract checks for install destination readiness used by mihomo/CFST installers.
 */
class RuntimeBinaryInstallContractTest {
    @Test
    fun isPresent_rejectsMissingAndEmpty() {
        val missing = File("/tmp/viasix-definitely-missing-binary-xyz")
        assertFalse(RuntimeBinaryInstall.isPresent(missing))

        val empty = File.createTempFile("viasix-empty", ".bin")
        empty.writeBytes(ByteArray(0))
        assertFalse(RuntimeBinaryInstall.isPresent(empty))
        empty.delete()
    }

    @Test
    fun isPresent_acceptsNonEmptyFile() {
        val f = File.createTempFile("viasix-bin", ".bin")
        f.writeBytes(byteArrayOf(0x7f, 'E'.code.toByte(), 'L'.code.toByte(), 'F'.code.toByte()))
        assertTrue(RuntimeBinaryInstall.isPresent(f))
        f.delete()
    }
}
