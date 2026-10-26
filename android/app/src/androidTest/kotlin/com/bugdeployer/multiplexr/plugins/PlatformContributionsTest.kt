package com.bugdeployer.multiplexr.plugins
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class PlatformContributionsTest {
    @Test fun independentlyBuiltGeneralContributionsRunInIsolatedInterpreter() {
        val instrumentation=InstrumentationRegistry.getInstrumentation();val context=instrumentation.targetContext
        val root=File(context.cacheDir,"platform-demo-${System.nanoTime()}")
        try {
            val store=PluginStore(root)
            val bytes=instrumentation.context.assets.open("platform-demo.plugin.json").use { it.readBytes() }
            val review=store.stage(bytes);val id=review["id"] as String
            val permissions=(review["permissions"] as List<*>).map { it as String }.toSet()
            store.activate(review["token"] as String,0,permissions,emptySet(),setOf("collection"),false)
            store.enabled(id,true);val revision=store.row(id).getLong("revision");val plugin=store.packageFor(id,revision)
            val cases=mapOf(
                "metadata.provider" to "{\"query\":\"Example\",\"kind\":\"ebook\"}",
                "artwork.provider" to "{\"title\":\"opaque-title\",\"roles\":[\"cover\"]}",
                "source.provider" to "{\"root\":\"opaque-root\"}",
                "import.handler" to "{\"input\":\"opaque-input\",\"mime\":\"text/plain\",\"selection\":[{\"id\":\"opaque-title\",\"revision\":\"r1\"}]}",
                "export.handler" to "{\"selection\":[]}", "library.tool" to "{\"selection\":[]}",
                "event.handler" to "{\"event\":\"org.multiplexr:library.changed\",\"sequence\":1,\"data\":{}}",
                "ui.action" to "{\"scope\":{\"scope\":\"app\"}}", "ui.section" to "{\"scope\":{\"scope\":\"app\"}}", "ui.destination" to "{\"scope\":{\"scope\":\"app\"}}",
                "session.hook" to "{\"session\":\"opaque-session\",\"state\":{\"kind\":\"time\",\"milliseconds\":0}}"
            )
            for((method,params) in cases) {
                val latch=CountDownLatch(1);var output:String?=null;var error:String?=null
                val input=JSONObject().put("v",1).put("id","sample").put("method",method).put("params",JSONObject(params)).toString()
                instrumentation.runOnMainSync {
                    PluginRuntimeClient(context).run(plugin.code,input,{ raw,reply ->
                        val request=JSONObject(raw);assertEquals("imports.read",request.getString("method"))
                        reply(JSONObject().put("v",1).put("id",request.getString("id")).put("result",JSONObject().put("text","Synthetic import").put("mime","text/plain")).toString())
                    }) { value,failure -> output=value;error=failure;latch.countDown() }
                }
                assertTrue(method,latch.await(8,TimeUnit.SECONDS));assertNull(method,error)
                val response=JSONObject(output!!);assertTrue("$method: $response",response.has("result"))
            }
            store.enabled(id,false)
            try {store.withCapability(id,revision,"metadata.provide",setOf("collection")) { };fail("Disabled plugin retained authority") } catch(_:IllegalArgumentException) { }
            store.remove(id,true);assertTrue(store.inventory().isEmpty())
        } finally {root.deleteRecursively()}
    }
}
