package com.bugdeployer.multiplexr

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ReadingCatalogTest {
    private fun json(value: Any?): Any? = when (value) {
        is JSONObject -> value.keys().asSequence().associateWith { json(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { json(value.get(it)) }
        else -> value
    }
    private fun JSONObject.same(other: JSONObject) = json(this) == json(other)
    private fun JSONArray.same(other: JSONArray) = json(this) == json(other)
    private fun fixture(name: String): JSONObject {
        val file = generateSequence(File(".").canonicalFile) { it.parentFile }
            .map { File(it, "test/fixtures/$name") }.first { it.isFile }
        return JSONObject(file.readText())
    }
    private fun base() = fixture("reading-v1.json").getJSONObject("base")
    private fun patch(input: JSONObject, patch: JSONObject) {
        val path = patch.getJSONArray("path")
        var parent: Any = input
        for (i in 0 until path.length() - 1) parent = when (val p = parent) {
            is JSONObject -> p.get(path.getString(i))
            is JSONArray -> p.get(path.getInt(i))
            else -> error("Invalid fixture path")
        }
        val last = path.length() - 1
        if (patch.getString("op") == "remove") when (val p = parent) {
            is JSONObject -> p.remove(path.getString(last))
            is JSONArray -> p.remove(path.getInt(last))
        } else when (val p = parent) {
            is JSONObject -> p.put(path.getString(last), patch.get("value"))
            is JSONArray -> p.put(path.getInt(last), patch.get("value"))
        }
    }
    @Test fun sharedDartNativeWireFixturesAgree() {
        val fixture = fixture("reading-v1.json"); val cases = fixture.getJSONArray("cases")
        for (i in 0 until cases.length()) {
            val test = cases.getJSONObject(i)
            val input = JSONObject(fixture.getJSONObject("base").toString())
            val patches = test.getJSONArray("patches")
            for (j in 0 until patches.length()) patch(input, patches.getJSONObject(j))
            val before = input.toString()
            val result = runCatching { ReadingCatalogCodec.validate(input) }
            assertEquals(test.getString("name") + ": " + result.exceptionOrNull(), test.getBoolean("valid"), result.isSuccess)
            if (result.isSuccess) assertEquals(before, result.getOrThrow().toString())
        }
    }
    @Test fun backupRoundTripRetainsReadingAndLegacyIdentitiesAndRejectsFutureVersions() {
        val old = fixture("batch8-backup-v1.json")
        val legacy = BackupCodec.validate(old)
        val reading = base()
        old.getJSONObject("state").put(ReadingCatalogCodec.KEY, reading)
        val restored = BackupCodec.validate(old)
        assertTrue(restored.getJSONObject("state").getJSONObject(ReadingCatalogCodec.KEY).same(reading))
        for (key in legacy.getJSONObject("state").keys()) {
            assertTrue(key, restored.getJSONObject("state").getJSONObject(key).same(legacy.getJSONObject("state").getJSONObject(key)))
        }
        assertTrue(restored.getJSONArray("collections").same(legacy.getJSONArray("collections")))
        assertTrue(restored.getJSONArray("assets").same(legacy.getJSONArray("assets")))
        val collections = restored.getJSONArray("collections").let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
        val assets = restored.getJSONArray("assets").let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
        val state = restored.getJSONObject("state").let { s -> s.keys().asSequence().associateWith { s.getJSONObject(it) } }
        val exported = BackupCodec.export(collections, assets, restored.getJSONArray("queue"), state)
        assertEquals(1, exported.getInt("version"))
        assertTrue(exported.getJSONObject("state").getJSONObject(ReadingCatalogCodec.KEY).same(reading))
        old.getJSONObject("state").put("reading:library:v2", reading)
        assertTrue(runCatching { BackupCodec.validate(old) }.isFailure)
    }
    @Test fun collectionCleanupRemovesReadingReferencesOnlyForExactOwner() {
        val input = base()
        val next = CollectionStatePolicy.withoutCollection(ReadingCatalogCodec.KEY, input, "books:[]")!!
        for (field in listOf("collections", "groups", "titles", "memberships", "progress")) assertEquals(field, 1, next.getJSONArray(field).length())
        assertEquals(2, next.getJSONArray("settings").length()) // App default plus comics title override.
        assertEquals(2, input.getJSONArray("collections").length())
        assertTrue(CollectionStatePolicy.exportable(ReadingCatalogCodec.KEY))
        assertFalse(CollectionStatePolicy.exportable("reading:library:v2"))
        assertTrue(CollectionStatePolicy.withoutCollection(ReadingCatalogCodec.KEY, input, "books")!!.same(input))
    }
    @Test fun readingAndLegacyOwnersCannotCollide() {
        assertTrue(runCatching { ReadingCatalogCodec.requireSeparateOwners(base(), setOf("books:[]")) }.isFailure)
        ReadingCatalogCodec.requireSeparateOwners(base(), setOf("video"))
        val backup = fixture("batch8-backup-v1.json")
        val reading = base()
        val id = backup.getJSONArray("collections").getJSONObject(0).getString("id")
        reading.getJSONArray("collections").put(JSONObject().put("id", id).put("name", "Collision").put("subtype", "ebook")
            .put("locked", false).put("includeInGlobal", true).put("roots", JSONArray()))
        backup.getJSONObject("state").put(ReadingCatalogCodec.KEY, reading)
        assertTrue(runCatching { BackupCodec.validate(backup) }.isFailure)
    }
    @Test fun snapshotsRespectTheExistingNativeStateCap() {
        val input = base()
        val resources = JSONArray()
        for (i in 0 until 2600) resources.put(JSONObject().put("id", "$i").put("href", "$i.xhtml").put("label", "x".repeat(4096)))
        input.getJSONArray("titles").getJSONObject(0).put("readingOrder", resources)
        assertTrue(runCatching { ReadingCatalogCodec.validate(input) }.isFailure)
    }
}
