package com.bugdeployer.multiplexr

import org.junit.Assert.*
import org.junit.Test

class PlaybackLifetimeTest {
    @Test fun activePublicBackgroundSessionSurvivesTaskRemoval() {
        assertTrue(PlaybackLifetime.keepAfterTaskRemoval(true, false, true, true, false))
        assertFalse(PlaybackLifetime.keepAfterTaskRemoval(false, false, true, true, false))
        assertFalse(PlaybackLifetime.keepAfterTaskRemoval(true, true, true, true, false))
        assertFalse(PlaybackLifetime.keepAfterTaskRemoval(true, false, false, true, false))
        assertFalse(PlaybackLifetime.keepAfterTaskRemoval(true, false, true, false, false))
        assertFalse(PlaybackLifetime.keepAfterTaskRemoval(true, false, true, true, true))
    }
    @Test fun viewDisposalCannotReleaseTheServicesPlayer() {
        assertFalse(PlaybackLifetime.release(0, true, true))
        assertFalse(PlaybackLifetime.release(0, false, true))
        assertFalse(PlaybackLifetime.release(1, false, false))
        assertTrue(PlaybackLifetime.release(0, false, false))
    }
    @Test fun reattachmentRequiresCollectionAndAssetOwnershipAsWellAsUri() {
        assertTrue(PlaybackLifetime.reuse(true, "a", "x", "a", "x", "content://clip", "content://clip"))
        assertFalse(PlaybackLifetime.reuse(true, "a", "x", "b", "x", "content://clip", "content://clip"))
        assertFalse(PlaybackLifetime.reuse(true, "a", "x", "a", "y", "content://clip", "content://clip"))
        assertFalse(PlaybackLifetime.reuse(false, "a", "x", "a", "x", "content://clip", "content://clip"))
    }
}
