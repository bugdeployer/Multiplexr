package com.bugdeployer.multiplexr.plugins

import android.app.Service
import android.content.Intent
import android.os.*
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Each invocation gets a fresh isolated JS runtime. */
class PluginSandboxService : Service() {
    private val worker = Executors.newSingleThreadExecutor()
    private val watchdog = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val responses = java.util.concurrent.ConcurrentHashMap<Long, java.util.concurrent.CompletableFuture<String>>()
    private var hostSequence = 0L
    private var active = 0L
    private var lastId = 0L
    private val messenger: Messenger = Messenger(object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(msg: Message) {
            if(msg.what == HOST_RESPONSE) { responses.remove(msg.data.getLong("call"))?.complete(msg.data.getString("value") ?: ""); return }
            val reply = msg.replyTo ?: return
            val id = msg.data.getLong("id")
            when (msg.what) {
                INFO -> respond(reply, id, "info", "${Process.myPid()}:${Process.myUid()}")
                CANCEL -> if (id == active) QuickJs.cancel(id)
                STOP -> Process.killProcess(Process.myPid())
                RUN -> {
                    if (active != 0L) { respond(reply, id, "busy", ""); return }
                    if (id <= lastId || id <= 0) { respond(reply, id, "invalid_request", ""); return }
                    val source = msg.data.getByteArray("source")
                    val input = msg.data.getByteArray("input")
                    if (source == null || input == null || source.size > 65536 || input.size > 65536) {
                        respond(reply, id, "message_too_large", ""); return
                    }
                    if (msg.data.getInt("v") != 1) { respond(reply, id, "version_mismatch", ""); return }
                    active = id; lastId = id
                    val mediated = msg.data.getBoolean("mediated")
                    QuickJs.gateway = if(!mediated) null else { request ->
                        val call = ++hostSequence
                        val future = java.util.concurrent.CompletableFuture<String>()
                        responses[call] = future
                        try {
                            reply.send(Message.obtain(null, HOST_CALL).apply { data = Bundle().apply { putLong("id", id); putLong("call", call); putString("request", request) }; replyTo = messenger })
                            future.get(11, TimeUnit.SECONDS)
                        } finally { responses.remove(call) }
                    }
                    val kill = watchdog.schedule({ Process.killProcess(Process.myPid()) }, 15, TimeUnit.SECONDS)
                    worker.execute {
                        val bytes = try { QuickJs.execute(source, input, id) } catch (_: Throwable) { null }
                        kill.cancel(false)
                        main.post {
                            QuickJs.gateway = null
                            active = 0
                            if (bytes == null || bytes.isEmpty()) respond(reply, id, "runtime_failure", "")
                            else respond(reply, id, if (bytes[0].toInt() == 0) "ok" else String(bytes, 1, bytes.size - 1, Charsets.UTF_8),
                                if (bytes[0].toInt() == 0) String(bytes, 1, bytes.size - 1, Charsets.UTF_8) else "")
                        }
                    }
                }
                else -> respond(reply, id, "invalid_request", "")
            }
        }
    })
    private fun respond(to: Messenger, id: Long, status: String, value: String) {
        try { to.send(Message.obtain().apply { data = Bundle().apply {
            putInt("v", 1); putLong("id", id); putString("status", status); putString("value", value)
        } }) } catch (_: RemoteException) { /* Caller went away; no data is committed. */ }
    }
    override fun onBind(intent: Intent): IBinder = messenger.binder
    override fun onDestroy() { worker.shutdownNow(); watchdog.shutdownNow(); super.onDestroy() }
    companion object { const val RUN = 1; const val CANCEL = 2; const val INFO = 3; const val STOP = 4; const val HOST_CALL = 5; const val HOST_RESPONSE = 6 }
}
