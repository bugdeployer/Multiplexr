package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PortabilityTest {
    private fun collection() = JSONObject().put("id", "c").put("name", "Movies").put("type", "video").put("subtype", "cinema").put("view", "grid").put("player", "internal")
        .put("roots", JSONArray().put(JSONObject().put("uri", "content://folder").put("name", "Movies"))).put("extensions", JSONArray(listOf("mp4"))).put("locked", true)
    private fun asset() = JSONObject().put("id", "same").put("collectionId", "c").put("uri", "content://file").put("filename", "Movie.mp4").put("metadata", JSONObject().put("title", "Custom title").put("tags", "Travel"))
        .put("favorite", true).put("positionMs", 4000).put("watched", false).put("localPoster", "/private/cache.jpg").put("thumbnail", "/private/thumb.jpg")
    private fun backup() = BackupCodec.export(listOf(collection()), listOf(asset()), JSONArray().put("[\"c\",\"same\"]"), emptyMap())
    @Test fun exportPreservesCuratedDataAndHistoryButExcludesCredentialsAndCache() {
        val source = collection().put("apiToken", "must-not-export")
        val out = BackupCodec.export(listOf(source), listOf(asset()), JSONArray(), emptyMap())
        assertFalse(out.toString().contains("must-not-export")); assertFalse(out.toString().contains("/private/"))
        assertEquals("Custom title", out.getJSONArray("assets").getJSONObject(0).getJSONObject("metadata").getString("title"))
        assertEquals(4000, out.getJSONArray("assets").getJSONObject(0).getInt("positionMs"))
        assertTrue(out.getJSONArray("collections").getJSONObject(0).getBoolean("locked"))
        assertEquals(1, BackupCodec.validate(JSONObject(out.toString())).getInt("version"))
    }
    @Test fun scopedSettingsAndLocalSpacePreferencesSurviveExportAndRestore() {
        val settingsKey = "media:settings:" + JSONArray(listOf("c", "title:/folder"))
        val input = mapOf(
            settingsKey to JSONObject().put("rate", 1.5).put("openAction", "play"),
            "spaces:audiobooks:c" to JSONObject().put("confirmExit", false).put("source", "pinned").put("pins", JSONArray().put(JSONArray(listOf("c", "title")).toString()))
        )
        val out = BackupCodec.export(listOf(collection()), emptyList(), JSONArray(), input.filterKeys(CollectionStatePolicy::exportable))
        val restored = BackupCodec.validate(JSONObject(out.toString())).getJSONObject("state")
        assertEquals(1.5, restored.getJSONObject(settingsKey).getDouble("rate"), .001)
        assertFalse(restored.getJSONObject("spaces:audiobooks:c").getBoolean("confirmExit"))
        assertEquals(1, restored.getJSONObject("spaces:audiobooks:c").getJSONArray("pins").length())
    }
    @Test fun rejectsFutureVersionsBeforeRestore() { try { BackupCodec.validate(backup().put("version", 2)); fail() } catch (_: IllegalArgumentException) {} }
    @Test fun rejectsDuplicateCollections() { val b = backup(); b.getJSONArray("collections").put(collection()); try { BackupCodec.validate(b); fail() } catch (_: IllegalArgumentException) {} }
    @Test fun rejectsDuplicateAssets() { val b = backup(); b.getJSONArray("assets").put(asset()); try { BackupCodec.validate(b); fail() } catch (_: IllegalArgumentException) {} }
    @Test fun rejectsOrphanAsset() { val b = backup(); b.getJSONArray("assets").getJSONObject(0).put("collectionId", "other"); try { BackupCodec.validate(b); fail() } catch (_: IllegalArgumentException) {} }
    @Test fun queueDeduplicatesAndDropsOrphans() { val b = backup(); b.getJSONArray("queue").put("[\"c\",\"same\"]").put("[\"c\",\"gone\"]"); assertEquals(1, BackupCodec.validate(b).getJSONArray("queue").length()) }
    @Test fun tagsNormalizeCaseAndMerge() {
        assertEquals(listOf("Travel", "Family"), TagOperations.normalize(listOf(" #Travel, travel;Family")))
        assertEquals(listOf("Family"), TagOperations.apply("Travel, Family", "rename", listOf("travel"), "family"))
        assertEquals(listOf("Travel"), TagOperations.apply("Travel, Family", "delete", listOf("FAMILY"), null))
    }
    @Test fun tagsReplaceAndRemoveAreIndependentOfHistory() {
        assertEquals(emptyList<String>(), TagOperations.apply("Travel", "replace", emptyList(), null))
        assertEquals(listOf("Travel", "Friends"), TagOperations.apply("Travel", "add", listOf("Friends"), null))
        assertEquals(listOf("Travel"), TagOperations.apply("Travel, Friends", "remove", listOf("friends"), null))
    }
    @Test fun rejectsInvalidRename() { try { TagOperations.apply("a", "rename", listOf("a"), "b,c"); fail() } catch (_: IllegalArgumentException) {} }
    @Test fun rejectsLongTags() { try { TagOperations.normalize(listOf("a".repeat(81))); fail() } catch (_: IllegalArgumentException) {} }
    @Test fun reconnectRetainsTheDurableIdReferencedByTheQueue() {
        val queue = JSONArray().put("[\"c\",\"old\"]").put("[\"other\",\"old\"]")
        val previous = JSONObject().put("id","old").put("filename","clip.mp4").put("size",100).put("available",false)
        val found = mutableMapOf("new" to JSONObject().put("id","new").put("filename","clip.mp4").put("size",100))
        ScanIdentity.reconnect(mapOf("old" to previous),found,emptySet())
        assertEquals("old",found.getValue("old").getString("id"))
        assertEquals("old",JSONArray(queue.getString(0)).getString(1))
        assertEquals("other",JSONArray(queue.getString(1)).getString(0))
    }
    @Test fun malformedTypedFieldsAreRejectedBeforeReplacement() {
        val wrongSize = backup(); wrongSize.getJSONArray("collections").getJSONObject(0).put("cardSize", "large")
        try { BackupCodec.validate(wrongSize); fail() } catch (_: IllegalArgumentException) {}
        val wrongHistory = backup(); wrongHistory.getJSONArray("assets").getJSONObject(0).put("watched", "false")
        try { BackupCodec.validate(wrongHistory); fail() } catch (_: IllegalArgumentException) {}
    }

    @Test fun legacyFilenameOnlyScansRemainInferable() {
        val raw = asset(); raw.remove("metadata")
        val backup = BackupCodec.export(listOf(collection()), listOf(raw), JSONArray(), emptyMap())
        assertFalse(backup.getJSONArray("assets").getJSONObject(0).has("metadata"))
        assertEquals("Movie.mp4", backup.getJSONArray("assets").getJSONObject(0).getString("filename"))
    }

}
