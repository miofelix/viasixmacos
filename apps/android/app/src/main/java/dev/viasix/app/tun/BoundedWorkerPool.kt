package dev.viasix.app.tun

import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * A cached-style daemon worker pool with a hard thread ceiling and no hidden task backlog.
 * Blocking network work is rejected immediately once all workers are occupied.
 */
internal class BoundedWorkerPool(
    maxThreads: Int,
    threadNamePrefix: String,
) : AutoCloseable {
    private val threadNumber = AtomicInteger(0)
    private val executor: ThreadPoolExecutor

    init {
        require(maxThreads > 0) { "maxThreads must be positive" }
        require(threadNamePrefix.isNotBlank()) { "threadNamePrefix must not be blank" }
        executor =
            ThreadPoolExecutor(
                0,
                maxThreads,
                IDLE_TIMEOUT_SECONDS,
                TimeUnit.SECONDS,
                SynchronousQueue(),
                { runnable ->
                    Thread(
                        runnable,
                        "$threadNamePrefix-${threadNumber.incrementAndGet()}",
                    ).apply { isDaemon = true }
                },
                ThreadPoolExecutor.AbortPolicy(),
            )
    }

    /** Returns false instead of running blocking work on the submitting thread. */
    fun execute(task: () -> Unit): Boolean =
        try {
            executor.execute(task)
            true
        } catch (_: RejectedExecutionException) {
            false
        }

    val largestPoolSize: Int
        get() = executor.largestPoolSize

    override fun close() {
        executor.shutdownNow()
        try {
            if (!executor.awaitTermination(CLOSE_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                executor.shutdownNow()
            }
        } catch (_: InterruptedException) {
            executor.shutdownNow()
            Thread.currentThread().interrupt()
        }
    }

    private companion object {
        const val IDLE_TIMEOUT_SECONDS = 30L
        const val CLOSE_TIMEOUT_MS = 2_000L
    }
}
