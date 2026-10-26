package com.bugdeployer.multiplexr

import java.io.File
import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class ReadingIndexCodecTest {
    private fun fixture(): JSONObject = generateSequence(File(".").canonicalFile) { it.parentFile }
        .map { File(it, "test/fixtures/reading-index-v1.json") }.first { it.isFile }.let { JSONObject(it.readText()) }
    @Test fun sharedDartNativeIndexFixturesAgree() {
        val fixture = fixture(); val cases = fixture.getJSONArray("cases")
        for (i in 0 until cases.length()) {
            val test = cases.getJSONObject(i); val input = JSONObject(fixture.getJSONObject("index").toString())
            val path = test.getJSONArray("path"); var target: Any = input
            for (j in 0 until path.length() - 1) target = when (val t = target) {
                is JSONObject -> t.get(path.getString(j))
                is JSONArray -> t.get(path.getInt(j))
                else -> error("Bad path")
            }
            when (val t = target) {
                is JSONObject -> t.put(path.getString(path.length() - 1), test.get("value"))
                is JSONArray -> t.put(path.getInt(path.length() - 1), test.get("value"))
            }
            val result = runCatching { ReadingIndexCodec.validate(input, fixture.getJSONObject("catalog")) }
            assertEquals(test.getString("name") + ": " + result.exceptionOrNull(), test.getBoolean("valid"), result.isSuccess)
        }
    }
    @Test fun staleScanAndCrossCollectionChangesAreRejectedBeforeWrites() {
        val f = fixture(); val catalog = f.getJSONObject("catalog"); val index = f.getJSONObject("index")
        ReadingIndexCodec.checkCommit("books:[]", catalog, index, JSONObject(catalog.toString()), JSONObject(index.toString()), catalog, index)
        val changed = JSONObject(catalog.toString()); changed.getJSONArray("collections").getJSONObject(1).put("name", "Changed")
        assertTrue(runCatching { ReadingIndexCodec.checkCommit("books:[]", catalog, index, changed, index, catalog, index) }.exceptionOrNull() is ReadingScanConflict)
        assertTrue(runCatching { ReadingIndexCodec.checkCommit("books:[]", catalog, index, catalog, index, changed, index) }.isFailure)
        val changedIndex = JSONObject(index.toString()); changedIndex.getJSONArray("entries").getJSONObject(2).put("manualCover", true)
        assertTrue(runCatching { ReadingIndexCodec.checkCommit("books:[]", catalog, index, catalog, index, catalog, changedIndex) }.isFailure)
    }
    @Test fun deletionRetainsOnlyExactOwnersAndRestoreRequiresSourceVerification() {
        val f = fixture(); val catalog = f.getJSONObject("catalog"); val index = f.getJSONObject("index"); val original = index.toString()
        val nextCatalog = ReadingCatalogCodec.withoutCollection(catalog, "books:[]")
        val next = ReadingIndexCodec.retain(index, nextCatalog)
        assertEquals(1, next.getJSONArray("entries").length()); assertEquals(original, index.toString())
        assertTrue(ReadingIndexCodec.same(next, CollectionStatePolicy.withoutCollection(ReadingIndexCodec.KEY, index, "books:[]")))
        assertFalse(ReadingIndexCodec.restoredCatalog(catalog).getJSONArray("titles").getJSONObject(0).getJSONObject("source").getBoolean("available"))
        assertFalse(ReadingIndexCodec.restoredIndex(index).getJSONArray("roots").getJSONObject(0).getBoolean("complete"))
        assertTrue(catalog.getJSONArray("titles").getJSONObject(0).getJSONObject("source").getBoolean("available"))
    }
    @Test fun backupKeepsPortableEvidenceAndCoversAndRejectsOrphanOrLocalCoverReferences() {
        val f = fixture(); val catalog = f.getJSONObject("catalog"); val index = f.getJSONObject("index")
        index.getJSONArray("entries").getJSONObject(0).put("cover", "data:image/jpeg;base64,YWJj")
        val state = mapOf(ReadingCatalogCodec.KEY to catalog, ReadingIndexCodec.KEY to index)
        val backup = BackupCodec.export(emptyList(), emptyList(), JSONArray(), state)
        assertTrue(ReadingIndexCodec.same(index, backup.getJSONObject("state").getJSONObject(ReadingIndexCodec.KEY)))
        assertTrue(runCatching { BackupCodec.export(emptyList(), emptyList(), JSONArray(), mapOf(ReadingIndexCodec.KEY to index)) }.isFailure)
        index.getJSONArray("entries").getJSONObject(0).put("cover", "reading-cover:" + "a".repeat(64))
        assertTrue(runCatching { BackupCodec.export(emptyList(), emptyList(), JSONArray(), state) }.isFailure)
    }
}
