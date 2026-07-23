package dev.viasix.app.cfst

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Structural checks that installer constants stay aligned with fetch-cfst assets.
 * Full install needs Android Context; binary is gitignored until fetch-cfst runs.
 */
class CfstInstallerSurfaceTest {
    @Test
    fun assetPathsMatchFetchScriptLayout() {
        assertEquals("cfst/cfst-arm64", CfstInstaller.ASSET_BINARY_ARM64)
        assertEquals("cfst/ipv6.txt", CfstInstaller.ASSET_IPV6_LIST)
        assertEquals("cfst", CfstInstaller.BINARY_NAME)
        assertEquals("ipv6.txt", CfstInstaller.IPV6_LIST_NAME)
    }

    @Test
    fun bundledIpv6ListAssetIsPresentOnClasspathOrSourceTree() {
        assertTrue(CfstInstaller.ASSET_BINARY_ARM64.startsWith("cfst/"))
        assertTrue(CfstInstaller.ASSET_IPV6_LIST.endsWith("ipv6.txt"))
        val ipv6 =
            listOf(
                File("src/main/assets/cfst/ipv6.txt"),
                File("app/src/main/assets/cfst/ipv6.txt"),
                File("apps/android/app/src/main/assets/cfst/ipv6.txt"),
            ).firstOrNull { it.isFile }
        assertTrue("ipv6.txt must exist in assets", ipv6 != null && ipv6.length() > 0)
    }

    @Test
    fun cfstBinaryPresentForDeviceApkOrDocumentedMissing() {
        // When building a device APK, fetch-cfst must have run. Fail unit tests if
        // neither the binary nor an intentional empty-tree is acceptable for CI?
        // Prefer soft-check: if binary exists it must be non-empty ELF-sized.
        val bin =
            listOf(
                File("src/main/assets/cfst/cfst-arm64"),
                File("app/src/main/assets/cfst/cfst-arm64"),
                File("apps/android/app/src/main/assets/cfst/cfst-arm64"),
            ).firstOrNull { it.isFile }
        if (bin != null) {
            assertTrue("cfst-arm64 must not be empty", bin.length() > 1_000_000)
        }
    }
}
