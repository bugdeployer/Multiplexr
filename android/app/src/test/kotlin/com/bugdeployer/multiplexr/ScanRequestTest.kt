package com.bugdeployer.multiplexr
import org.junit.Assert.*
import org.junit.Test

class ScanRequestTest {
    @Test fun legacyStringKeepsOldResponseShape() {
        val request = ScanRequest.decode("collection")
        assertNull(request.requestId)
        assertEquals(listOf("warning"), request.result(listOf("warning")))
        assertFalse(request.progress(2,"folder").containsKey("requestId"))
    }
    @Test fun trackedRequestEchoesIdentityInProgressAndResult() {
        val request = ScanRequest.decode(mapOf("id" to "collection", "requestId" to "generation-2"))
        assertEquals("generation-2", request.progress(2,"folder")["requestId"])
        val result = request.result(listOf("warning")) as Map<*, *>
        assertEquals("generation-2", result["requestId"])
        assertEquals(listOf("warning"), result["warnings"])
    }
    @Test(expected = IllegalArgumentException::class) fun invalidTokenIsRejected() {
        ScanRequest.decode(mapOf("id" to "collection", "requestId" to 3))
    }
    @Test(expected = IllegalArgumentException::class) fun missingCollectionIsRejected() {
        ScanRequest.decode(mapOf("requestId" to "generation"))
    }
}
