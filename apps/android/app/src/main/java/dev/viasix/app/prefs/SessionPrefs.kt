package dev.viasix.app.prefs

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * SharedPreferences-backed session state for the Android shell.
 * Extends macOS-aligned fields: node candidates, exit-IP detection prefs.
 */
data class SessionPrefs(
    val profileYaml: String = "",
    val selectedAddress: String = "2001:db8::1",
    val routingMode: String = "rule",
    val fullTunnel: Boolean = true,
    val candidateAddresses: List<String> = emptyList(),
    val exitIPEndpoint: String = "https://api.myip.la/cn?json",
    val exitIPDetectionMode: String = "automatic",
    /** Last CFST IP range (comma-separated CIDRs / addresses). */
    val lastSpeedIpRange: String = "2606:4700::/32",
    /** When true, CFST uses bundled ipv6.txt (`-f`) instead of [lastSpeedIpRange]. */
    val speedUseBundledList: Boolean = false,
    val speedDisableDownload: Boolean = false,
) {
    fun toJson(): JSONObject =
        JSONObject()
            .put("profileYaml", profileYaml)
            .put("selectedAddress", selectedAddress)
            .put("routingMode", routingMode)
            .put("fullTunnel", fullTunnel)
            .put(
                "candidateAddresses",
                JSONArray().also { arr ->
                    candidateAddresses.forEach { arr.put(it) }
                },
            )
            .put("exitIPEndpoint", exitIPEndpoint)
            .put("exitIPDetectionMode", exitIPDetectionMode)
            .put("lastSpeedIpRange", lastSpeedIpRange)
            .put("speedUseBundledList", speedUseBundledList)
            .put("speedDisableDownload", speedDisableDownload)

    companion object {
        fun fromJson(raw: String?): SessionPrefs {
            if (raw.isNullOrBlank()) return SessionPrefs()
            return try {
                val o = JSONObject(raw)
                val candidates = mutableListOf<String>()
                val arr = o.optJSONArray("candidateAddresses")
                if (arr != null) {
                    for (i in 0 until arr.length()) {
                        val value = arr.optString(i).trim()
                        if (value.isNotEmpty()) candidates += value
                    }
                }
                SessionPrefs(
                    profileYaml = o.optString("profileYaml", ""),
                    selectedAddress = o.optString("selectedAddress", "2001:db8::1"),
                    routingMode = o.optString("routingMode", "rule"),
                    fullTunnel = o.optBoolean("fullTunnel", true),
                    candidateAddresses = candidates,
                    exitIPEndpoint =
                        o.optString("exitIPEndpoint", "https://api.myip.la/cn?json")
                            .ifBlank { "https://api.myip.la/cn?json" },
                    exitIPDetectionMode = o.optString("exitIPDetectionMode", "automatic"),
                    lastSpeedIpRange =
                        o.optString("lastSpeedIpRange", "2606:4700::/32")
                            .ifBlank { "2606:4700::/32" },
                    speedUseBundledList = o.optBoolean("speedUseBundledList", false),
                    speedDisableDownload = o.optBoolean("speedDisableDownload", false),
                )
            } catch (_: Exception) {
                SessionPrefs()
            }
        }
    }
}

class SessionPrefsStore(context: Context) {
    private val prefs =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun load(): SessionPrefs = SessionPrefs.fromJson(prefs.getString(KEY, null))

    fun save(value: SessionPrefs) {
        prefs.edit().putString(KEY, value.toJson().toString()).apply()
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val PREFS_NAME = "viasix_session"
        private const val KEY = "session"
    }
}
