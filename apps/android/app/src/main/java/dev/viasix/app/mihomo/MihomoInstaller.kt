package dev.viasix.app.mihomo

import android.content.Context
import android.os.Build
import android.util.Log
import dev.viasix.app.runtime.RuntimeBinaryInstall
import dev.viasix.app.runtime.RuntimeComponentCondition
import dev.viasix.app.runtime.RuntimeComponentInfo
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

    @Synchronized
    fun installIfNeeded(
        context: Context,
        force: Boolean = false,
    ): File {
        if (!isArm64()) {
            throw IOException("设备 ABI 非 arm64，当前 APK 仅包含 arm64-v8a mihomo")
        }
        val destDir = File(context.filesDir, "mihomo")
        val dest = File(destDir, BINARY_NAME)
        return RuntimeBinaryInstall.installAssetBinary(
            context = context,
            assetPath = ASSET_ARM64,
            dest = dest,
            missingHint =
                "Mihomo asset missing ($ASSET_ARM64). Rebuild after: node apps/android/scripts/fetch-mihomo.mjs",
            force = force,
        )
    }

    fun inspectInstalled(context: Context): RuntimeComponentInfo {
        val file = File(File(context.filesDir, "mihomo"), BINARY_NAME)
        if (!isArm64()) {
            return RuntimeComponentInfo(
                condition = RuntimeComponentCondition.UNSUPPORTED,
                detail = "设备 ABI 非 arm64；此 APK 未打包对应架构的 mihomo",
                path = file.absolutePath,
            )
        }
        val inspection = RuntimeBinaryInstall.inspectElfBinary(file)
        val condition =
            when (inspection.condition) {
                RuntimeBinaryInstall.BinaryCondition.READY -> RuntimeComponentCondition.READY
                RuntimeBinaryInstall.BinaryCondition.MISSING,
                RuntimeBinaryInstall.BinaryCondition.EMPTY -> RuntimeComponentCondition.MISSING
                RuntimeBinaryInstall.BinaryCondition.INVALID_FORMAT,
                RuntimeBinaryInstall.BinaryCondition.INCOMPATIBLE_ARCHITECTURE,
                RuntimeBinaryInstall.BinaryCondition.NOT_EXECUTABLE -> RuntimeComponentCondition.INVALID
            }
        return RuntimeComponentInfo(
            condition = condition,
            detail = binaryDetail(inspection),
            path = file.absolutePath,
            sizeBytes = inspection.sizeBytes.takeIf { it > 0L },
        )
    }

    fun repair(context: Context): RuntimeComponentInfo =
        if (!isArm64()) {
            inspectInstalled(context)
        } else {
            try {
                installIfNeeded(context, force = true)
                inspectInstalled(context)
            } catch (error: Exception) {
                Log.w(TAG, "repair: ${error.message}")
                RuntimeComponentInfo(
                    condition = RuntimeComponentCondition.ERROR,
                    detail = error.message ?: "mihomo 修复失败",
                )
            }
        }

    fun isArm64(): Boolean {
        val abis = Build.SUPPORTED_ABIS
        return abis.any { it.contains("arm64") || it == "aarch64" }
    }

    private fun binaryDetail(inspection: RuntimeBinaryInstall.BinaryInspection): String =
        when (inspection.condition) {
            RuntimeBinaryInstall.BinaryCondition.MISSING -> "未安装；可从 APK 内置资产修复"
            RuntimeBinaryInstall.BinaryCondition.EMPTY -> "文件为空；需要重新安装"
            RuntimeBinaryInstall.BinaryCondition.INVALID_FORMAT ->
                "文件不是完整的 64-bit little-endian ELF"
            RuntimeBinaryInstall.BinaryCondition.INCOMPATIBLE_ARCHITECTURE ->
                "ELF 架构不兼容（machine=${inspection.machine ?: "?"}，需要 AArch64）"
            RuntimeBinaryInstall.BinaryCondition.NOT_EXECUTABLE -> "ELF 缺少执行权限；需要修复"
            RuntimeBinaryInstall.BinaryCondition.READY ->
                "AArch64 ELF · ${inspection.sizeBytes / 1024} KB"
        }
}
