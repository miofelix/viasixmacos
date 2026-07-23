package dev.viasix.app.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppRoutingPolicyTest {
    private val ownPackage = "dev.viasix.app"

    @Test
    fun allAndBypassModesAlwaysKeepViaSixOutsideTheVpn() {
        val all = AppRoutingPolicy.rules(AppRoutingMode.ALL, emptyList(), ownPackage)
        val bypass =
            AppRoutingPolicy.rules(
                AppRoutingMode.BYPASS_SELECTED,
                listOf("com.example.video", ownPackage, "com.example.video"),
                ownPackage,
            )

        assertEquals(emptyList<String>(), all.allowedPackages)
        assertEquals(listOf(ownPackage), all.disallowedPackages)
        assertEquals(emptyList<String>(), bypass.allowedPackages)
        assertEquals(
            listOf(ownPackage, "com.example.video"),
            bypass.disallowedPackages,
        )
    }

    @Test
    fun onlySelectedModeBuildsAnAllowlistWithoutViaSix() {
        val rules =
            AppRoutingPolicy.rules(
                AppRoutingMode.ONLY_SELECTED,
                listOf(
                    "com.example.browser",
                    ownPackage,
                    "com.example.chat",
                    "not-a-package",
                ),
                ownPackage,
            )

        assertEquals(
            listOf("com.example.browser", "com.example.chat"),
            rules.allowedPackages,
        )
        assertEquals(emptyList<String>(), rules.disallowedPackages)
    }

    @Test
    fun stateKeepsSelectedUninstalledAppsVisibleAndToggleable() {
        val state =
            AppRoutingState(
                selectedPackages = listOf("com.example.old"),
            ).withInstalledApps(
                listOf(InstalledAppInfo("com.example.chat", "Chat")),
            )

        assertEquals("com.example.old", state.installedApps.first().packageName)
        assertFalse(state.installedApps.first().launchable)
        assertTrue(state.togglePackage("com.example.chat").selectedPackages.contains("com.example.chat"))
        assertFalse(state.togglePackage("com.example.old").selectedPackages.contains("com.example.old"))
    }

    @Test
    fun manualPackageNamesRequireAQualifiedAndroidIdentifier() {
        assertTrue(AppRoutingPolicy.isValidPackageName("com.example.background_service"))
        assertFalse(AppRoutingPolicy.isValidPackageName("background_service"))
        assertFalse(AppRoutingPolicy.isValidPackageName("https://example.com"))
        assertFalse(AppRoutingPolicy.isValidPackageName("com.example.bad-name"))
    }
}
