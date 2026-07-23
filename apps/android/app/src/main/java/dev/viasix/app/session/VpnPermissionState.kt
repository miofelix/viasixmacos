package dev.viasix.app.session

data class VpnPermissionState(
    val granted: Boolean = false,
) {
    val statusLabel: String
        get() = if (granted) "已授权" else "未授权"

    val actionLabel: String
        get() = if (granted) "打开系统 VPN 设置" else "授予 VPN 权限"
}
