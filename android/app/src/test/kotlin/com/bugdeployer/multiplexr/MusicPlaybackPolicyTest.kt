package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MusicPlaybackPolicyTest {
    private fun id(c: String = "c", t: String = "song") = JSONObject().put("kind", "music").put("collectionId", c).put("itemId", t)
    private fun request(local: String = "") = JSONObject().put("id", id()).put("scopeCollectionId", local)
        .put("files", JSONArray().put(JSONObject().put("id", "occurrence").put("owner", id()).put("uri", "content://audio/song")))
    private fun collection(locked: Boolean = false, included: Boolean = true) = JSONObject()
        .put("id", "c").put("type", "audio").put("subtype", "music").put("locked", locked).put("includeInGlobalAudio", included)
    private fun track() = JSONObject().put("id", id()).put("available", true)
        .put("source", JSONObject().put("uri", "content://audio/song"))
    @Test fun accessIsCheckedForEachQueueEntryAndScope() {
        assertTrue(MusicPlaybackPolicy.allowed(request(), 0, collection(), track()))
        assertFalse(MusicPlaybackPolicy.allowed(request(), 0, collection(locked = true), track()))
        assertFalse(MusicPlaybackPolicy.allowed(request(), 0, collection(included = false), track()))
        assertTrue(MusicPlaybackPolicy.allowed(request("c"), 0, collection(locked = true, included = false), track()))
        assertFalse(MusicPlaybackPolicy.allowed(request(), 0, null, track()))
        assertFalse(MusicPlaybackPolicy.allowed(request(), 0, collection(), track().put("available", false)))
        assertFalse(MusicPlaybackPolicy.allowed(request(), 0, collection(), track().apply { getJSONObject("source").put("uri", "content://different") }))
    }
    @Test fun localQueueCannotCrossCollectionsButGlobalQueueCan() {
        val input = request("c")
        input.getJSONArray("files").put(JSONObject().put("id", "second").put("owner", id("other")).put("uri", "content://other"))
        assertTrue(runCatching { MusicPlaybackPolicy.validate(input) }.isFailure)
        input.put("scopeCollectionId", "")
        MusicPlaybackPolicy.validate(input)
        assertEquals("other", MusicPlaybackPolicy.owner(input, 1).getString("collectionId"))
    }
    @Test fun repeatedTracksNeedDifferentOccurrenceIds() {
        val input = request()
        input.getJSONArray("files").put(JSONObject(input.getJSONArray("files").getJSONObject(0).toString()))
        assertTrue(runCatching { MusicPlaybackPolicy.validate(input) }.isFailure)
        input.getJSONArray("files").getJSONObject(1).put("id", "repeat-song")
        MusicPlaybackPolicy.validate(input)
    }
    @Test fun sessionRetainsCanonicalOrderAndShuffleTraversalWithoutSourceCopies() {
        val input = request()
        input.getJSONArray("files").put(JSONObject().put("id", "second").put("owner", id("other", "two")).put("uri", "content://other"))
        input.put("canonicalEntryIds", JSONArray(listOf("second", "occurrence")))
        val saved = MusicSessionCodec.snapshot(input, 0, 123)
        assertEquals("second", saved.getJSONArray("entries").getJSONObject(0).getString("entryId"))
        assertEquals("occurrence", saved.getJSONArray("traversal").getString(0))
        assertFalse(saved.toString().contains("content://"))
        assertEquals(123L, saved.getLong("positionMs"))
        val next = MusicSessionCodec.withoutCollection(saved, "c")!!
        assertEquals("second", next.getString("currentEntryId"))
        assertEquals(0L, next.getLong("positionMs"))
        assertEquals(1, next.getJSONArray("traversal").length())
        assertNull(MusicSessionCodec.withoutCollection(next, "other"))
    }
}
