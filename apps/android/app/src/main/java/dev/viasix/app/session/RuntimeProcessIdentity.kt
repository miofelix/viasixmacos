package dev.viasix.app.session

import java.util.UUID

/** Unique for the lifetime of the current app process; changes after any process restart. */
object RuntimeProcessIdentity {
    val token: String = UUID.randomUUID().toString()
}
