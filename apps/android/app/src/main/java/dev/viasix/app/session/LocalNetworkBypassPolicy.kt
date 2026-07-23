package dev.viasix.app.session

/** Android 13+ routes excluded when the user explicitly keeps local traffic outside VPN. */
object LocalNetworkBypassPolicy {
    val IPV4_PREFIXES =
        listOf(
            "10.0.0.0/8",
            "127.0.0.0/8",
            "169.254.0.0/16",
            "172.16.0.0/12",
            "192.168.0.0/16",
            "224.0.0.0/4",
            "255.255.255.255/32",
        )

    val IPV6_PREFIXES =
        listOf(
            "::1/128",
            "fc00::/7",
            "fe80::/10",
            "ff00::/8",
        )
}
