package com.bugdeployer.multiplexr
import com.bugdeployer.multiplexr.plugins.*
import okhttp3.*
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class PluginHttpTest {
    private fun client(handle: (Request)->Pair<Int,Pair<String?,String>>) = OkHttpClient.Builder().addInterceptor { chain ->
        val response=handle(chain.request())
        Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(response.first).message("test").body(response.second.second.toResponseBody()).apply { response.second.first?.let { header("Location",it) } }.build()
    }.build()
    @Test fun approvedRedirectIsRecheckedAndUnapprovedRedirectNeverConnects() {
        val requests=mutableListOf<String>()
        val http=PluginHttp(client { request -> requests.add(request.url.toString());302 to ("https://blocked.example/private" to "") })
        try { http.get("https://example.com/start",setOf("https://example.com"),register={},check={});fail("Expected redirect rejection") } catch(_: IllegalArgumentException) { }
        assertEquals(listOf("https://example.com/start"),requests)
    }
    @Test fun credentialNeverFollowsRedirectToAnotherApprovedOrigin() {
        var calls=0
        val http=PluginHttp(client { request -> calls++;assertEquals("Bearer private",request.header("Authorization"));302 to ("https://other.example/echo" to "") })
        try { http.get("https://example.com/start",setOf("https://example.com","https://other.example"),"Authorization" to "Bearer private",register={},check={});fail("Expected credential redirect rejection") } catch(_: IllegalArgumentException) { }
        assertEquals(1,calls)
    }
    @Test fun responseBoundAndSecretRedactionApplyBeforePluginReceivesData() {
        val http=PluginHttp(client { 200 to (null to "private Bearer private") })
        val result=http.get("https://example.com",setOf("https://example.com"),"Authorization" to "Bearer private",register={},check={})
        assertFalse((result["body"] as String).contains("private"));assertEquals(setOf("body","status"),result.keys)
        try { PluginHttp(client { 200 to (null to "x".repeat(65537)) }).get("https://example.com",setOf("https://example.com"),register={},check={});fail("Expected bound") } catch(_: IllegalArgumentException) { }
    }
    @Test fun cancellationAndRedirectLimitsStopAdditionalEffects() {
        var calls=0
        val http=PluginHttp(client { calls++;302 to ("/again" to "") })
        try { http.get("https://example.com",setOf("https://example.com"),register={},check={});fail("Expected redirect limit") } catch(_: IllegalStateException) { }
        assertEquals(4,calls)
        calls=0
        try { http.get("https://example.com",setOf("https://example.com"),register={},check={throw IllegalStateException("revoked")});fail("Expected revocation") } catch(_: IllegalStateException) { }
        assertEquals(0,calls)
    }
}
