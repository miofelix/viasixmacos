package dev.viasix.app.session

enum class AppRoutingMode(
    val wire: String,
    val label: String,
    val detail: String,
) {
    ALL(
        wire = "all",
        label = "所有应用",
        detail = "除 ViaSix 自身外，所有应用均进入 VPN。",
    ),
    BYPASS_SELECTED(
        wire = "bypass_selected",
        label = "绕过所选应用",
        detail = "所选应用直接联网，其余应用进入 VPN。",
    ),
    ONLY_SELECTED(
        wire = "only_selected",
        label = "仅代理所选应用",
        detail = "只有所选应用进入 VPN，其余应用直接联网。",
    ),
    ;

    companion object {
        fun parse(wire: String?): AppRoutingMode =
            entries.firstOrNull { it.wire == wire } ?: ALL
    }
}

data class InstalledAppInfo(
    val packageName: String,
    val label: String,
    val launchable: Boolean = true,
)

data class AppRoutingState(
    val mode: AppRoutingMode = AppRoutingMode.ALL,
    val selectedPackages: List<String> = emptyList(),
    val installedApps: List<InstalledAppInfo> = emptyList(),
    val isLoadingApps: Boolean = false,
) {
    val selectedCount: Int
        get() = selectedPackages.size

    fun togglePackage(packageName: String): AppRoutingState {
        val normalized = packageName.trim()
        if (normalized.isEmpty()) return this
        val next = selectedPackages.toMutableSet()
        val added = next.add(normalized)
        if (!added) next.remove(normalized)
        val nextApps =
            when {
                added && installedApps.none { it.packageName == normalized } ->
                    installedApps +
                        InstalledAppInfo(
                            packageName = normalized,
                            label = normalized,
                            launchable = false,
                        )
                !added ->
                    installedApps.filterNot {
                        it.packageName == normalized && !it.launchable
                    }
                else -> installedApps
            }
        return copy(
            selectedPackages = next.sorted(),
            installedApps = nextApps,
        )
    }

    fun withInstalledApps(discovered: List<InstalledAppInfo>): AppRoutingState {
        val byPackage = discovered.associateBy { it.packageName }.toMutableMap()
        selectedPackages.forEach { packageName ->
            byPackage.putIfAbsent(
                packageName,
                InstalledAppInfo(
                    packageName = packageName,
                    label = packageName,
                    launchable = false,
                ),
            )
        }
        return copy(
            installedApps =
                byPackage.values.sortedWith(
                    compareBy<InstalledAppInfo> { !selectedPackages.contains(it.packageName) }
                        .thenBy(String.CASE_INSENSITIVE_ORDER) { it.label },
                ),
        )
    }
}

data class AppRoutingRules(
    val allowedPackages: List<String>,
    val disallowedPackages: List<String>,
)

object AppRoutingPolicy {
    private val packageNamePattern =
        Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$")

    fun isValidPackageName(value: String): Boolean =
        packageNamePattern.matches(value.trim())

    fun rules(
        mode: AppRoutingMode,
        selectedPackages: Collection<String>,
        ownPackage: String,
    ): AppRoutingRules {
        val selected =
            selectedPackages
                .asSequence()
                .map(String::trim)
                .filter { isValidPackageName(it) && it != ownPackage }
                .distinct()
                .sorted()
                .toList()
        return when (mode) {
            AppRoutingMode.ALL ->
                AppRoutingRules(
                    allowedPackages = emptyList(),
                    disallowedPackages = listOf(ownPackage),
                )
            AppRoutingMode.BYPASS_SELECTED ->
                AppRoutingRules(
                    allowedPackages = emptyList(),
                    disallowedPackages = (listOf(ownPackage) + selected).distinct(),
                )
            AppRoutingMode.ONLY_SELECTED ->
                AppRoutingRules(
                    allowedPackages = selected,
                    disallowedPackages = emptyList(),
                )
        }
    }
}
