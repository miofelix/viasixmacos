package dev.viasix.app.session

data class BatteryOptimizationState(
    val exempt: Boolean = false,
) {
    val statusLabel: String
        get() = if (exempt) "不受限制" else "受系统优化"
}
