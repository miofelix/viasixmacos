package dev.viasix.app.session

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/** Discovers launchable apps without requesting broad package visibility. */
class InstalledAppsRepository(
    private val context: Context,
) {
    fun load(): List<InstalledAppInfo> {
        val packageManager = context.packageManager
        val launcherIntent =
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.queryIntentActivities(
                    launcherIntent,
                    PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_ALL.toLong()),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.queryIntentActivities(launcherIntent, PackageManager.MATCH_ALL)
            }
        return resolved
            .asSequence()
            .mapNotNull { info ->
                val packageName = info.activityInfo?.packageName?.trim().orEmpty()
                if (packageName.isEmpty() || packageName == context.packageName) {
                    null
                } else {
                    InstalledAppInfo(
                        packageName = packageName,
                        label = info.loadLabel(packageManager).toString().ifBlank { packageName },
                    )
                }
            }
            .distinctBy { it.packageName }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.label })
            .toList()
    }
}
