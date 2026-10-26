package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MusicCatalogTest {
    private fun track(collection: String = "c", id: String = "t") = JSONObject()
        .put("id", JSONObject().put("kind", "music").put("collectionId", collection).put("itemId", id))
        .put("source", JSONObject().put("id", id).put("uri", "content://audio/$id").put("filename", "$id.mp3"))
        .put("rootId", "root").put("folderId", "folder").put("albumId", JSONObject.NULL)
        .put("metadata", JSONObject().put("title", "Track").put("artist", "Artist").put("album", "Album").put("disc", 1).put("track", 2))
        .put("available", true).put("overrides", JSONObject().put("albumId", JSONObject.NULL))
    private fun catalog(vararg tracks: JSONObject) = JSONObject().put("version", 1).put("tracks", JSONArray(tracks.toList()))
    @Test fun musicCatalogValidatesAndRetainsManualUngrouping() {
        val input = catalog(track())
        assertSame(input, MusicCatalogCodec.validate(input))
        assertTrue(input.getJSONArray("tracks").getJSONObject(0).getJSONObject("overrides").isNull("albumId"))
    }
    @Test fun rejectsDuplicateSourcesWrongKindsAndNegativeNumbers() {
        for (input in listOf(catalog(track(), track()),
            catalog(track().apply { getJSONObject("id").put("kind", "audiobook") }),
            catalog(track().apply { getJSONObject("metadata").put("track", -1) }),
            catalog(track().apply { getJSONObject("overrides").put("author", "Book author") }))) {
            assertTrue(runCatching { MusicCatalogCodec.validate(input) }.isFailure)
        }
    }
    @Test fun deletionRemovesOnlyOneCollectionsMusicAndCatalogIsExportable() {
        val input = catalog(track(), track("other", "second"))
        val next = CollectionStatePolicy.withoutCollection("music:library", input, "c")!!
        assertEquals(1, next.getJSONArray("tracks").length())
        assertEquals("other", next.getJSONArray("tracks").getJSONObject(0).getJSONObject("id").getString("collectionId"))
        assertEquals(2, input.getJSONArray("tracks").length())
        assertTrue(CollectionStatePolicy.exportable("music:library"))
    }
    @Test fun backupPreservesMusicCatalogWithoutChangingExistingFormat() {
        val collection = JSONObject().put("id", "c").put("name", "Music").put("type", "audio").put("subtype", "music")
            .put("view", "grid").put("player", "internal").put("roots", JSONArray()).put("extensions", JSONArray(listOf("mp3")))
        val result = BackupCodec.export(listOf(collection), emptyList(), JSONArray(), mapOf("music:library" to catalog(track())))
        assertEquals(1, result.getInt("version"))
        assertEquals(1, result.getJSONObject("state").getJSONObject("music:library").getJSONArray("tracks").length())
        assertTrue(runCatching { BackupCodec.export(emptyList(), emptyList(), JSONArray(), mapOf("music:library" to catalog(track()))) }.isFailure)
    }
}
