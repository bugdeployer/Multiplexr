package com.bugdeployer.multiplexr

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject
import org.json.JSONArray

class AudioScanReconciliationTest {
    @Test fun repeatedAppendKeepsManualChapterOrderAndOriginalSources() {
        val book = JSONObject("""{"files":[{"id":"original","uri":"content://original"}],"chapters":[{"id":"second","fileId":"original"},{"id":"first","fileId":"original"}],"positionMs":1234}""")
        val files = listOf(JSONObject("""{"id":"new","uri":"content://new"}"""))
        val chapters = JSONArray("""[{"id":"third","fileId":"new"}]""")
        AudioScanReconciliation.append(book, files, chapters)
        val first = book.toString()
        AudioScanReconciliation.append(book, files, chapters)
        assertEquals(first, book.toString())
        assertEquals("second", book.getJSONArray("chapters").getJSONObject(0).getString("id"))
        assertEquals(2, book.getJSONArray("files").length())
        assertEquals(1234, book.getInt("positionMs"))
    }
    @Test fun repeatedScanNeverCreatesAnotherBook() {
        assertEquals(AudioScanReconciliation.Decision.Create, AudioScanReconciliation.decide(emptySet(), null, 3))
        assertEquals(AudioScanReconciliation.Decision.Unchanged, AudioScanReconciliation.decide(setOf("book"), "book", 0))
        assertEquals(AudioScanReconciliation.Decision.Append("book"), AudioScanReconciliation.decide(setOf("book"), "book", 1))
        assertEquals(AudioScanReconciliation.Decision.Unchanged, AudioScanReconciliation.decide(setOf("book"), "book", 0))
    }
    @Test fun ambiguousOwnersNeverStealSources() {
        assertEquals(AudioScanReconciliation.Decision.Review, AudioScanReconciliation.decide(setOf("one", "two"), null, 1))
        assertEquals(AudioScanReconciliation.Decision.Review, AudioScanReconciliation.decide(setOf("one"), "two", 1))
    }
    @Test fun standaloneAndSingleM4bUseTheSameDecision() {
        for (count in listOf(1, 103)) {
            assertEquals(AudioScanReconciliation.Decision.Create, AudioScanReconciliation.decide(emptySet(), null, count))
            assertEquals(AudioScanReconciliation.Decision.Append("original"), AudioScanReconciliation.decide(setOf("original"), null, count))
        }
    }
}
