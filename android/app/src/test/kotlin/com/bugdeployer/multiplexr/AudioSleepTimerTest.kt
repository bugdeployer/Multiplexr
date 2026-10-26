package com.bugdeployer.multiplexr

import org.junit.Assert.*
import org.junit.Test

class AudioSleepTimerTest {
    @Test fun deadlineExpiresUsingElapsedTimeDespiteWallClockChanges() {
        val timer = AudioSleepTimer()
        timer.set(5, 1000000, 2000)
        assertEquals(1300000L, timer.deadlineUtcMs)
        assertFalse(timer.expired(301999))
        assertTrue(timer.expired(302000))
        assertTrue(timer.expired(900000))
    }
    @Test fun chapterTimerPausesExactlyOneBoundaryAndReplacementCancelsPreviousMode() {
        val timer = AudioSleepTimer()
        timer.set(5, 1000, 1000)
        timer.set(-1, 2000, 2000)
        assertFalse(timer.expired(999999))
        assertTrue(timer.chapterEnded())
        assertFalse(timer.chapterEnded())
        assertEquals(0L, timer.deadlineUtcMs)
        timer.set(-1, 0, 0)
        timer.set(15, 0, 0)
        assertFalse(timer.endOfChapter)
        timer.clear()
        assertFalse(timer.expired(9999999))
    }
    @Test fun invalidDurationsCannotSilentlyBecomeAlwaysOnTimers() {
        for (minutes in listOf(-2L, 181L, Long.MAX_VALUE)) {
            try { AudioSleepTimer().set(minutes, 0, 0); fail() } catch (_: IllegalArgumentException) {}
        }
    }
}
