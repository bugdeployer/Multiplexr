package com.bugdeployer.multiplexr.plugins

import android.os.Handler
import android.os.Looper
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class MetadataPluginTest {
    @Test fun installedProviderUsesMediatedHttpAndReturnsMetadataInIsolatedRuntime() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val folder = File(context.cacheDir, "metadata-plugin-test-${System.nanoTime()}")
        try {
            // Independently built provider, signed with an ephemeral test key.
            val bytes = instrumentation.context.assets.open("openlibrary-provider-v0.2.0.mpx.json").use { it.readBytes() }
            val store = PluginStore(folder)
            val review = store.stage(bytes)
            val id = review["id"] as String
            store.activate(review["token"] as String, 0, setOf("metadata.provide", "http.request"), setOf("https://openlibrary.org"), setOf("books"), false)
            store.enabled(id, true)
            val installed = store.packageFor(id, store.row(id).getLong("revision"))
            val latch = CountDownLatch(1)
            var output: String? = null
            var failure: String? = null
            var calls = 0
            instrumentation.runOnMainSync {
                PluginRuntimeClient(context).run(installed.code,
                    """{"v":1,"id":"metadata","method":"metadata.search","params":{"query":"Dune","kind":"ebook"}}""",
                    { raw, reply ->
                        val request = JSONObject(raw)
                        assertEquals("http.get", request.getString("method"))
                        assertTrue(request.getJSONObject("params").getString("url").startsWith("https://openlibrary.org/search.json?title=Dune&"))
                        calls++
                        Handler(Looper.getMainLooper()).postDelayed({
                            reply(JSONObject().put("v",1).put("id",request.getString("id"))
                                .put("result",JSONObject().put("status",200).put("body",
                                    """{"docs":[{"key":"/works/OL893415W","title":"Dune","author_name":["Frank Herbert"],"first_publish_year":1965}],"numFound":1}"""))
                                .toString())
                        }, 3000)
                    }) { value, error -> output = value; failure = error; latch.countDown() }
            }
            assertTrue(latch.await(12, TimeUnit.SECONDS))
            assertNull(failure)
            assertEquals(1, calls)
            val result = JSONObject(output!!).getJSONObject("result")
            val candidate = result.getJSONArray("items").getJSONObject(0)
            assertEquals("Dune", candidate.getString("title"))
            assertEquals("Frank Herbert", candidate.getJSONArray("authors").getString(0))
            assertEquals(1965, candidate.getJSONObject("fields").getInt("year"))
            assertTrue(result.isNull("nextCursor"))
        } finally { folder.deleteRecursively() }
    }
}
