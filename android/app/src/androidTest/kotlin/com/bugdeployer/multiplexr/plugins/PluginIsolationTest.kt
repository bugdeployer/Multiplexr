package com.bugdeployer.multiplexr.plugins

import android.content.*
import android.os.*
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

class PluginIsolationTest {
    private class Session : AutoCloseable {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val received = LinkedBlockingQueue<Bundle>()
        val connected = CountDownLatch(1)
        val died = CountDownLatch(1)
        var remote: Messenger? = null
        var id = 0L
        val replies = Messenger(object : Handler(Looper.getMainLooper()) {
            override fun handleMessage(msg: Message) { received.offer(msg.data) }
        })
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                remote = Messenger(binder)
                binder.linkToDeath({ died.countDown() }, 0)
                connected.countDown()
            }
            override fun onServiceDisconnected(name: ComponentName) { remote = null; died.countDown() }
        }
        init {
            assertTrue(context.bindService(Intent(context, PluginSandboxService::class.java), connection, Context.BIND_AUTO_CREATE))
            assertTrue("sandbox bind timeout", connected.await(10, TimeUnit.SECONDS))
        }
        fun send(what: Int, source: String = "", input: String = "{}", version: Int = 1, requestId: Long = ++id) {
            remote!!.send(Message.obtain(null, what).apply {
                replyTo = replies
                data = Bundle().apply {
                    putLong("id", requestId); putInt("v", version)
                    putByteArray("source", source.toByteArray()); putByteArray("input", input.toByteArray())
                }
            })
        }
        fun result(): Bundle = received.poll(5, TimeUnit.SECONDS) ?: throw AssertionError("No bounded response")
        fun run(body: String, input: String = "{}"): Bundle {
            send(PluginSandboxService.RUN, "function multiplexrEntry(request) { $body }", input)
            return result()
        }
        override fun close() { context.unbindService(connection) }
    }
    @Test fun isolatedUidAndNoAmbientAuthority() = Session().use { s ->
        s.send(PluginSandboxService.INFO)
        val identity = s.result().getString("value")!!.split(":").map { it.toInt() }
        assertNotEquals(Process.myPid(), identity[0]); assertNotEquals(Process.myUid(), identity[1])
        assertEquals(android.content.pm.PackageManager.PERMISSION_DENIED,
            s.context.checkPermission(android.Manifest.permission.INTERNET, identity[0], identity[1]))
        val result = s.run("return ['Java','Dart','require','std','os','fetch','XMLHttpRequest','Worker','process'].map(k => typeof globalThis[k]);")
        assertEquals("ok", result.getString("status"))
        assertEquals("[\"undefined\",\"undefined\",\"undefined\",\"undefined\",\"undefined\",\"undefined\",\"undefined\",\"undefined\",\"undefined\"]", result.getString("value"))
    }
    @Test fun infiniteLoopInterruptedAndNextInvocationWorks() = Session().use { s ->
        val start = SystemClock.elapsedRealtime()
        assertEquals("deadline_exceeded", s.run("while (true) {}").getString("status"))
        assertTrue(SystemClock.elapsedRealtime() - start < 2000)
        assertEquals("42", s.run("return 6 * 7;").getString("value"))
    }
    @Test fun memoryExhaustionContainedAndContextDiscarded() = Session().use { s ->
        val result = s.run("globalThis.poison = true; return new Uint8Array(64 * 1024 * 1024);")
        assertEquals("resource_limit", result.getString("status"))
        assertEquals("\"undefined\"", s.run("return typeof globalThis.poison;").getString("value"))
    }
    @Test fun cancellationInterruptsExecutingCode() = Session().use { s ->
        s.send(PluginSandboxService.RUN, "function multiplexrEntry() { while (true) {} }")
        val runId = s.id
        s.send(PluginSandboxService.CANCEL, requestId = runId)
        assertEquals("cancelled", s.result().getString("status"))
        assertEquals("true", s.run("return true;").getString("value"))
    }
    @Test fun messagesAndVersionsAreBounded() = Session().use { s ->
        s.send(PluginSandboxService.RUN, "x".repeat(65537))
        assertEquals("message_too_large", s.result().getString("status"))
        s.send(PluginSandboxService.RUN, "", version = 2)
        assertEquals("version_mismatch", s.result().getString("status"))
        assertEquals("message_too_large", s.run("return 'x'.repeat(65537);").getString("status"))
        assertEquals("invalid_request", s.run("return 1;", "{bad").getString("status"))
    }
    @Test fun invalidHostCallsCannotReachNativeFeatures() = Session().use { s ->
        val response = s.run("return JSON.parse(__hostCall(JSON.stringify({v:1,id:'bad1',method:'native.files.read',params:{path:'/data/data/com.bugdeployer.multiplexr'}})));")
        assertEquals("unsupported_capability", JSONObject(response.getString("value")!!).getJSONObject("error").getString("code"))
        assertEquals("plugin_error", s.run("for(let i=0;i<65;i++) __hostCall('{\"v\":1,\"method\":\"runtime.ping\"}'); return true;").getString("status"))
    }
    @Test fun processDeathLeavesHostAliveAndCanRestart() {
        val hostPid = Process.myPid()
        val firstPid: String
        Session().use { s ->
            s.send(PluginSandboxService.INFO); firstPid = s.result().getString("value")!!
            s.send(PluginSandboxService.STOP)
            assertTrue(s.died.await(5, TimeUnit.SECONDS))
        }
        assertEquals(hostPid, Process.myPid())
        Session().use { s ->
            s.send(PluginSandboxService.INFO); assertNotEquals(firstPid, s.result().getString("value"))
            assertEquals("42", s.run("return 42;").getString("value"))
        }
    }
    @Test fun independentlyBuiltPluginUsesVersionedBridge() = Session().use { s ->
        val context = InstrumentationRegistry.getInstrumentation().context
        val artifact = JSONObject(context.assets.open("synthetic.plugin.json").bufferedReader().use { it.readText() })
        s.send(PluginSandboxService.RUN, artifact.getString("code"), "{\"v\":1,\"id\":\"proof1\",\"method\":\"metadata.search\",\"params\":{\"query\":\"Moon\",\"kind\":\"ebook\"}}")
        val response = s.result()
        assertEquals("ok", response.getString("status"))
        val reply = JSONObject(response.getString("value")!!)
        assertEquals(1, reply.getInt("v")); assertEquals("proof1", reply.getString("id"))
        assertEquals("Moon — synthetic", reply.getJSONObject("result").getJSONArray("items").getJSONObject(0).getString("title"))
    }
    @Test fun serializationAndPromiseWorkCannotEscapeDeadline() = Session().use { s ->
        assertEquals("deadline_exceeded", s.run("return {toJSON() { while(true) {} }};").getString("status"))
        assertEquals("unsupported_capability", s.run("return Promise.resolve(42);").getString("status"))
        assertEquals("plugin_error", s.run("function recur() { return recur(); } return recur();").getString("status"))
        assertEquals("\"你好 📚\"", s.run("return '你好 📚';").getString("value"))
    }
    @Test fun malformedBridgeEnvelopesCannotAliasPing() = Session().use { s ->
        for (request in listOf(
            "{\"v\":1,\"id\":\"a\",\"method\":\"runtime.ping\\u0000native\",\"params\":{}}",
            "{\"v\":1,\"id\":\"a\",\"method\":\"runtime.ping\",\"params\":{},\"extra\":1}",
            "{\"v\":1,\"id\":\"a\",\"method\":\"runtime.ping\",\"params\":{\"path\":\"/data\"}}"
        )) {
            val quoted = JSONObject.quote(request)
            val result = s.run("return JSON.parse(__hostCall($quoted));")
            assertEquals("invalid_request", JSONObject(result.getString("value")!!).getJSONObject("error").getString("code"))
        }
    }
    @Test fun utf8LimitsAndHostQuotaApplyToRealPayloads() = Session().use { s ->
        assertEquals("message_too_large", s.run("return '字'.repeat(24000);").getString("status"))
        assertEquals("plugin_error", s.run("for(let i=0;i<65;i++) __hostCall(JSON.stringify({v:1,id:'q'+i,method:'runtime.ping',params:{}})); return true;").getString("status"))
        assertEquals("true", s.run("return true;").getString("value"))
    }
    @Test fun staleCancellationAndRequestReplayCannotPoisonTheNextRun() = Session().use { s ->
        assertEquals("42", s.run("return 42;").getString("value"))
        val old = s.id
        s.send(PluginSandboxService.RUN, "function multiplexrEntry(){return 0;}", requestId = old)
        assertEquals("invalid_request", s.result().getString("status"))
        s.send(PluginSandboxService.CANCEL, requestId = old)
        assertEquals("43", s.run("return 43;").getString("value"))
    }
}
