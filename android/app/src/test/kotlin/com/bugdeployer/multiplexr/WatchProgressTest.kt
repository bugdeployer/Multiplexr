package com.bugdeployer.multiplexr

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WatchProgressTest {
    @Test fun hidingContinueWatchingSurvivesFurtherSavesUntilReopened() {
        val asset = JSONObject().put("positionMs", 1000).put("hiddenFromContinue", true)
        WatchProgress.apply(asset, 2000, 10000)
        assertTrue(asset.getBoolean("hiddenFromContinue"))
        WatchProgress.start(asset)
        assertFalse(asset.getBoolean("hiddenFromContinue"))
    }
    @Test fun pausedSavesDoNotReorderHistory() {
        val asset = JSONObject().put("positionMs", 2000).put("lastPlayedAt", 123L)
        WatchProgress.apply(asset, 2000, 10000)
        assertEquals(123L, asset.getLong("lastPlayedAt"))
    }
    @Test fun completionIsRecordedAtThresholdAndSurvivesZeroSave() {
        val asset = JSONObject()
        WatchProgress.apply(asset, 9400, 10000)
        assertFalse(asset.optBoolean("watched"))
        WatchProgress.apply(asset, 9500, 10000)
        assertTrue(asset.getBoolean("watched"))
        val completion = asset.getLong("completedAt")
        WatchProgress.apply(asset, 0, 10000)
        assertTrue(asset.getBoolean("watched"))
        assertEquals(completion, asset.getLong("completedAt"))
        assertEquals(10000L, asset.getLong("durationMs"))
    }
    @Test fun scanMergesNewerHistoryWithoutReplacingNewFileFields() {
        val latest = JSONObject().put("positionMs", 9000).put("watched", true).put("lastPlayedAt", 12).put("completedAt", 13).put("hiddenFromContinue", true).put("filename", "old.mp4")
        val scanned = JSONObject().put("filename", "new.mp4").put("positionMs", 1000)
        WatchProgress.copyHistory(latest, scanned)
        assertEquals(9000L, scanned.getLong("positionMs"))
        assertTrue(scanned.getBoolean("watched"))
        assertTrue(scanned.getBoolean("hiddenFromContinue"))
        assertEquals(13L, scanned.getLong("completedAt"))
        assertEquals("new.mp4", scanned.getString("filename"))
    }
}
