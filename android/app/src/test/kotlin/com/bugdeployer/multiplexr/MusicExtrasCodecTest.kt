package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MusicExtrasCodecTest {
    private fun extras() = JSONObject().put("version", 1)
        .put("titles", JSONObject().put("[\"music\",\"c\",\"song\"]", JSONObject().put("favorite", true).put("tags", JSONArray(listOf("Favorites")))))
        .put("albums", JSONObject().put("[\"c\",\"album\"]", JSONObject().put("title", "Album").put("cover", "data:image/png;base64,test")))
        .put("playlists", JSONArray().put(playlist("local", "c")).put(playlist("global", null)))
    private fun playlist(id: String, owner: String?) = JSONObject().put("version", 1).put("id", id).put("name", "Mix")
        .put("collectionId", owner ?: JSONObject.NULL).put("entries", JSONArray().put(JSONObject().put("id", "occurrence").put("collectionId", "c").put("titleId", "song")))
    @Test fun roundTripKeepsArtworkTagsAndScopedPlaylists() {
        val input = extras()
        val result = MusicExtrasCodec.validate(JSONObject(input.toString()))
        assertEquals(input.toString(), result.toString())
        assertEquals(2, result.getJSONArray("playlists").length())
    }
    @Test fun deletionRemovesOwnedStateAndGlobalReferences() {
        val result = MusicExtrasCodec.withoutCollection(extras(), "c")
        assertEquals(0, result.getJSONObject("titles").length())
        assertEquals(0, result.getJSONObject("albums").length())
        val playlists = result.getJSONArray("playlists")
        assertEquals(1, playlists.length())
        assertEquals("global", playlists.getJSONObject(0).getString("id"))
        assertEquals(0, playlists.getJSONObject(0).getJSONArray("entries").length())
    }
    @Test fun localPlaylistCannotReferenceAnotherOwner() {
        val value = extras()
        value.getJSONArray("playlists").getJSONObject(0).getJSONArray("entries").getJSONObject(0).put("collectionId", "other")
        assertTrue(runCatching { MusicExtrasCodec.validate(value) }.isFailure)
    }
    @Test fun repeatedTracksNeedDistinctOccurrences() {
        val value = extras()
        val entries = value.getJSONArray("playlists").getJSONObject(0).getJSONArray("entries")
        entries.put(JSONObject(entries.getJSONObject(0).toString()))
        assertTrue(runCatching { MusicExtrasCodec.validate(value) }.isFailure)
        entries.getJSONObject(1).put("id", "second")
        MusicExtrasCodec.validate(value)
    }
    @Test fun referencesCannotOutliveMusicOwnersAtWriteAndRestoreBoundaries() {
        MusicExtrasCodec.validate(extras(), setOf("c"))
        assertTrue(runCatching { MusicExtrasCodec.validate(extras(), setOf("other")) }.isFailure)
    }
    @Test fun backupRetainsMusicExtrasAndRejectsOrphanOwners() {
        val collection = JSONObject().put("id", "c").put("name", "Music").put("type", "audio").put("subtype", "music")
            .put("view", "grid").put("player", "internal").put("roots", JSONArray()).put("extensions", JSONArray(listOf("mp3")))
        val backup = BackupCodec.export(listOf(collection), emptyList(), JSONArray(), mapOf("music:extras" to extras()))
        assertEquals(2, backup.getJSONObject("state").getJSONObject("music:extras").getJSONArray("playlists").length())
        assertTrue(runCatching { BackupCodec.export(emptyList(), emptyList(), JSONArray(), mapOf("music:extras" to extras())) }.isFailure)
    }

}
