package dev.viasix.app.cfst

import dev.viasix.core.speedtest.SpeedTestParameters
import dev.viasix.core.speedtest.SpeedTestResultParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.atomic.AtomicReference
import kotlin.io.path.createTempDirectory
import kotlin.concurrent.thread

/**
 * Exercises [CfstRunner] failure paths and success parsing without a real CFST binary.
 * Uses missing binary / empty result file so the shipped entry points run on JVM.
 */
class CfstRunnerOutcomeTest {
    @Test
    fun failsWhenBinaryMissing() {
        val work = createTempDirectory("cfst-work").toFile()
        try {
            val runner = CfstRunner()
            val outcome =
                runner.run(
                    binary = File(work, "no-such-cfst"),
                    workDir = work,
                    parameters = SpeedTestParameters.defaultsForRange("2001:db8::/32"),
                )
            assertTrue(outcome is CfstRunOutcome.Failed)
            assertTrue((outcome as CfstRunOutcome.Failed).message.contains("未找到 CFST"))
            assertFalse(runner.isRunning)
        } finally {
            work.deleteRecursively()
        }
    }

    @Test
    fun failsWhenIpSourceMissing() {
        val work = createTempDirectory("cfst-work").toFile()
        val bin = File(work, "cfst").apply { writeText("x"); setExecutable(true) }
        try {
            val outcome =
                CfstRunner().run(
                    binary = bin,
                    workDir = work,
                    parameters = SpeedTestParameters(),
                )
            assertTrue(outcome is CfstRunOutcome.Failed)
            assertTrue((outcome as CfstRunOutcome.Failed).message.contains("IP"))
        } finally {
            work.deleteRecursively()
        }
    }

    @Test
    fun failsWhenIpFileMissing() {
        val work = createTempDirectory("cfst-work").toFile()
        val bin = File(work, "cfst").apply { writeText("x"); setExecutable(true) }
        try {
            val outcome =
                CfstRunner().run(
                    binary = bin,
                    workDir = work,
                    parameters = SpeedTestParameters.defaultsForFile(File(work, "missing.txt").absolutePath),
                )
            assertTrue(outcome is CfstRunOutcome.Failed)
            assertTrue((outcome as CfstRunOutcome.Failed).message.contains("找不到"))
        } finally {
            work.deleteRecursively()
        }
    }

    @Test
    fun parserIntegrationMatchesRunnerSuccessShape() {
        // Shipped parser path used after CFST exits; fixture mirrors runner's read→parse.
        val csv =
            """
            IP,Sent,Received,Loss,Latency,Speed,Region
            2001:db8::1,4,4,0.00,12.3,15.50,SJC
            """.trimIndent()
        val results = SpeedTestResultParser.parse(csv)
        val success =
            CfstRunOutcome.Success(
                results = results,
                resultCsvPath = "/tmp/result.csv",
                message = "测速完成：${results.size} 个结果",
            )
        assertEquals(1, success.results.size)
        assertEquals("2001:db8::1", success.results[0].ip)
        assertEquals("12.3", success.results[0].latency)
        assertTrue(success.message.contains("1"))
    }

    @Test
    fun runnersShareProcessWideSlotAndCrossInstanceCancellation() {
        val work = createTempDirectory("cfst-global-run").toFile()
        val script =
            File(work, "blocking-cfst").apply {
                writeText(
                    """
                    #!/bin/sh
                    trap 'exit 0' TERM INT
                    while :; do
                      sleep 1
                    done
                    """.trimIndent(),
                )
                setExecutable(true)
            }
        val first = CfstRunner()
        val firstOutcome = AtomicReference<CfstRunOutcome>()
        val worker =
            thread(name = "cfst-runner-test") {
                firstOutcome.set(
                    first.run(
                        binary = script,
                        workDir = work,
                        parameters = SpeedTestParameters.defaultsForRange("2001:db8::/32"),
                    ),
                )
            }
        try {
            val deadline = System.nanoTime() + 2_000_000_000L
            while (!first.isRunning && System.nanoTime() < deadline) {
                Thread.sleep(10)
            }
            assertTrue(first.isRunning)

            val duplicate =
                CfstRunner().run(
                    binary = script,
                    workDir = work,
                    parameters = SpeedTestParameters.defaultsForRange("2001:db8::/32"),
                )
            assertTrue(duplicate is CfstRunOutcome.Failed)
            assertTrue((duplicate as CfstRunOutcome.Failed).message.contains("已有测速任务"))

            assertTrue(CfstRunner().requestCancel())
            worker.join(5_000)
            assertFalse(worker.isAlive)
            assertEquals(CfstRunOutcome.Cancelled, firstOutcome.get())
            assertFalse(first.isRunning)
        } finally {
            CfstRunner().requestCancel()
            worker.join(5_000)
            work.deleteRecursively()
        }
    }

    @Test
    fun activityDestroyRequestsRunnerCancellation() {
        val activity =
            listOf(
                File("src/main/java/dev/viasix/app/MainActivity.kt"),
                File("app/src/main/java/dev/viasix/app/MainActivity.kt"),
            ).firstOrNull { it.isFile } ?: error("MainActivity.kt not found")
        val source = activity.readText()
        val onDestroy =
            source.substringAfter("override fun onDestroy()")
                .substringBefore("private fun currentNotificationPermissionState")

        assertTrue(onDestroy.contains("cfstRunner.requestCancel()"))
        assertTrue(onDestroy.contains("super.onDestroy()"))
    }
}
