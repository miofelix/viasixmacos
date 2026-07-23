package dev.viasix.app.session

import org.junit.Assert.assertEquals
import org.junit.Test

class VpnPermissionStateTest {
    @Test
    fun labelsDistinguishConsentFromSystemSettings() {
        val denied = VpnPermissionState(granted = false)
        val granted = VpnPermissionState(granted = true)

        assertEquals("未授权", denied.statusLabel)
        assertEquals("授予 VPN 权限", denied.actionLabel)
        assertEquals("已授权", granted.statusLabel)
        assertEquals("打开系统 VPN 设置", granted.actionLabel)
    }
}
