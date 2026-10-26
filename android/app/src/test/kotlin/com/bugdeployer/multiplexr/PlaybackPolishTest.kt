package com.bugdeployer.multiplexr

import org.junit.Assert.*
import org.junit.Test

class PlaybackPolishTest {
    @Test fun supportedSubtitleTypesAreCaseInsensitive() {
        assertEquals("application/x-subrip", SubtitleFiles.mime("Movie.EN.SRT"))
        assertEquals("text/vtt", SubtitleFiles.mime("captions.vtt"))
        assertEquals("text/x-ssa", SubtitleFiles.mime("styled.ass"))
        assertEquals("text/x-ssa", SubtitleFiles.mime("styled.ssa"))
    }
    @Test fun unsupportedFilesCannotBeAttachedAsSubtitles() {
        for (name in listOf("video.mp4", "caption", "captions.srt.exe", "")) {
            try { SubtitleFiles.mime(name); fail("Accepted $name") }
            catch (_: IllegalArgumentException) {}
        }
    }
    @Test fun playbackFailuresOfferDifferentRecoveryActions() {
        assertTrue(PlaybackFailures.message(2005).contains("scan"))
        assertTrue(PlaybackFailures.message(2006).contains("root folder"))
        assertTrue(PlaybackFailures.message(4005).contains("external player"))
        assertTrue(PlaybackFailures.message(3001).contains("subtitle"))
        assertTrue(PlaybackFailures.message(9999).contains("Retry"))
    }
}
