package dev.viasix.core.speedtest

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class CfstOutputParserTest {
    @Test
    fun parseProgress_readsLastBarOnLine() {
        val text =
            "200 / 16640 [↘_____] 可用: 0  400 / 16640 [-↖____] 可用: 0"
        val p = CfstOutputParser.parseProgress(text)
        assertEquals(400, p!!.current)
        assertEquals(16640, p.total)
        assertEquals(2, p.percent)
    }

    @Test
    fun parseProgress_ignoresNonProgress() {
        assertNull(CfstOutputParser.parseProgress("开始延迟测速（模式：HTTP）"))
        assertNull(CfstOutputParser.parseProgress(""))
    }

    @Test
    fun stream_emitsOnlyOnChangeAndHandlesCarriageReturns() {
        val stream = CfstOutputParser.Stream()
        assertNull(stream.consume("开始延迟测速\n"))
        assertEquals("延迟测速", stream.lastPhaseHint())

        val first = stream.consume("0 / 100 [___]\r")
        assertEquals(CfstOutputParser.Progress(0, 100), first)

        assertNull(stream.consume("0 / 100 [___]\r")) // same

        val second = stream.consume("50 / 100 [==_]\r")
        assertEquals(CfstOutputParser.Progress(50, 100), second)
        assertEquals(50, second!!.percent)

        stream.consume("开始下载测速（下限：0.00）\n")
        assertEquals("下载测速", stream.lastPhaseHint())

        val msg = second.statusMessage(stream.lastPhaseHint())
        assertTrue(msg.contains("下载测速"))
        assertTrue(msg.contains("50 / 100"))
    }

    @Test
    fun stream_updatesAcrossChunks() {
        val stream = CfstOutputParser.Stream()
        // First emission
        assertEquals(
            CfstOutputParser.Progress(10, 100),
            stream.consume("10 / 100 ["),
        )
        // Same numbers ignored
        assertNull(stream.consume("====]\r10 / 100 [==]\r")
        )
        // Advance
        assertEquals(
            CfstOutputParser.Progress(75, 100),
            stream.consume("75 / 100 [======_]\r"),
        )
    }
}
