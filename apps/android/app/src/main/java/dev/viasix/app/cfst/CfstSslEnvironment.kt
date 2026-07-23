package dev.viasix.app.cfst

import android.content.Context
import android.util.Log
import java.io.File

/**
 * Supplies Android system CA material to the CFST (Go) process.
 *
 * The stock CFST binary uses Go's crypto/x509, which does **not** load Android's
 * Conscrypt trust store. Without [SSL_CERT_DIR] / [SSL_CERT_FILE], HTTPing fails
 * with `x509: certificate signed by unknown authority`.
 *
 * App UIDs often see an incomplete view of `/system/etc/security/cacerts` (only a
 * handful of entries) while `/apex/com.android.conscrypt/cacerts` remains complete.
 * Prefer the apex store, and when possible materialize a PEM bundle for
 * `SSL_CERT_FILE` which Go loads more reliably than hash-named DIR trees.
 */
object CfstSslEnvironment {
    private const val TAG = "CfstSsl"
    private const val PEM_NAME = "android-cacerts.pem"

    /** Prefer complete Conscrypt apex; system path is often filtered for app UIDs. */
    val certDirCandidates: List<String> =
        listOf(
            "/apex/com.android.conscrypt/cacerts",
            "/system/etc/security/cacerts",
        )

    fun resolveCertDir(
        existsUsable: (String) -> Boolean = ::isUsableCertDir,
    ): String? = certDirCandidates.firstOrNull(existsUsable)

    fun isUsableCertDir(path: String): Boolean {
        val dir = File(path)
        if (!dir.isDirectory) return false
        val count = dir.list()?.size ?: 0
        // Incomplete filtered mounts can expose only a few files — skip those.
        return count >= 16
    }

    /**
     * Build or refresh a PEM bundle under the app files dir from the best system
     * cert directory. Returns the PEM file when non-empty.
     */
    fun ensurePemBundle(context: Context, certDir: String? = resolveCertDir()): File? {
        val dirPath = certDir ?: return null
        val dir = File(dirPath)
        val out = File(File(context.filesDir, "cfst"), PEM_NAME)
        return try {
            if (!out.parentFile!!.exists() && !out.parentFile!!.mkdirs()) {
                return null
            }
            val sources =
                dir.listFiles()
                    ?.filter { it.isFile && it.canRead() && it.length() > 0L }
                    ?.sortedBy { it.name }
                    .orEmpty()
            if (sources.size < 16) {
                Log.w(TAG, "cert dir $dirPath only has ${sources.size} files; skip PEM")
                return if (out.isFile && out.length() > 10_000L) out else null
            }
            // Refresh when missing or suspiciously small vs source count.
            val needsRefresh =
                !out.isFile ||
                    out.length() < 50_000L ||
                    out.lastModified() + 7L * 24 * 60 * 60 * 1000 < System.currentTimeMillis()
            if (needsRefresh) {
                out.outputStream().buffered().use { sink ->
                    for (src in sources) {
                        src.inputStream().use { input -> input.copyTo(sink) }
                        sink.write('\n'.code)
                    }
                }
                Log.i(TAG, "wrote PEM bundle ${out.absolutePath} from ${sources.size} certs in $dirPath")
            }
            out.takeIf { it.isFile && it.length() > 10_000L }
        } catch (error: Exception) {
            Log.w(TAG, "ensurePemBundle: ${error.message}")
            null
        }
    }

    /**
     * Mutates a [ProcessBuilder] environment so Go CFST can verify TLS for HTTPing.
     * Does not override existing non-blank `SSL_CERT_*` values.
     */
    fun applyTo(
        environment: MutableMap<String, String>,
        certDir: String? = resolveCertDir(),
        pemFile: File? = null,
    ) {
        if (pemFile != null && pemFile.isFile && environment["SSL_CERT_FILE"].isNullOrBlank()) {
            environment["SSL_CERT_FILE"] = pemFile.absolutePath
        }
        if (!certDir.isNullOrBlank() && environment["SSL_CERT_DIR"].isNullOrBlank()) {
            environment["SSL_CERT_DIR"] = certDir
        }
    }

    fun applyForContext(
        context: Context,
        environment: MutableMap<String, String>,
    ) {
        val dir = resolveCertDir()
        val pem = ensurePemBundle(context, dir)
        applyTo(environment, certDir = dir, pemFile = pem)
        Log.i(
            TAG,
            "CFST SSL env CERT_DIR=${environment["SSL_CERT_DIR"]} CERT_FILE=${environment["SSL_CERT_FILE"]}",
        )
    }
}
