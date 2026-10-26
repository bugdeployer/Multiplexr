package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class BrowseStateCodecTest {
    private fun state(collection: String? = "a") = JSONObject().put("routeId", "videos")
        .put("collectionId", collection ?: JSONObject.NULL).put("query", "search")
        .put("sort", "added").put("filter", "0").put("folder", "").put("tag", "").put("layout", "")
        .put("tab", 1).put("scrollOffset", 125.5)
    private fun key(collection: String? = "a") = "ui:browse:" + JSONArray(listOf("videos", collection))
    @Test fun validBrowsingIsLocalAndCleanupUsesExactCollectionIdentity() {
        BrowseStateCodec.validate(key(), state())
        BrowseStateCodec.validate(key(null), state(null))
        assertFalse(CollectionStatePolicy.exportable(key()))
        assertTrue(CollectionStatePolicy.ownedBy(key("a:/quoted"), "a:/quoted"))
        assertFalse(CollectionStatePolicy.ownedBy(key("ab"), "a"))
        assertFalse(CollectionStatePolicy.ownedBy(key(null), "a"))
        assertEquals(key("a/b").replace("\\/", "/"), MediaStateKeys.canonical(key("a/b")))
    }
    @Test fun malformedScopeAndFieldsAreRejected() {
        for (pair in listOf(key() to state().put("tab", "1"), key() to state().put("scrollOffset", -1),
            key() to state().put("query", 7), key() to state("other"),
            key() to state().put("routeId", "collection"), key() to state().put("query", "x".repeat(4097)))) {
            try { BrowseStateCodec.validate(pair.first, pair.second); fail("Accepted invalid browsing state") }
            catch (_: IllegalArgumentException) {} catch (_: org.json.JSONException) {}
        }
    }
    @Test fun stoppedPipCannotBypassLockOrBackgroundPlaybackPreference() {
        assertTrue(PlaybackLifetime.visiblePip(true, false))
        assertFalse(PlaybackLifetime.visiblePip(true, true))
        assertFalse(PlaybackLifetime.visiblePip(false, false))
        assertTrue(PlaybackLifetime.pauseOnDeparture(false, false, PlaybackLifetime.visiblePip(true, true)))
        assertFalse(PlaybackLifetime.pauseOnDeparture(true, false, PlaybackLifetime.visiblePip(true, true)))
    }
    @Test fun appLockDoesNotCancelAllowedPlaybackButPrivateCollectionsRemainRestricted() {
        assertFalse(PlaybackLifetime.pauseOnDeparture(true, false, false))
        assertFalse(PlaybackLifetime.pauseOnDeparture(false, false, true))
        assertTrue(PlaybackLifetime.pauseOnDeparture(false, false, false))
        assertTrue(PlaybackLifetime.pauseOnDeparture(true, true, false))
        assertTrue(PlaybackLifetime.pauseOnDeparture(true, true, true))
    }
}
