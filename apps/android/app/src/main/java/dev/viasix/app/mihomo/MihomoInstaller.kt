package dev.viasix.app.mihomo

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Installs the bundled mihomo binary from assets into the app private files dir.
 * Currently ships arm64-v8a asset name `mihomo/mihomo-arm64`.
 */
object MihomoInstaller {
    private const val TAG = "MihomoInstaller"
    private const val ASSET_ARM64 = "mihomo/mihomo-arm64"
    private const val BINARY_NAME = "mihomo"

    fun installIfNeeded(context: Context): File {
        val destDir = File(context.filesDir, "mihomo")
        if (!destDir.exists() && !destDir.mkdirs()) {
            throw IOException("Cannot create mihomo dir: ${destDir.absolutePath}")
        }
        val dest = File(destDir, BINARY_NAME)
        val assetName = selectAsset()
        val needsCopy =
            !dest.isFile ||
                !dest.canExecute() ||
                dest.length() == 0L

        if (needsCopy) {
            Log.i(TAG, "Installing mihomo from assets/$assetName -> ${dest.absolutePath}")
            try {
                context.assets.open(assetName).use { input ->
                    FileOutputStream(dest).use { output -> input.copyTo(output) }
                }
            } catch (error: Exception) {
                throw IOException(
                    "Mihomo asset missing ($assetName). Run: node apps/android/scripts/fetch-mihomo.mjs",
                    error,
                )
            }
            // Best-effort executable bit for native process launch.
            dest.setReadable(true, false)
            dest.setExecutable(true, false)
            if (!dest.canExecute()) {
                // Some devices ignore setExecutable; still try ProcessBuilder.
                Log.w(TAG, "mihomo may not be marked executable")
            }
        }
        return dest
    }

    private fun selectAsset(): String {
        val abis = Build.SUPPORTED_ABIS
        if (abis.any { it.contains("arm64") || it == "aarch64" }) {
            return ASSET_ARM64
        }
        // Fall back to arm64 asset with a clear runtime failure on incompatible ABIs.
        Log.w(TAG, "Unsupported ABI list ${abis.joinToString()}; trying arm64 asset")
        return ASSET_ARM64
    }
}
