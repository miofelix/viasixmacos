package dev.viasix.app.cfst

import android.content.Context
import android.os.Build
import android.util.Log
import dev.viasix.app.runtime.RuntimeBinaryInstall
import dev.viasix.app.runtime.RuntimeComponentCondition
import dev.viasix.app.runtime.RuntimeComponentInfo
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
    )

    @Synchronized
    fun installIfNeeded(
        context: Context,
        force: Boolean = false,
    ): InstallResult {
        if (!isArm64()) {
            throw IOException("设备 ABI 非 arm64，当前 APK 仅包含 arm64 CFST")
        }
        val destDir = File(context.filesDir, "cfst")
        if (!destDir.exists() && !destDir.mkdirs()) {
            throw IOException("Cannot create cfst dir: ${destDir.absolutePath}")
        }

        val binary = File(destDir, BINARY_NAME)
        val ipv6List = File(destDir, IPV6_LIST_NAME)
        RuntimeBinaryInstall.installAssetBinary(
            context = context,
            assetPath = ASSET_BINARY_ARM64,
            dest = binary,
            missingHint =
                "CFST asset missing ($ASSET_BINARY_ARM64). Rebuild after: node apps/android/scripts/fetch-cfst.mjs",
            force = force,
        )
        RuntimeBinaryInstall.installAssetFile(
            context = context,
            assetPath = ASSET_IPV6_LIST,
            dest = ipv6List,
            missingHint = "CFST ipv6 list asset missing ($ASSET_IPV6_LIST)",
            force = force,
        )

        return InstallResult(
            binary = binary,
            ipv6List = ipv6List,
        )
    }

    fun inspectInstalled(context: Context): RuntimeComponentInfo {
        val destDir = File(context.filesDir, "cfst")
        val binary = File(destDir, BINARY_NAME)
        val ipv6List = File(destDir, IPV6_LIST_NAME)
        if (!isArm64()) {
            return RuntimeComponentInfo(
                condition = RuntimeComponentCondition.UNSUPPORTED,
                detail = "设备 ABI 非 arm64；此 APK 未打包对应架构的 CFST",
                path = binary.absolutePath,
            )
        }
        val inspection = RuntimeBinaryInstall.inspectElfBinary(binary)
        val listReady = RuntimeBinaryInstall.isPresent(ipv6List)
        val condition =
            when {
                inspection.condition == RuntimeBinaryInstall.BinaryCondition.MISSING ||
                    inspection.condition == RuntimeBinaryInstall.BinaryCondition.EMPTY ||
                    !ipv6List.exists() -> RuntimeComponentCondition.MISSING
                !inspection.ready || !listReady -> RuntimeComponentCondition.INVALID
                else -> RuntimeComponentCondition.READY
            }
        val detail =
            if (inspection.ready && listReady) {
                "AArch64 ELF · ${inspection.sizeBytes / 1024} KB · 列表 ${ipv6List.length()} B"
            } else {
                buildList {
                    if (!inspection.ready) add(binaryDetail(inspection))
                    if (!listReady && ipv6List.exists()) {
                        add("IPv6 列表为空；需要重新安装")
                    } else if (!listReady) {
                        add("缺少 IPv6 列表；需要安装")
                    }
                }.joinToString("；")
            }
        return RuntimeComponentInfo(
            condition = condition,
            detail = detail,
            path = binary.absolutePath,
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
                    detail = error.message ?: "CFST 修复失败",
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

    private fun binaryDetail(inspection: RuntimeBinaryInstall.BinaryInspection): String =
        when (inspection.condition) {
            RuntimeBinaryInstall.BinaryCondition.MISSING -> "CFST 未安装"
            RuntimeBinaryInstall.BinaryCondition.EMPTY -> "CFST 文件为空；需要重新安装"
            RuntimeBinaryInstall.BinaryCondition.INVALID_FORMAT ->
                "CFST 不是完整的 64-bit little-endian ELF"
            RuntimeBinaryInstall.BinaryCondition.INCOMPATIBLE_ARCHITECTURE ->
                "CFST 架构不兼容（machine=${inspection.machine ?: "?"}，需要 AArch64）"
            RuntimeBinaryInstall.BinaryCondition.NOT_EXECUTABLE ->
                "CFST 缺少执行权限；需要修复"
            RuntimeBinaryInstall.BinaryCondition.READY ->
                "AArch64 ELF · ${inspection.sizeBytes / 1024} KB"
        }
}
