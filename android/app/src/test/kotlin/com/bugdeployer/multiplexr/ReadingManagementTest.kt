package com.bugdeployer.multiplexr

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ReadingManagementTest {
    private fun fixture(): JSONObject = generateSequence(File(".").canonicalFile) { it.parentFile }.map { File(it, "test/fixtures/reading-management-v1.json") }.first { it.isFile }.let { JSONObject(it.readText()) }
    private fun request(f: JSONObject): JSONObject = JSONObject().put("expectedCatalog", JSONObject(f.getJSONObject("catalog").toString())).put("expectedIndex", JSONObject(f.getJSONObject("index").toString()))
        .put("expectedManagement", JSONObject(f.getJSONObject("management").toString())).put("catalog", JSONObject(f.getJSONObject("catalog").toString())).put("index", JSONObject(f.getJSONObject("index").toString()))
        .put("management", JSONObject(f.getJSONObject("management").toString()))
    @Test fun sharedManagementWireCasesMatchDart() {
        val f = fixture(); val cases = f.getJSONArray("cases")
        for (i in 0 until cases.length()) {
            val case = cases.getJSONObject(i); val value = JSONObject(f.getJSONObject("management").toString()); val path = case.getJSONArray("path")
            var target: Any = value
            for (j in 0 until path.length() - 1) target = when (val t = target) { is JSONObject -> t.get(path.getString(j)); is JSONArray -> t.get(path.getInt(j)); else -> error("path") }
            when (val t = target) { is JSONObject -> t.put(path.getString(path.length() - 1), case.get("value")); is JSONArray -> t.put(path.getInt(path.length() - 1), case.get("value")) }
            assertEquals(case.getString("name"), case.getBoolean("valid"), runCatching { ReadingManagementCodec.validate(value, f.getJSONObject("catalog")) }.isSuccess)
        }
    }
    @Test fun managementCommitRequiresAllSnapshotsAndExactOwnerIsolation() {
        val f = fixture(); val catalog = f.getJSONObject("catalog"); val index = f.getJSONObject("index"); val managed = f.getJSONObject("management")
        val valid = request(f); valid.getJSONObject("catalog").getJSONArray("titles").getJSONObject(0).getJSONObject("metadata").put("title", "Reviewed")
        ReadingManagementCodec.checkCommit("books:[]", catalog, index, managed, valid)
        val stale = request(f); stale.getJSONObject("expectedManagement").put("pageNotes", JSONArray())
        assertTrue(runCatching { ReadingManagementCodec.checkCommit("books:[]", catalog, index, managed, stale) }.isFailure)
        val foreign = request(f); foreign.getJSONObject("catalog").getJSONArray("titles").getJSONObject(2).getJSONObject("metadata").put("title", "Wrong owner")
        assertTrue(runCatching { ReadingManagementCodec.checkCommit("books:[]", catalog, index, managed, foreign) }.isFailure)
        val foreignNotes = request(f); foreignNotes.getJSONObject("management").getJSONArray("pageNotes").getJSONObject(0).put("note", "Wrong owner")
        assertTrue(runCatching { ReadingManagementCodec.checkCommit("books:[]", catalog, index, managed, foreignNotes) }.isFailure)
    }
    @Test fun portableBackupIncludesManagedTagsJobsGroupArtworkAndPageNotesAndRejectsLocalArtwork() {
        val f = fixture(); val managed = f.getJSONObject("management")
        val backup = BackupCodec.export(emptyList(), emptyList(), JSONArray(), mapOf(ReadingCatalogCodec.KEY to f.getJSONObject("catalog"), ReadingManagementCodec.KEY to managed))
        assertTrue(ReadingIndexCodec.same(managed, backup.getJSONObject("state").getJSONObject(ReadingManagementCodec.KEY)))
        managed.getJSONArray("entities").getJSONObject(1).put("cover", "reading-cover:" + "a".repeat(64))
        assertTrue(runCatching { BackupCodec.export(emptyList(), emptyList(), JSONArray(), mapOf(ReadingCatalogCodec.KEY to f.getJSONObject("catalog"), ReadingManagementCodec.KEY to managed)) }.isFailure)
        val unsupported = JSONObject(backup.toString()); unsupported.getJSONObject("state").put("reading:management:v2", managed)
        assertTrue(runCatching { BackupCodec.validate(unsupported) }.isFailure)
    }
    @Test fun deletionPrunesOnlyRemovedOwnersAndPreservesStaleRevisionNotes() {
        val f = fixture(); val catalog = f.getJSONObject("catalog"); val managed = f.getJSONObject("management")
        catalog.getJSONArray("titles").getJSONObject(2).getJSONObject("source").put("revision", "changed")
        assertEquals(1, ReadingManagementCodec.retain(managed, catalog).getJSONArray("pageNotes").length())
        val withoutBooks = ReadingCatalogCodec.withoutCollection(catalog, "books:[]")
        val retained = ReadingManagementCodec.retain(managed, withoutBooks)
        assertEquals(1, retained.getJSONArray("pageNotes").length()); assertEquals(0, retained.getJSONArray("jobs").length())
        assertEquals(1, CollectionStatePolicy.withoutCollection(ReadingManagementCodec.KEY, managed, "books")!!.getJSONArray("jobs").length())
        assertEquals(0, CollectionStatePolicy.withoutCollection(ReadingManagementCodec.KEY, managed, "comics")!!.getJSONArray("pageNotes").length())
    }
    @Test fun indexLookupUsedByReadersUsesLiteralIdRatherThanNonexistentTitleId() {
        val f = fixture(); val entries = f.getJSONObject("index").getJSONArray("entries")
        assertEquals("issue", ReadingIndexCodec.entry(entries, "comics", "issue").getString("id"))
        assertEquals("standalone", ReadingIndexCodec.entry(entries, "books:[]", "standalone").getString("id"))
        assertTrue(runCatching { ReadingIndexCodec.entry(entries, "books", "standalone") }.isFailure)
    }
}
