package dev.viasix.app.prefs

import android.content.Context
import org.json.JSONObject

/**
 * Lightweight SharedPreferences-backed session state for the Android shell.
 */
data class SessionPrefs(
    val profileYaml: String = "",
    val selectedAddress: String = "2001:db8::1",
    val routingMode: String = "rule",
    val fullTunnel: Boolean = true,
) {
    fun toJson(): JSONObject =
        JSONObject()
            .put("profileYaml", profileYaml)
            .put("selectedAddress", selectedAddress)
            .put("routingMode", routingMode)
            .put("fullTunnel", fullTunnel)

    companion object {
        fun fromJson(raw: String?): SessionPrefs {
            if (raw.isNullOrBlank()) return SessionPrefs()
            return try {
                val o = JSONObject(raw)
                SessionPrefs(
                    profileYaml = o.optString("profileYaml", ""),
                    selectedAddress = o.optString("selectedAddress", "2001:db8::1"),
                    routingMode = o.optString("routingMode", "rule"),
                    fullTunnel = o.optBoolean("fullTunnel", true),
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

    companion object {
        private const val PREFS_NAME = "viasix_session"
        private const val KEY = "session"
    }
}
