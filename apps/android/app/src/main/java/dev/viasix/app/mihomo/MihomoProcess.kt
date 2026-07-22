package dev.viasix.app.mihomo

import android.util.Log
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Supervises a single user-space mihomo process.
 */
class MihomoProcess(
    private val binary: File,
    private val workDir: File,
) {
    private val processRef = AtomicReference<Process?>(null)

    val isRunning: Boolean
        get() = processRef.get()?.isAlive == true

    @Synchronized
    fun start(configYaml: String) {
        stop()
        if (!workDir.exists() && !workDir.mkdirs()) {
            throw IOException("Cannot create work dir ${workDir.absolutePath}")
        }
        val configFile = File(workDir, "config.yaml")
        configFile.writeText(configYaml)

        val builder =
            ProcessBuilder(
                binary.absolutePath,
                "-d",
                workDir.absolutePath,
                "-f",
                configFile.absolutePath,
            )
                .directory(workDir)
                .redirectErrorStream(true)

        val process =
            try {
                builder.start()
            } catch (error: Exception) {
                throw IOException("Failed to start mihomo: ${error.message}", error)
            }
        processRef.set(process)

        // Drain stdout on a side thread so the pipe never blocks the core.
        Thread(
            {
                try {
                    process.inputStream.bufferedReader().useLines { lines ->
                        lines.forEach { line ->
                            if (line.isNotBlank()) Log.i(TAG, line)
                        }
                    }
                } catch (_: Exception) {
                }
            },
            "mihomo-log",
        ).apply {
            isDaemon = true
            start()
        }

        // Brief settle: if process dies immediately, surface failure.
        try {
            Thread.sleep(300)
        } catch (_: InterruptedException) {
        }
        if (!process.isAlive) {
            processRef.set(null)
            throw IOException("mihomo exited immediately after start")
        }
        Log.i(TAG, "mihomo started")
    }

    @Synchronized
    fun stop() {
        val process = processRef.getAndSet(null) ?: return
        try {
            process.destroy()
            if (!process.waitFor(3, TimeUnit.SECONDS)) {
                process.destroyForcibly()
                process.waitFor(2, TimeUnit.SECONDS)
            }
        } catch (error: Exception) {
            Log.w(TAG, "stop mihomo: ${error.message}")
        }
        Log.i(TAG, "mihomo stopped")
    }

    companion object {
        private const val TAG = "MihomoProcess"
    }
}
