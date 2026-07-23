package dev.viasix.app.session

/** Runs at most one worker while retaining only the newest request it has not taken yet. */
internal class LatestRequestGate<T : Any> {
    private val monitor = Any()
    private var workerActive = false
    private var pending: T? = null

    /** Returns true only when the caller must launch the single worker. */
    fun submit(request: T): Boolean =
        synchronized(monitor) {
            pending = request
            if (workerActive) {
                false
            } else {
                workerActive = true
                true
            }
        }

    /** Takes the latest request, or retires the worker atomically when none remains. */
    fun takeNext(): T? =
        synchronized(monitor) {
            pending?.also { pending = null }
                ?: run {
                    workerActive = false
                    null
                }
        }

    fun cancelPending() {
        synchronized(monitor) {
            pending = null
        }
    }
}
