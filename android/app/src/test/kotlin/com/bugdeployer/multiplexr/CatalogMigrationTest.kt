package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CatalogMigrationTest {
    private class Store : CatalogMigrationStore {
        var rows = linkedMapOf<String, JSONObject>()
        var values = linkedMapOf<String, JSONObject>()
        var writes = 0; var failAt: Int? = null; var transactions = 0; var failTransaction: Int? = null
        var legacy: JSONObject? = null
        override fun legacyVideoQueue() = legacy
        private fun copy(input: Map<String, JSONObject>) = input.mapValues { JSONObject(it.value.toString()) }.toMutableMap()
        private fun write() { writes++; if (writes == failAt) error("Disk full") }
        override fun readState(key: String) = values[key]?.let { JSONObject(it.toString()) }
        override fun collections() = rows.values.map { JSONObject(it.toString()) }
        override fun states() = copy(values)
        override fun putCollection(value: JSONObject) { write(); rows[value.getString("id")] = JSONObject(value.toString()) }
        override fun putState(key: String, value: JSONObject) { write(); values[key] = JSONObject(value.toString()) }
        override fun deleteState(key: String) { write(); values.remove(key) }
        override fun transaction(action: () -> Unit) {
            transactions++
            if (transactions == failTransaction) error("Process stopped before activation")
            val oldRows = copy(rows); val oldValues = copy(values)
            try { action() } catch (failure: Throwable) {
                rows = LinkedHashMap(oldRows); values = LinkedHashMap(oldValues); throw failure
            }
        }
    }
    private val canonical = "progress:[\"audiobook\",\"c\",\"folder:Books/One\"]"
    private val alias = canonical.replace("/", "\\/")
    private fun legacy() = JSONObject().put("id","c").put("type","audiobook").put("subtype","videos")
        .put("name","Private").put("locked",true).put("includeInGlobalAudio",false).put("roots",JSONArray().put("root-grant"))
    private fun progress(value: Int) = JSONObject().put("positionMs",value).put("chapterId","part")
    private fun store() = Store().apply { rows["c"] = legacy(); values[alias] = progress(1234) }

    @Test fun retryAfterInterruptedActivationPreservesIdentityAndHistory() {
        val store = store(); store.failTransaction = 2
        try { CatalogMigration.ensure(store); fail() } catch (_: IllegalStateException) {}
        assertEquals("prepared",store.values.getValue(CatalogMigration.KEY).getString("status"))
        assertEquals("audiobook",store.rows.getValue("c").getString("type"))
        // A queued background save after preparation must not be overwritten by a stale plan.
        store.values[alias] = progress(5678); store.failTransaction = null
        CatalogMigration.ensure(store)
        assertEquals(5678,store.values.getValue(canonical).getInt("positionMs"))
        assertFalse(store.values.containsKey(alias))
        assertTrue(store.rows.getValue("c").getBoolean("locked"))
        assertFalse(store.rows.getValue("c").getBoolean("includeInGlobalAudio"))
        assertEquals("audio",store.rows.getValue("c").getString("type"))
        assertEquals("root-grant",store.rows.getValue("c").getJSONArray("roots").getString(0))
        val before = store.values.getValue(CatalogMigration.KEY).getJSONObject("before")
        assertEquals(5678,before.getJSONObject("state").getJSONObject(alias).getInt("positionMs"))
        val writes = store.writes; CatalogMigration.ensure(store); assertEquals(writes,store.writes)
    }
    @Test fun failedWriteRollsBackEveryCatalogChangeAndCanRetry() {
        val store = store(); store.failAt = 3
        try { CatalogMigration.ensure(store); fail() } catch (_: IllegalStateException) {}
        assertEquals("audiobook",store.rows.getValue("c").getString("type"))
        assertTrue(store.values.containsKey(alias)); assertFalse(store.values.containsKey(canonical))
        assertEquals("prepared",store.values.getValue(CatalogMigration.KEY).getString("status"))
        store.failAt = null; CatalogMigration.ensure(store)
        assertEquals("complete",store.values.getValue(CatalogMigration.KEY).getString("status"))
        assertEquals(1234,store.values.getValue(canonical).getInt("positionMs"))
    }
    @Test fun failedPreparationLeavesNoJournalOrChanges() {
        val store = store(); store.failAt = 1
        try { CatalogMigration.ensure(store); fail() } catch (_: IllegalStateException) {}
        assertFalse(store.values.containsKey(CatalogMigration.KEY))
        assertTrue(store.values.containsKey(alias)); assertEquals("audiobook",store.rows.getValue("c").getString("type"))
    }
    @Test fun conflictingAliasNeverReplacesTheCurrentlyVisibleCanonicalValue() {
        val store = store(); store.values[canonical] = progress(999)
        CatalogMigration.ensure(store)
        assertEquals(999,store.values.getValue(canonical).getInt("positionMs"))
        val journal = store.values.getValue(CatalogMigration.KEY)
        assertEquals(canonical,journal.getJSONArray("conflicts").getString(0))
        assertEquals(1234,journal.getJSONObject("before").getJSONObject("state").getJSONObject(alias).getInt("positionMs"))
    }
    @Test fun missingLegacyOwnerIsMaterializedOnceWithoutChangingBookOrChapterIdentity() {
        val catalog = JSONObject("""{"version":1,"books":[{"id":{"kind":"audiobook","collectionId":"orphan","itemId":"book"},"metadata":{"title":"Book","seriesId":"s"},"files":[{"id":"file","uri":"content://source","filename":"Part.mp3"}]}]}""")
        val store = Store(); store.values["audio:library"] = catalog
        CatalogMigration.ensure(store); CatalogMigration.ensure(store)
        assertEquals(setOf("orphan"),store.rows.keys)
        assertEquals(catalog.toString(),store.values.getValue("audio:library").toString())
    }
    @Test fun legacyQueueBecomesSQLiteAuthorityWithoutOverwritingAnExistingQueue() {
        val store = store(); store.legacy = JSONObject().put("items",JSONArray().put("[\"c\",\"one\"]"))
        CatalogMigration.ensure(store)
        assertEquals("[\"c\",\"one\"]",store.values.getValue("legacyVideoQueue").getJSONArray("items").getString(0))
        store.legacy = JSONObject().put("items",JSONArray()); CatalogMigration.ensure(store)
        assertEquals(1,store.values.getValue("legacyVideoQueue").getJSONArray("items").length())
    }
    @Test fun explicitDeletionPurgesRetainedRecoverySnapshotsForThatOwner() {
        val store = store(); CatalogMigration.ensure(store)
        CatalogMigration.forgetState(store,canonical)
        assertFalse(store.values.getValue(CatalogMigration.KEY).getJSONObject("before").getJSONObject("state").has(alias))
        CatalogMigration.forgetCollection(store,"c")
        assertEquals(0,store.values.getValue(CatalogMigration.KEY).getJSONObject("before").getJSONArray("collections").length())
    }
    @Test fun collectionDeletionAlsoScrubsTheMigratedLegacyQueueSnapshot() {
        val store = store(); store.legacy = JSONObject().put("items",JSONArray().put(JSONArray(listOf("c","one")).toString()).put(JSONArray(listOf("other","two")).toString()))
        CatalogMigration.ensure(store); CatalogMigration.forgetCollection(store,"c")
        val retained = store.values.getValue(CatalogMigration.KEY).getJSONObject("before").getJSONObject("legacyQueue").getJSONArray("items")
        assertEquals(1,retained.length()); assertEquals("other",JSONArray(retained.getString(0)).getString(0))
    }
}
