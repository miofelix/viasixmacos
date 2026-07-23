package dev.viasix.core.speedtest

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class NodeResultSortingTest {
    @Test
    fun latencyAscendingPutsLowestFirstAndMissingLast() {
        val rows =
            listOf(
                row("a", latency = "100"),
                row("b", latency = "9"),
                row("c", latency = "—"),
                row("d", latency = "45.8"),
            )
        val sorted = NodeResultSorting.sorted(rows, NodeSortKey.LATENCY, ascending = true)
        assertEquals(listOf("b", "d", "a", "c"), sorted.map { it.ip })
    }

    @Test
    fun speedDescendingPutsFastestFirstMissingLast() {
        val rows =
            listOf(
                row("a", speed = "9.5"),
                row("b", speed = "12"),
                row("c", speed = ""),
            )
        val sorted = NodeResultSorting.sorted(rows, NodeSortKey.SPEED, ascending = false)
        assertEquals(listOf("b", "a", "c"), sorted.map { it.ip })
    }

    @Test
    fun lossAscending() {
        val rows =
            listOf(
                row("a", loss = "0.25"),
                row("b", loss = "0.05"),
                row("c", loss = "1.0"),
            )
        val sorted = NodeResultSorting.sorted(rows, NodeSortKey.LOSS, ascending = true)
        assertEquals(listOf("b", "a", "c"), sorted.map { it.ip })
    }

    @Test
    fun equalValuesPreserveSourceOrder() {
        val rows =
            listOf(
                row("30", latency = "15"),
                row("10", latency = "15"),
                row("20", latency = "15"),
            )
        val sorted = NodeResultSorting.sorted(rows, NodeSortKey.LATENCY)
        assertEquals(listOf("30", "10", "20"), sorted.map { it.ip })
    }

    @Test
    fun emptyAndSingleUnchanged() {
        assertTrue(NodeResultSorting.sorted(emptyList(), NodeSortKey.LATENCY).isEmpty())
        val one = listOf(row("only"))
        assertEquals(one, NodeResultSorting.sorted(one, NodeSortKey.SPEED))
    }

    @Test
    fun parseMetricNumberStripsUnits() {
        assertEquals(12.3, NodeResultSorting.parseMetricNumber("12.3 ms"))
        assertEquals(1.2, NodeResultSorting.parseMetricNumber("1.2 MB/s"))
        assertEquals(0.0, NodeResultSorting.parseMetricNumber("0.00%"))
        assertNull(NodeResultSorting.parseMetricNumber("—"))
        assertNull(NodeResultSorting.parseMetricNumber(""))
    }

    @Test
    fun regionMissingLast() {
        val rows =
            listOf(
                row("a", region = "HKG"),
                row("b", region = ""),
                row("c", region = "NRT"),
            )
        val sorted = NodeResultSorting.sorted(rows, NodeSortKey.REGION, ascending = true)
        assertEquals(listOf("a", "c", "b"), sorted.map { it.ip })
    }

    private fun row(
        ip: String,
        sent: String = "4",
        received: String = "4",
        loss: String = "0",
        latency: String = "1",
        speed: String = "1",
        region: String = "",
    ) = SpeedTestResult(
        ip = ip,
        sent = sent,
        received = received,
        loss = loss,
        latency = latency,
        speed = speed,
        region = region,
    )
}
