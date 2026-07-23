package dev.viasix.app.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GenerationGateTest {
    @Test
    fun newerGenerationCannotBeConfusedWithEarlierWork() {
        val gate = GenerationGate()
        val first = gate.next()
        val second = gate.next()

        assertFalse(gate.isCurrent(first))
        assertTrue(gate.isCurrent(second))
        assertFalse(gate.claim(first))
    }

    @Test
    fun invalidatePermanentlyRetiresCurrentGeneration() {
        val gate = GenerationGate()
        val generation = gate.next()

        gate.invalidate()

        assertFalse(gate.isCurrent(generation))
        assertFalse(gate.claim(generation))
    }

    @Test
    fun terminalActionCanOnlyBeClaimedOnce() {
        val gate = GenerationGate()
        val generation = gate.next()

        assertTrue(gate.claim(generation))
        assertFalse(gate.isCurrent(generation))
        assertFalse(gate.claim(generation))
    }
}
