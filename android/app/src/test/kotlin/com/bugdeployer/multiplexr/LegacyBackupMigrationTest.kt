package com.bugdeployer.multiplexr

import java.io.File
import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class LegacyBackupMigrationTest {
    private fun fixture(): JSONObject {
        val file = generateSequence(File(".").canonicalFile) { it.parentFile }
            .map { File(it,"test/fixtures/batch8-backup-v1.json") }.first { it.isFile }
        return JSONObject(file.readText())
    }
    @Test fun legacyRestoreNormalizeExportAndRepeatKeepAllDurableIdentity() {
        val original = fixture(); val validated = BackupCodec.validate(original)
        val collections = validated.getJSONArray("collections").let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
        val states = validated.getJSONObject("state").let { value -> value.keys().asSequence().associateWith { value.getJSONObject(it) } }
        val plan = CatalogNormalization.plan(collections,states)
        val normalized = collections.map { c -> plan.collections.firstOrNull { it.getString("id")==c.getString("id") } ?: c }
        assertEquals(3,normalized.size)
        assertEquals("audio",normalized.single { it.getString("id")=="audio" }.getString("type"))
        val assets = validated.getJSONArray("assets").let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
        val exported = BackupCodec.export(normalized,assets,validated.getJSONArray("queue"),states+plan.state)
        val repeated = BackupCodec.validate(JSONObject(exported.toString()))
        for (key in listOf("collections","assets","state","queue")) assertEquals(exported.get(key).toString(),repeated.get(key).toString())
        assertEquals(original.getJSONObject("state").getJSONObject("audio:library").toString(),repeated.getJSONObject("state").getJSONObject("audio:library").toString())
        assertEquals(original.getJSONArray("queue").toString(),repeated.getJSONArray("queue").toString())
        assertEquals(4,repeated.getJSONArray("assets").length())
        val progress = repeated.getJSONObject("state").getJSONObject("progress:[\"audiobook\",\"audio\",\"folder:Saga/One\"]")
        assertEquals("Keep bookmark",progress.getJSONArray("bookmarks").getJSONObject(0).getString("label"))
        assertEquals(3000,progress.getInt("positionMs"))
        assertTrue(normalized.single { it.getString("id")=="audio" }.getBoolean("locked"))
        assertFalse(normalized.single { it.getString("id")=="audio" }.getBoolean("includeInGlobalAudio"))
        assertEquals("manual-show",assets[1].getJSONObject("metadata").getString("groupId"))
        assertTrue(CatalogNormalization.plan(normalized,states+plan.state).collections.isEmpty())
    }
    @Test fun duplicateAliasesAndPrivateTransientStateAreNotExported() {
        val input = fixture(); val state = input.getJSONObject("state")
        state.put("catalog:migration:1",JSONObject().put("before","private snapshot"))
        state.put("metadata:audio",JSONObject().put("apiKey","secret"))
        state.put("provider_secret","secret")
        val key = "progress:[\"audiobook\",\"audio\",\"folder:Saga/One\"]"
        val legacy = state.keys().asSequence().first { it.startsWith("progress:") }
        state.put(key,JSONObject(state.getJSONObject(legacy).toString()).put("positionMs",9000).put("apiKey","secret"))
        val output = BackupCodec.validate(input)
        assertEquals(9000,output.getJSONObject("state").getJSONObject(key).getInt("positionMs"))
        assertEquals(1,output.getJSONObject("state").keys().asSequence().count { it.startsWith("progress:") })
        assertFalse(output.toString().contains("secret")); assertFalse(output.toString().contains("private snapshot"))
    }
}
