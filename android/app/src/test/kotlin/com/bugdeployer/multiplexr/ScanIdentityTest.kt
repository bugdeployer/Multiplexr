package com.bugdeployer.multiplexr

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ScanIdentityTest {
    private fun file(id: String) = JSONObject().put("id", id).put("filename", "clip.mp4").put("size", 100).put("rootUri", "root").put("available", true)
    @Test fun uniqueMovePreservesMetadataAndHistory() {
        val old = file("old").put("available", false).put("positionMs", 5000).put("metadata", JSONObject().put("title", "Custom"))
        val found = linkedMapOf("new" to file("new"))
        assertEquals(mapOf("new" to "old"), ScanIdentity.reconnect(mapOf("old" to old), found, setOf("root")))
        assertEquals("old", found.getValue("old").getString("id"))
        assertEquals(5000, found.getValue("old").getInt("positionMs"))
        assertEquals("Custom", found.getValue("old").getJSONObject("metadata").getString("title"))
    }
    @Test fun multipleNewCopiesNeverStealHistoryFromOneOldFile() {
        val found = linkedMapOf("a" to file("a"), "b" to file("b"))
        val old = file("old").put("available", false).put("positionMs", 5000)
        assertTrue(ScanIdentity.reconnect(mapOf("old" to old), found, setOf("root")).isEmpty())
        assertFalse(found.getValue("a").has("positionMs"))
    }
    @Test fun repeatReconnectRetainsIdentityAndQueueKeys() {
        val old = file("old").put("available", false)
        val first = linkedMapOf("new" to file("new"))
        ScanIdentity.reconnect(mapOf("old" to old), first, setOf("root"))
        assertEquals(setOf("old"), first.keys)
        val second = linkedMapOf("old" to JSONObject(first.getValue("old").toString()))
        assertTrue(ScanIdentity.reconnect(first, second, setOf("root")).isEmpty())
        assertEquals(first.getValue("old").toString(), second.getValue("old").toString())
    }
    @Test fun ambiguousReconnectIsReportedForReview() {
        val found = linkedMapOf("new" to file("new"))
        val warnings = mutableListOf<String>()
        ScanIdentity.reconnect(mapOf("one" to file("one").put("available", false),
            "two" to file("two").put("available", false)), found, setOf("root")) { warnings.add(it) }
        assertEquals(1, warnings.size)
        assertEquals("new", found.getValue("new").getString("id"))
    }
    @Test fun reappearingOriginalPreventsFalseMove() {
        val old = file("old").put("available", false)
        val found = linkedMapOf("new" to file("new"), "old" to file("old"))
        assertTrue(ScanIdentity.reconnect(mapOf("old" to old), found, setOf("root")).isEmpty())
    }
}
