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

class InstalledPluginTest {
    @Test fun mediatedNetworkWaitDoesNotConsumeCpuOrOldTwoSecondWallLimit() {
        val start = android.os.SystemClock.elapsedRealtime()
        val (value, error) = execute("tool.inspect") { raw, reply ->
            val request = JSONObject(raw)
            Handler(Looper.getMainLooper()).postDelayed({
                reply(JSONObject().put("v",1).put("id",request.getString("id")).put("result",JSONObject().put("protocol",1).put("runtime","slow-network")).toString())
            }, 3000)
        }
        assertNull(error)
        assertTrue(android.os.SystemClock.elapsedRealtime() - start >= 3000)
        assertEquals("slow-network", JSONObject(value!!).getJSONObject("result").getString("runtime"))
    }
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun signed() = instrumentation.context.assets.open("installed-signed.plugin.json").use { it.readBytes() }
    private fun execute(method: String,host: (String,(String)->Unit)->Unit): Pair<String?,String?> {
        val folder=File(context.cacheDir,"plugin-installed-test-${System.nanoTime()}")
        val store=PluginStore(folder);val review=store.stage(signed());val id=review["id"] as String
        store.activate(review["token"] as String,0,setOf("runtime.ping","catalog.read"),emptySet(),setOf("collection"),false)
        assertFalse(store.row(id).getBoolean("enabled"));store.enabled(id,true)
        val p=store.packageFor(id,store.row(id).getLong("revision"))
        val latch=CountDownLatch(1);var output:String?=null;var error:String?=null
        instrumentation.runOnMainSync {
            PluginRuntimeClient(context).run(p.code,JSONObject().put("v",1).put("id","installed").put("method",method).put("params",JSONObject().put("scopes",org.json.JSONArray().put(JSONObject().put("handle","opaque-scope")))).toString(),host) { value,failure -> output=value;error=failure;latch.countDown() }
        }
        assertTrue("Installed interpreter did not complete",latch.await(8,TimeUnit.SECONDS))
        folder.deleteRecursively();return output to error
    }
    @Test fun independentlySignedPackageRunsAfterInstallationWithoutRebuild() {
        var calls=0
        val (value,error)=execute("tool.inspect") { raw,reply ->
            val request=JSONObject(raw);assertEquals("runtime.ping",request.getString("method"));calls++
            reply(JSONObject().put("v",1).put("id",request.getString("id")).put("result",JSONObject().put("protocol",1).put("runtime","mediated")).toString())
        }
        assertNull(error);assertEquals(1,calls);assertEquals("mediated",JSONObject(value!!).getJSONObject("result").getString("runtime"))
    }
    @Test fun mediatedUtf8HasNoNativeObjectsOrRawScopeIdentifiers() {
        val (value,error)=execute("tool.read") { raw,reply ->
            val request=JSONObject(raw);assertEquals("opaque-scope",request.getJSONObject("params").getString("handle"))
            reply(JSONObject().put("v",1).put("id",request.getString("id")).put("result",JSONObject().put("title","Allowed \uD83D\uDC26")).toString())
        }
        assertNull(error);assertEquals("Allowed \uD83D\uDC26",JSONObject(value!!).getJSONObject("result").getString("title"))
    }
    @Test fun revokedHostCallsReturnBoundedErrorsWithoutExceptionMessages() {
        val (value,error)=execute("tool.inspect") { raw,reply -> val request=JSONObject(raw);reply(JSONObject().put("v",1).put("id",request.getString("id")).put("error",JSONObject().put("code","permission_denied")).toString()) }
        assertNull(error);assertEquals("permission_denied",JSONObject(value!!).getJSONObject("error").getString("code"))
    }
    @Test fun installedNonterminationCannotFreezeHostMainThread() {
        val (value,error)=execute("tool.loop") { _,reply -> reply("{}") }
        assertNull(value);assertTrue(error in setOf("deadline_exceeded","runtime_failure"))
        val latch=CountDownLatch(1);Handler(Looper.getMainLooper()).post { latch.countDown() };assertTrue(latch.await(1,TimeUnit.SECONDS))
    }
    @Test fun credentialsAreEncryptedAndDestinationBoundAndRemovable() {
        val root=File(context.cacheDir,"plugin-vault-test-${System.nanoTime()}")
        try {
            val vault=PluginCredentials(root);vault.save("org.example.inspector","https://example.com","private-test-token")
            assertFalse(root.listFiles()!!.single().readBytes().toString(Charsets.ISO_8859_1).contains("private-test-token"))
            assertEquals("Bearer private-test-token",vault.header("org.example.inspector","https://example.com")!!.second)
            assertEquals("X-API-Key" to "private-test-token",vault.header("org.example.inspector","https://example.com",true))
            assertNull(vault.header("org.other.tool","https://example.com"));assertNull(vault.header("org.example.inspector","https://different.example"))
            vault.remove("org.example.inspector",setOf("https://example.com"));assertNull(vault.header("org.example.inspector","https://example.com"))
        } finally { root.deleteRecursively() }
    }
}
