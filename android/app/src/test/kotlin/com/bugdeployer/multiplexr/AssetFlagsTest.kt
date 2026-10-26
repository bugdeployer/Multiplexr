package com.bugdeployer.multiplexr
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
class AssetFlagsTest {
    @Test fun personalFlagsDoNotChangeHistoryOrMetadata() {
        val asset=JSONObject().put("positionMs",5000).put("providerId",10).put("metadataSource","tmdb")
        AssetFlags.apply(asset,"favorite",true);AssetFlags.apply(asset,"watchLater",true)
        assertTrue(asset.getBoolean("favorite"));assertTrue(asset.getBoolean("watchLater"));assertEquals(5000,asset.getInt("positionMs"));assertEquals(10,asset.getInt("providerId"))
    }
    @Test fun clearOnlineMatchPreservesWatchHistoryAndSkipsManualEdits() {
        val asset=JSONObject().put("positionMs",5000).put("providerId",10).put("seriesId",10).put("episodeId",11).put("metadataSource","tmdb").put("favorite",true)
        assertTrue(AssetFlags.apply(asset,"clearMatches",false));assertFalse(asset.has("providerId"));assertFalse(asset.has("seriesId"));assertEquals(5000,asset.getInt("positionMs"));assertTrue(asset.getBoolean("favorite"))
        val manual=JSONObject().put("metadataSource","manual").put("providerId",12)
        assertFalse(AssetFlags.apply(manual,"clearMatches",false));assertEquals(12,manual.getInt("providerId"))
    }
    @Test fun bulkWatchedAndUnwatchedUpdateCompletionConsistently() {
        val asset=JSONObject().put("positionMs",5000).put("hiddenFromContinue",true)
        AssetFlags.apply(asset,"watched",true);assertTrue(asset.getBoolean("watched"));assertTrue(asset.getLong("completedAt")>0);assertEquals(0,asset.getInt("positionMs"))
        AssetFlags.apply(asset,"watched",false);assertFalse(asset.getBoolean("watched"));assertEquals(0L,asset.getLong("completedAt"));assertFalse(asset.getBoolean("hiddenFromContinue"))
    }
}
