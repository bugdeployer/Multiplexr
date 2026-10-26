package com.bugdeployer.multiplexr
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AudiobookAutoplayTest {
    private fun book(id: String, title: String = id, series: String = "Saga", order: Double = 0.0, collection: String = "local") = JSONObject()
        .put("id", JSONObject().put("kind", "audiobook").put("collectionId", collection).put("itemId", id))
        .put("metadata", JSONObject().put("title", title).put("series", series).put("seriesOrder", order))
        .put("files", JSONArray().put(JSONObject().put("id", "file").put("uri", "content://audio/file")))
        .put("chapters", JSONArray().put(JSONObject().put("id", "chapter1").put("fileId", "file").put("title", "First").put("startMs", 0).put("endMs", 1000))
            .put(JSONObject().put("id", "chapter2").put("fileId", "file").put("title", "Second").put("startMs", 1000).put("endMs", 2000)))
    @Test fun naturalOrderDoesNotCrossCollectionsOrSeriesOrLoop() {
        val a = book("2", "Book 2"); val b = book("10", "Book 10")
        val all = JSONArray(listOf(b, book("3", collection = "other"), book("4", series = "Other saga"), a))
        assertSame(b, AudiobookAutoplay.next(all, a.getJSONObject("id")))
        assertNull(AudiobookAutoplay.next(all, b.getJSONObject("id")))
    }
    @Test fun explicitSeriesOrderWinsAndStandaloneTitlesDoNotChain() {
        val a = book("10", order = 1.0); val b = book("2", order = 2.0); val unknown = book("1")
        assertSame(b, AudiobookAutoplay.next(JSONArray(listOf(unknown, b, a)), a.getJSONObject("id")))
        assertSame(unknown, AudiobookAutoplay.next(JSONArray(listOf(unknown, b, a)), b.getJSONObject("id")))
        val standalone = book("single", series = "")
        assertNull(AudiobookAutoplay.next(JSONArray(listOf(standalone, book("another", series = ""))), standalone.getJSONObject("id")))
    }
    @Test fun compiledAudioRetainsChapterClipsAndDistinctTitleIdentity() {
        val b = book("next")
        val request = AudiobookAutoplay.request(b)
        assertEquals("next", request.getJSONObject("id").getString("itemId"))
        assertEquals(2, request.getJSONArray("files").length())
        assertEquals(1000L, request.getJSONArray("files").getJSONObject(1).getLong("startMs"))
        assertEquals("content://audio/file", request.getJSONArray("files").getJSONObject(1).getString("uri"))
    }
    @Test fun nextTitleResumesItsOwnUnfinishedProgressButNeverAnotherCollections() {
        val b = book("next")
        val progress = JSONObject().put("id", b.getJSONObject("id")).put("chapterId", "chapter2").put("positionMs", 500).put("finished", false)
        val request = AudiobookAutoplay.request(b, progress)
        assertEquals(1, request.getInt("index")); assertEquals(500L, request.getLong("positionMs"))
        progress.put("finished", true)
        assertEquals(0, AudiobookAutoplay.request(b, progress).getInt("index"))
        progress.put("finished", false).put("id", book("next", collection = "other").getJSONObject("id"))
        assertEquals(0, AudiobookAutoplay.request(b, progress).getInt("index"))
    }
}
