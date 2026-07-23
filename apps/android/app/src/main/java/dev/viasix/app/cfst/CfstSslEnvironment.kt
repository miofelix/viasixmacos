package dev.viasix.app.cfst

import java.io.File

/**
 * Supplies Android system CA locations to the CFST (Go) process.
 *
 * The stock CFST binary uses Go's crypto/x509, which does **not** load Android's
 * Conscrypt trust store. Without [SSL_CERT_DIR] / [SSL_CERT_FILE], HTTPing fails
 * with `x509: certificate signed by unknown authority` and reports 0 available IPs.
 */
object CfstSslEnvironment {
    /** Ordered candidates; first existing non-empty directory wins. */
    val certDirCandidates: List<String> =
        listOf(
            "/system/etc/security/cacerts",
            "/apex/com.android.conscrypt/cacerts",
        )

    fun resolveCertDir(
        existsNonEmpty: (String) -> Boolean = { path ->
            val dir = File(path)
            dir.isDirectory && (dir.list()?.isNotEmpty() == true)
        },
    ): String? = certDirCandidates.firstOrNull(existsNonEmpty)

    /**
     * Mutates a [ProcessBuilder] environment map so Go CFST can verify TLS for HTTPing.
     * Does not override an existing non-blank `SSL_CERT_FILE` / `SSL_CERT_DIR`.
     */
    fun applyTo(environment: MutableMap<String, String>, certDir: String? = resolveCertDir()) {
        if (certDir.isNullOrBlank()) return
        if (environment["SSL_CERT_DIR"].isNullOrBlank()) {
            environment["SSL_CERT_DIR"] = certDir
        }
        if (environment["SSL_CERT_FILE"].isNullOrBlank()) {
            // Prefer DIR (Android hash-named PEMs). Leave FILE unset unless a caller set it.
        }
    }
}
