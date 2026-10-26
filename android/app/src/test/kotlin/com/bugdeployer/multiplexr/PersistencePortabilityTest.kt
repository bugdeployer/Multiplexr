package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PersistencePortabilityTest {
    @Test fun restoreKeepsExactAndParentGrantsWithoutPrefixConfusion() {
        val root = "content://provider/tree/primary%3ABooks%2FSaga"
        assertTrue(RestoreReconciliation.granted(root,setOf(root)))
        assertTrue(RestoreReconciliation.granted(root,setOf("content://provider/tree/primary%3ABooks")))
        assertFalse(RestoreReconciliation.granted(root,setOf("content://provider/tree/primary%3ABook")))
        assertFalse(RestoreReconciliation.granted(root,setOf("content://other/tree/primary%3ABooks")))
        assertFalse(RestoreReconciliation.granted(root,emptySet()))
        val original = JSONObject().put("id","c").put("roots",JSONArray().put(JSONObject().put("uri",root)))
        val restored = RestoreReconciliation.collection(original,setOf(root))
        assertTrue(restored.getJSONObject("rootHealth").getString(root).startsWith("Permission retained"))
        assertFalse(original.has("rootHealth"))
    }
    @Test fun legacyProgressGetsItsDurableIdentityAndDropsNonPortableFields() {
        val key = "progress:[\"audiobook\",\"c\",\"folder:A/B\"]"
        val old = JSONObject().put("chapterId","chapter").put("positionMs",42).put("apiKey","private")
            .put("bookmarks",JSONArray().put(JSONObject().put("chapterId","chapter").put("positionMs",5).put("label","Keep").put("token","private")))
        val value = DurableMediaStateCodec.validate(key,old)
        assertEquals("folder:A/B",value.getJSONObject("id").getString("itemId"))
        assertEquals(42,value.getInt("positionMs")); assertFalse(value.toString().contains("private"))
        assertEquals("Keep",value.getJSONArray("bookmarks").getJSONObject(0).getString("label"))
    }
    @Test(expected=IllegalArgumentException::class) fun mismatchedProgressIdentityIsRejected() {
        DurableMediaStateCodec.validate("progress:[\"audiobook\",\"c\",\"one\"]",JSONObject("""{"id":{"kind":"audiobook","collectionId":"c","itemId":"two"}}"""))
    }
    @Test fun queuesDeduplicateAndCatalogDeletionPrunesOnlyTheRemovedTitle() {
        val id = JSONObject("""{"kind":"audiobook","collectionId":"c","itemId":"one"}""")
        val other = JSONObject(id.toString()).put("collectionId","other")
        val queue = JSONObject().put("items",JSONArray().put(id).put(other).put(id))
        assertEquals(2,DurableMediaStateCodec.validate("queue:audiobook",queue).getJSONArray("items").length())
        val catalog = JSONObject().put("books",JSONArray().put(JSONObject().put("id",other)))
        val kept = DurableMediaStateCodec.retainBooks(queue,catalog).getJSONArray("items")
        assertEquals(1,kept.length()); assertEquals("other",kept.getJSONObject(0).getString("collectionId"))
    }
    @Test fun negativeHistoryIsRejectedBeforeRestore() {
        try { DurableMediaStateCodec.validate("progress:[\"audiobook\",\"c\",\"one\"]",JSONObject().put("positionMs",-1)); fail() }
        catch (_: IllegalArgumentException) {}
    }
}
