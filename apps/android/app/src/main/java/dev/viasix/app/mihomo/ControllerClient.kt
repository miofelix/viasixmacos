package dev.viasix.app.mihomo

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

data class ControllerHealth(
    val ok: Boolean,
    val message: String,
    val version: String? = null,
)

data class TrafficSample(
    val live: Boolean,
    val message: String,
    val uploadTotal: Long = 0,
    val downloadTotal: Long = 0,
)

/**
 * Minimal Mihomo external-controller HTTP client for health and traffic totals.
 */
object ControllerClient {
    fun probe(host: String, port: Int, secret: String, timeoutMs: Int = 3000): ControllerHealth {
        return try {
            val conn = open("http://$host:$port/version", secret, timeoutMs)
            val code = conn.responseCode
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            if (code !in 200..299) {
                ControllerHealth(false, "HTTP $code")
            } else {
                val version =
                    runCatching { JSONObject(body).optString("version").ifBlank { null } }
                        .getOrNull()
                ControllerHealth(
                    ok = true,
                    message = version?.let { "controller ok (version $it)" } ?: "controller ok",
                    version = version,
                )
            }
        } catch (error: Exception) {
            ControllerHealth(false, "unreachable: ${error.message}")
        }
    }

    fun connectionsTotals(
        host: String,
        port: Int,
        secret: String,
        timeoutMs: Int = 3000,
    ): TrafficSample {
        return try {
            val conn = open("http://$host:$port/connections", secret, timeoutMs)
            val code = conn.responseCode
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            if (code !in 200..299) {
                return TrafficSample(false, "HTTP $code")
            }
            val json = JSONObject(body)
            val up = json.optLong("uploadTotal", 0)
            val down = json.optLong("downloadTotal", 0)
            TrafficSample(
                live = true,
                message = "Σ ↑ ${formatBytes(up)}  ↓ ${formatBytes(down)}",
                uploadTotal = up,
                downloadTotal = down,
            )
        } catch (error: Exception) {
            TrafficSample(false, "traffic unavailable: ${error.message}")
        }
    }

    private fun open(url: String, secret: String, timeoutMs: Int): HttpURLConnection {
        val conn = (URL(url).openConnection() as HttpURLConnection)
        conn.connectTimeout = timeoutMs
        conn.readTimeout = timeoutMs
        conn.requestMethod = "GET"
        if (secret.isNotBlank()) {
            conn.setRequestProperty("Authorization", "Bearer $secret")
        }
        return conn
    }

    fun formatBytes(bytes: Long): String {
        if (bytes < 1024) return "$bytes B"
        val units = arrayOf("KB", "MB", "GB", "TB")
        var value = bytes.toDouble()
        var unit = -1
        while (value >= 1024 && unit < units.lastIndex) {
            value /= 1024
            unit += 1
        }
        return String.format("%.1f %s", value, units[unit])
    }

    fun sleepQuietly(ms: Long) {
        try {
            TimeUnit.MILLISECONDS.sleep(ms)
        } catch (_: InterruptedException) {
        }
    }
}
