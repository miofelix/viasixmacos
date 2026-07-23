package dev.viasix.app.session

data class UnderlyingNetworkSelection<T>(
    val network: T? = null,
    val label: String = "正在检测",
) {
    fun updated(
        network: T,
        label: String,
    ): UnderlyingNetworkSelection<T> =
        if (this.network == network && this.label == label) this else copy(network = network, label = label)

    /** Ignore a delayed loss callback for a network that is no longer selected. */
    fun lost(network: T): UnderlyingNetworkSelection<T> =
        if (this.network == network) UnderlyingNetworkSelection(label = "网络切换中") else this
}

object UnderlyingNetworkPresentation {
    fun label(
        wifi: Boolean,
        cellular: Boolean,
        ethernet: Boolean,
        validated: Boolean,
    ): String {
        val transport =
            when {
                wifi -> "Wi-Fi"
                cellular -> "蜂窝网络"
                ethernet -> "以太网"
                else -> "其他网络"
            }
        return "$transport · ${if (validated) "已联网" else "待验证"}"
    }
}
