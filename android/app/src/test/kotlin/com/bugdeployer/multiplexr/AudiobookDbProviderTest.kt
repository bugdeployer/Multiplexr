package com.bugdeployer.multiplexr
import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
class AudiobookDbProviderTest {
    @Test fun recordingMetadataStaysSeparateFromWorkIdentity() {
        val book = JSONObject().put("id", "work123").put("title", "Title").put("description", "Description")
            .put("people", JSONArray().put(JSONObject().put("role", JSONObject().put("name", "Author")).put("person", JSONObject().put("name", "Writer"))))
            .put("coverImage", JSONObject().put("url", "https://audiobookdb.org/images/cover"))
        val release = JSONObject().put("id", "edition456").put("title", "Recording").put("language", JSONObject().put("name", "English"))
            .put("people", JSONArray().put(JSONObject().put("role", JSONObject().put("name", "Narrator")).put("person", JSONObject().put("name", "Reader"))))
        val data = AudiobookDbProvider.normalize(book, release)
        assertEquals("audiobookdb:work123:edition456", data.getString("providerId"))
        assertEquals("Writer", data.getString("author")); assertEquals("Reader", data.getString("narrator"))
        assertEquals("English", data.getString("language"))
        assertEquals("https://audiobookdb.org/images/cover/large.jpg", data.getString("coverUrl"))
        assertEquals("audiobookdb", data.getString("metadataSource"))
        assertFalse(data.has("seriesId"))
    }
    @Test fun absentRecordingDoesNotInventNarratorOrPublicationDate() {
        val data = AudiobookDbProvider.normalize(JSONObject().put("id", "work").put("title", "Title"), null)
        assertEquals("", data.getString("narrator")); assertEquals("", data.getString("publicationDate")); assertEquals("", data.getString("coverUrl"))
    }
}
