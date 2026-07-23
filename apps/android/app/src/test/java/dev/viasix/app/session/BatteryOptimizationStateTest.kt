package dev.viasix.app.session

import org.junit.Assert.assertEquals
import org.junit.Test

class BatteryOptimizationStateTest {
    @Test
    fun labelsExposeWhetherLongRunningVpnIsExempt() {
        assertEquals("受系统优化", BatteryOptimizationState(exempt = false).statusLabel)
        assertEquals("不受限制", BatteryOptimizationState(exempt = true).statusLabel)
    }
}
