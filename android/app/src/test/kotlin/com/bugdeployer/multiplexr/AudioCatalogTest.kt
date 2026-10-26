package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AudioCatalogTest {
    @Test fun overlappingSourcesInDifferentCollectionsKeepSeparateBookIdentities() {
        val value = catalog()
        val books = value.getJSONArray("books")
        val copy = JSONObject(books.getJSONObject(0).toString())
        copy.getJSONObject("id").put("collectionId", "another-collection")
        books.put(copy)
        assertEquals(2, AudioCatalogCodec.validate(value).getJSONArray("books").length())
    }
    @Test fun audiobookCollectionsAndTheirGlobalPrivacySettingsSurviveBackup() {
        val audio = catalog()
        val collection = JSONObject().put("id", "audiobooks").put("name", "Books").put("type", "audiobook")
            .put("subtype", "videos").put("view", "list").put("player", "internal")
            .put("roots", JSONArray()).put("extensions", JSONArray(listOf("mp3", "m4b")))
            .put("locked", true).put("includeInGlobalAudio", false)
        val backup = BackupCodec.export(listOf(collection), emptyList(), JSONArray(), mapOf("audio:library" to audio))
        val restored = BackupCodec.validate(backup).getJSONArray("collections").getJSONObject(0)
        assertEquals("audiobook", restored.getString("type"))
        assertTrue(restored.getBoolean("locked"))
        assertFalse(restored.getBoolean("includeInGlobalAudio"))
        collection.put("subtype","audiobooks")
        val explicit = BackupCodec.export(listOf(collection), emptyList(), JSONArray(), mapOf("audio:library" to audio))
        assertEquals("audiobooks",explicit.getJSONArray("collections").getJSONObject(0).getString("subtype"))
    }
    @Test fun audioPickersCannotConsumeBackupThemeOrSubtitleResults() {
        assertEquals(DocumentRequest.entries.size, DocumentRequest.entries.map { it.code }.toSet().size)
    }
    @Test fun acceptsMultipleChapterRangesInOneSourceAndRejectsOverlaps() {
        val value = catalog()
        val book = value.getJSONArray("books").getJSONObject(0)
        val chapters = JSONArray()
            .put(JSONObject().put("id", "one").put("fileId", "chapter-1").put("title", "One").put("startMs", 0).put("endMs", 10000))
            .put(JSONObject().put("id", "two").put("fileId", "chapter-1").put("title", "Two").put("startMs", 10000).put("endMs", 60000))
        book.put("chapters", chapters)
        assertEquals(2, AudioCatalogCodec.validate(value).getJSONArray("books").getJSONObject(0).getJSONArray("chapters").length())
        chapters.getJSONObject(1).put("startMs", 9000)
        rejected(value)
    }
    @Test fun audiobookCoversSeriesTagsAndReorderedRangesSurviveBackup() {
        val audio = catalog(); val book = audio.getJSONArray("books").getJSONObject(0)
        book.getJSONObject("metadata").put("cover", "data:image/jpeg;base64,aGVsbG8=").put("coverSource", "manual")
            .put("series", "Saga").put("seriesId", "saga").put("seriesOrder", 1.5).put("tags", JSONArray(listOf("Fiction")))
        fun chapter(id: String, start: Int, end: Int) = JSONObject().put("id", id).put("fileId", "chapter-1").put("title", id).put("startMs", start).put("endMs", end)
        book.put("chapters", JSONArray().put(chapter("later", 30000, 60000)).put(chapter("first", 0, 30000)))
        val collection = JSONObject().put("id", "audiobooks").put("name", "Books").put("type", "audio").put("subtype", "audiobooks")
            .put("view", "grid").put("player", "internal").put("roots", JSONArray()).put("extensions", JSONArray(listOf("m4b")))
        val spaces = JSONObject().put("cinema", JSONObject().put("source", "pinned").put("hideWatched", true).put("startTab", 2).put("pins", JSONArray().put(JSONArray(listOf("a", "title")).toString())))
        val state = BackupCodec.export(listOf(collection), emptyList(), JSONArray(), mapOf("audio:library" to audio, "spaces:display" to spaces)).getJSONObject("state")
        val restored = state.getJSONObject("audio:library").getJSONArray("books").getJSONObject(0)
        assertEquals("manual", restored.getJSONObject("metadata").getString("coverSource"))
        assertEquals("later", restored.getJSONArray("chapters").getJSONObject(0).getString("id"))
        assertEquals(2, state.getJSONObject("spaces:display").getJSONObject("cinema").getInt("startTab"))
    }
    @Test fun spacePreferencesCannotExportCredentialsOrExtraPins() {
        assertThrows(IllegalArgumentException::class.java) { SpacePreferencesCodec.validate(JSONObject().put("credentials", JSONObject())) }
        val pins = JSONArray(); repeat(4) { pins.put(JSONArray(listOf("a", "$it")).toString()) }
        assertThrows(IllegalArgumentException::class.java) { SpacePreferencesCodec.validate(JSONObject().put("videos", JSONObject().put("pins", pins))) }
    }
    private fun catalog() = JSONObject().put("version", 1).put("books", JSONArray().put(JSONObject()
        .put("id", JSONObject().put("kind", "audiobook").put("collectionId", "audiobooks").put("itemId", "book"))
        .put("metadata", JSONObject().put("title", "Book").put("author", "Author").put("narrator", "Reader"))
        .put("files", JSONArray().put(JSONObject().put("id", "chapter-1").put("uri", "content://chapter")
            .put("filename", "Chapter.mp3").put("durationMs", 60000)))))
    private fun rejected(value: JSONObject) {
        try { AudioCatalogCodec.validate(value); fail("Invalid catalog accepted") } catch (_: IllegalArgumentException) {}
    }
    @Test fun audioCatalogRoundTripsInsideExistingVersionedBackup() {
        val audio = catalog()
        val progressKey = "progress:[\"audiobook\",\"audiobooks\",\"book\"]"
        val progress = JSONObject().put("chapterId", "chapter-1").put("positionMs", 12000)
        val backup = BackupCodec.export(emptyList(), emptyList(), JSONArray(), mapOf("audio:library" to audio, progressKey to progress))
        val restored = BackupCodec.validate(backup).getJSONObject("state")
        assertEquals("Reader", restored.getJSONObject("audio:library").getJSONArray("books").getJSONObject(0).getJSONObject("metadata").getString("narrator"))
        assertEquals(12000, restored.getJSONObject(progressKey).getInt("positionMs"))
        assertEquals(0, backup.getJSONArray("assets").length())
    }
    @Test fun rejectsMusicIdentityInBookCatalog() {
        val value = catalog(); value.getJSONArray("books").getJSONObject(0).getJSONObject("id").put("kind", "music")
        rejected(value)
    }
    @Test fun rejectsMusicFieldsInBookMetadata() {
        val value = catalog(); value.getJSONArray("books").getJSONObject(0).getJSONObject("metadata").put("albumArtist", "Band")
        rejected(value)
    }
    @Test fun rejectsDuplicateChaptersAndNegativeDurations() {
        val value = catalog(); val files = value.getJSONArray("books").getJSONObject(0).getJSONArray("files")
        files.put(JSONObject(files.getJSONObject(0).toString())); rejected(value)
        val negative = catalog(); negative.getJSONArray("books").getJSONObject(0).getJSONArray("files").getJSONObject(0).put("durationMs", -1)
        rejected(negative)
    }
    @Test fun rejectsNonDocumentSourcesAndUnknownVersions() {
        val value = catalog(); value.getJSONArray("books").getJSONObject(0).getJSONArray("files").getJSONObject(0).put("uri", "https://example.com/file")
        rejected(value)
        rejected(catalog().put("version", 2))
    }
    @Test fun arbitraryPrivateFieldsCannotEnterAudioBackups() {
        rejected(catalog().put("credential", "secret"))
        val value = catalog(); value.getJSONArray("books").getJSONObject(0).getJSONArray("files").getJSONObject(0).put("localCache", "/private/cache")
        rejected(value)
    }
}
