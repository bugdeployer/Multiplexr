package com.bugdeployer.multiplexr

import java.io.File
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class RxBaselineTest {
    @Test fun mixedMediaBackupValidatesExportsAndRestoresWithoutLosingReadingStyles() {
        val fixture = generateSequence(File(".").canonicalFile) { it.parentFile }
            .map { File(it, "test/fixtures/rx-mixed-backup-v1.json") }.first { it.isFile }
        val input = JSONObject(fixture.readText())
        val validated = BackupCodec.validate(input)
        val collections = validated.getJSONArray("collections").let { a ->
            (0 until a.length()).map { a.getJSONObject(it) }
        }
        val assets = validated.getJSONArray("assets").let { a ->
            (0 until a.length()).map { a.getJSONObject(it) }
        }
        val state = validated.getJSONObject("state").let { value ->
            value.keys().asSequence().associateWith { value.getJSONObject(it) }
        }
        val exported = BackupCodec.export(collections, assets, validated.getJSONArray("queue"), state)
        val restored = BackupCodec.validate(JSONObject(exported.toString()))
        assertEquals(4, restored.getJSONArray("collections").length())
        assertEquals(input.getJSONArray("assets").length(), restored.getJSONArray("assets").length())
        val restoredState = restored.getJSONObject("state")
        for (key in listOf("reading:library:v1", "reading:index:v1", "reading:management:v1", "reading:annotations:v1", "music:library", "audio:library")) {
            assertTrue("Missing durable state: $key", restoredState.has(key))
            assertEquals(validated.getJSONObject("state").getJSONObject(key).toString(), restoredState.getJSONObject(key).toString())
        }
        val titles = restoredState.getJSONObject("reading:library:v1").getJSONArray("titles")
        val styles = (0 until titles.length()).map { titles.getJSONObject(it).getJSONObject("metadata").optString("comicStyle") }
        assertTrue(styles.containsAll(listOf("manga", "manhua", "manhwa")))
        assertFalse(titles.getJSONObject(0).getJSONObject("source").getBoolean("available"))
        assertTrue(restoredState.getJSONObject("reading:annotations:v1").getJSONArray("items").length() > 0)
    }
}
