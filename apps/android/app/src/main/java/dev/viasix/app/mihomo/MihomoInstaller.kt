package dev.viasix.app.mihomo

import android.content.Context
import android.os.Build
import android.util.Log
import dev.viasix.app.runtime.RuntimeBinaryInstall
import java.io.File
import java.io.IOException

/**
 * Installs the bundled mihomo binary from assets into the app private files dir.
 * Currently ships arm64-v8a asset name `mihomo/mihomo-arm64`.
 */
object MihomoInstaller {
    private const val TAG = "MihomoInstaller"
    const val ASSET_ARM64 = "mihomo/mihomo-arm64"
    const val BINARY_NAME = "mihomo"

    data class Status(
        val binary: File?,
        val ready: Boolean,
        val abiSupported: Boolean,
        val message: String,
    )

    fun installIfNeeded(context: Context): File {
        val destDir = File(context.filesDir, "mihomo")
        val dest = File(destDir, BINARY_NAME)
        val assetName = selectAsset()
        return RuntimeBinaryInstall.installAssetBinary(
            context = context,
            assetPath = assetName,
            dest = dest,
            missingHint =
                "Mihomo asset missing ($assetName). Rebuild after: node apps/android/scripts/fetch-mihomo.mjs",
        )
    }

    /** Probe/install for Settings UI without throwing to the UI thread. */
    fun ensureInstalled(context: Context): Status {
        val abi = isArm64()
        return try {
            val file = installIfNeeded(context)
            val ready = RuntimeBinaryInstall.isPresent(file)
            Status(
                binary = file,
                ready = ready,
                abiSupported = abi,
                message =
                    when {
                        !abi -> "设备 ABI 非 arm64，当前仅打包 arm64 内核"
                        ready -> "已就绪（${file.length() / 1024} KB）"
                        else -> "安装后文件无效"
                    },
            )
        } catch (error: Exception) {
            Log.w(TAG, "ensureInstalled: ${error.message}")
            Status(
                binary = null,
                ready = false,
                abiSupported = abi,
                message = error.message ?: "mihomo 安装失败",
            )
        }
    }

    fun isArm64(): Boolean {
        val abis = Build.SUPPORTED_ABIS
        return abis.any { it.contains("arm64") || it == "aarch64" }
    }

    private fun selectAsset(): String {
        if (!isArm64()) {
            Log.w(TAG, "Unsupported ABI list ${Build.SUPPORTED_ABIS.joinToString()}; trying arm64 asset")
        }
        return ASSET_ARM64
    }
}
