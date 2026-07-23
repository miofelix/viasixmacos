package dev.viasix.app.runtime

import android.content.Context
import android.system.Os
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Shared helpers for shipping arm64 sidecar binaries from assets → filesDir.
 * Fixes common Android install failures: missing execute bit, zero-length dest,
 * and stale empty copies that never re-extract.
 */
internal object RuntimeBinaryInstall {
    private const val TAG = "RuntimeBinaryInstall"

    /**
     * Copy [assetPath] to [dest] when missing, empty, or not executable.
     * Always re-applies execute permissions after a successful install.
     */
    fun installAssetBinary(
        context: Context,
        assetPath: String,
        dest: File,
        missingHint: String,
    ): File {
        val parent = dest.parentFile
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw IOException("Cannot create dir: ${parent.absolutePath}")
        }

        val needsCopy = !dest.isFile || dest.length() == 0L
        if (needsCopy) {
            Log.i(TAG, "Installing assets/$assetPath -> ${dest.absolutePath}")
            try {
                // Atomic-ish write: temp then rename so a crash mid-copy doesn't leave a half file.
                val tmp = File(dest.absolutePath + ".tmp")
                context.assets.open(assetPath).use { input ->
                    FileOutputStream(tmp).use { output -> input.copyTo(output) }
                }
                if (tmp.length() == 0L) {
                    tmp.delete()
                    throw IOException("asset $assetPath is empty")
                }
                if (dest.exists()) dest.delete()
                if (!tmp.renameTo(dest)) {
                    tmp.copyTo(dest, overwrite = true)
                    tmp.delete()
                }
            } catch (error: Exception) {
                throw IOException(missingHint, error)
            }
        }

        ensureExecutable(dest)
        if (!dest.isFile || dest.length() == 0L) {
            throw IOException("install failed: ${dest.absolutePath}")
        }
        return dest
    }

    fun installAssetFile(
        context: Context,
        assetPath: String,
        dest: File,
        missingHint: String,
    ): File {
        val parent = dest.parentFile
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw IOException("Cannot create dir: ${parent.absolutePath}")
        }
        if (!dest.isFile || dest.length() == 0L) {
            Log.i(TAG, "Installing assets/$assetPath -> ${dest.absolutePath}")
            try {
                context.assets.open(assetPath).use { input ->
                    FileOutputStream(dest).use { output -> input.copyTo(output) }
                }
            } catch (error: Exception) {
                throw IOException(missingHint, error)
            }
        }
        return dest
    }

    fun ensureExecutable(file: File) {
        try {
            file.setReadable(true, false)
            file.setExecutable(true, false)
            file.setExecutable(true, true)
        } catch (_: Exception) {
        }
        try {
            // 0755 — required for ProcessBuilder on many Android versions.
            Os.chmod(file.absolutePath, 0b111_101_101)
        } catch (error: Exception) {
            Log.w(TAG, "chmod ${file.name}: ${error.message}")
        }
        if (!file.canExecute()) {
            Log.w(TAG, "${file.name} may not be marked executable after install")
        }
    }

    fun isPresent(file: File): Boolean = file.isFile && file.length() > 0L
}
