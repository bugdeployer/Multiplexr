package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class JobReceiptCodecTest {
    private fun row(id: String) = JSONObject().put("key", "metadata:$id")
        .put("collections", JSONArray(listOf(id))).put("outcome", "interrupted")
    private fun ledger() = JSONObject().put("version", 1)
        .put("receipts", JSONArray().put(row("a")).put(row("b")))
    @Test fun receiptsAreWritableLocalOnlyAndPrunedByExactOwner() {
        val value = ledger()
        JobReceiptCodec.validate(value)
        assertTrue(CollectionStatePolicy.writable(JobReceiptCodec.KEY, false))
        assertFalse(CollectionStatePolicy.exportable(JobReceiptCodec.KEY))
        val after = CollectionStatePolicy.withoutCollection(JobReceiptCodec.KEY, value, "a")!!
        assertEquals("metadata:b", after.getJSONArray("receipts").getJSONObject(0).getString("key"))
        assertEquals(2, value.getJSONArray("receipts").length())
    }
    @Test fun rejectsUnknownPayloadFieldsAndDuplicateReceipts() {
        for (value in listOf(
            ledger().put("commands", JSONArray()),
            ledger().also { it.getJSONArray("receipts").getJSONObject(0).put("token", "secret") },
            ledger().also { it.getJSONArray("receipts").put(row("a")) },
            ledger().also { it.getJSONArray("receipts").getJSONObject(0).put("outcome", "replay") }
        )) {
            assertTrue(runCatching { JobReceiptCodec.validate(value) }.isFailure)
        }
    }
}
