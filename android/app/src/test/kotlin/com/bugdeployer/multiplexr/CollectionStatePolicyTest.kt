package com.bugdeployer.multiplexr
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
class CollectionStatePolicyTest {
    @Test fun deletionPrunesSharedQueuesPinsAndRecoveryWithoutTouchingOtherOwners() {
        val id = "c:/quotes\""
        val queue = JSONObject().put("items", JSONArray().put(JSONObject().put("kind","music").put("collectionId",id).put("itemId","same"))
            .put(JSONObject().put("kind","music").put("collectionId","other").put("itemId","same")))
        val clean = CollectionStatePolicy.withoutCollection("queue:music",queue,id)!!
        assertEquals(1,clean.getJSONArray("items").length()); assertEquals(2,queue.getJSONArray("items").length())
        val pins = JSONArray().put(JSONArray(listOf(id,"title")).toString()).put(JSONArray(listOf("other","title")).toString())
        val prefs = JSONObject().put("cinema",JSONObject().put("pins",pins).put("counts",false))
        val filtered = CollectionStatePolicy.withoutCollection("spaces:display",prefs,id)!!
        assertEquals(1,filtered.getJSONObject("cinema").getJSONArray("pins").length())
        assertFalse(filtered.getJSONObject("cinema").getBoolean("counts"))
        assertEquals(2,prefs.getJSONObject("cinema").getJSONArray("pins").length())
        assertEquals(1,CollectionStatePolicy.withoutCollection("legacyVideoQueue",JSONObject().put("items",pins),id)!!.getJSONArray("items").length())
        assertNull(CollectionStatePolicy.withoutCollection("spaces:audiobooks:$id",JSONObject(),id))
    }
    @Test fun backupIncludesScopedPreferencesAndExcludesSecretsAndTransientJobs() {
        for (key in listOf("media:settings:[\"a\",\"title\"]", "spaces:audiobooks:a", "progress:[\"audiobook\",\"a\",\"title\"]", "audio:library", "spaces:display")) assertTrue(CollectionStatePolicy.exportable(key))
        for (key in listOf("metadata_provider", "audiobookdb_provider", "metadata:a", "ciphertext")) assertFalse(CollectionStatePolicy.exportable(key))
    }
    @Test fun cleanupUsesFullCollectionIdentityNotPrefixes() {
        val id = "a:/quotes\""
        assertTrue(CollectionStatePolicy.ownedBy("media:settings:" + JSONArray(listOf(id, "title")), id))
        assertTrue(CollectionStatePolicy.ownedBy("spaces:audiobooks:$id", id))
        assertTrue(CollectionStatePolicy.ownedBy("progress:" + JSONArray(listOf("audiobook", id, "title")), id))
        assertFalse(CollectionStatePolicy.ownedBy("spaces:audiobooks:ab", "a"))
        assertFalse(CollectionStatePolicy.ownedBy("media:settings:broken", id))
        assertFalse(CollectionStatePolicy.ownedBy("audio:library", id))
    }
    @Test fun scopedNavigationSettingsUsePortableSlashEncoding() {
        val android = "media:settings:" + JSONArray(listOf("collection", "folder:/Books/Title"))
        val dart = android.replace("\\/", "/")
        assertEquals(dart, MediaStateKeys.canonical(android))
        assertTrue(MediaStateKeys.aliases(dart).contains(android))
    }
}
