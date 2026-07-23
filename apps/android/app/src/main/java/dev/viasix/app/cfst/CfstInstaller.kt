package dev.viasix.app.cfst

import android.content.Context
import android.os.Build
import android.util.Log
import dev.viasix.app.runtime.RuntimeBinaryInstall
import java.io.File
import java.io.IOException

/**
 * Installs the bundled CFST binary and default IPv6 list from assets into the
 * app private files directory (same pattern as [dev.viasix.app.mihomo.MihomoInstaller]).
 *
 * Ships arm64 only (`cfst/cfst-arm64` from `scripts/fetch-cfst.mjs`, linux_arm64
 * upstream, statically linked). Callers should surface a clear error on unsupported ABIs.
 */
object CfstInstaller {
    private const val TAG = "CfstInstaller"
    const val ASSET_BINARY_ARM64 = "cfst/cfst-arm64"
    const val ASSET_IPV6_LIST = "cfst/ipv6.txt"
    const val BINARY_NAME = "cfst"
    const val IPV6_LIST_NAME = "ipv6.txt"

    data class InstallResult(
        val binary: File,
        val ipv6List: File,
        val abiSupported: Boolean,
    )

    data class Status(
        val binary: File?,
        val ipv6List: File?,
        val ready: Boolean,
        val abiSupported: Boolean,
        val message: String,
    )

    fun installIfNeeded(context: Context): InstallResult {
        val destDir = File(context.filesDir, "cfst")
        if (!destDir.exists() && !destDir.mkdirs()) {
            throw IOException("Cannot create cfst dir: ${destDir.absolutePath}")
        }

        val binary = File(destDir, BINARY_NAME)
        val ipv6List = File(destDir, IPV6_LIST_NAME)
        val abiSupported = isArm64()

        RuntimeBinaryInstall.installAssetBinary(
            context = context,
            assetPath = ASSET_BINARY_ARM64,
            dest = binary,
            missingHint =
                "CFST asset missing ($ASSET_BINARY_ARM64). Rebuild after: node apps/android/scripts/fetch-cfst.mjs",
        )
        RuntimeBinaryInstall.installAssetFile(
            context = context,
            assetPath = ASSET_IPV6_LIST,
            dest = ipv6List,
            missingHint = "CFST ipv6 list asset missing ($ASSET_IPV6_LIST)",
        )

        return InstallResult(
            binary = binary,
            ipv6List = ipv6List,
            abiSupported = abiSupported,
        )
    }

    fun ensureInstalled(context: Context): Status {
        val abi = isArm64()
        return try {
            val result = installIfNeeded(context)
            val ready =
                RuntimeBinaryInstall.isPresent(result.binary) &&
                    RuntimeBinaryInstall.isPresent(result.ipv6List)
            Status(
                binary = result.binary,
                ipv6List = result.ipv6List,
                ready = ready,
                abiSupported = abi,
                message =
                    when {
                        !abi -> "设备 ABI 非 arm64，当前仅打包 arm64 CFST"
                        ready ->
                            "已就绪（${result.binary.length() / 1024} KB，列表 ${result.ipv6List.length()} B）"
                        else -> "安装后文件不完整"
                    },
            )
        } catch (error: Exception) {
            Log.w(TAG, "ensureInstalled: ${error.message}")
            Status(
                binary = null,
                ipv6List = null,
                ready = false,
                abiSupported = abi,
                message = error.message ?: "CFST 安装失败",
            )
        }
    }

    fun isArm64(): Boolean {
        val abis = Build.SUPPORTED_ABIS
        return abis.any { it.contains("arm64") || it == "aarch64" }
    }

    fun workDir(context: Context): File {
        val dir = File(context.filesDir, "cfst/work")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }
}
