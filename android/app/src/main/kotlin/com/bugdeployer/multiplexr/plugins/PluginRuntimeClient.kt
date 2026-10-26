package com.bugdeployer.multiplexr.plugins
import android.content.*
import android.os.*
import java.util.concurrent.atomic.AtomicLong

/** One private isolated binding, no source supplied by a script or website. */
internal class PluginRuntimeClient(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val ids = AtomicLong(System.nanoTime())
    private var remote: Messenger? = null
    private var connection: ServiceConnection? = null
    private var finish: ((String?, String?) -> Unit)? = null
    fun run(code: String, input: String, host: (String, (String) -> Unit) -> Unit, done: (String?, String?) -> Unit) {
        check(connection == null) { "Runtime busy" }
        val id = ids.incrementAndGet()
        finish = done
        val inbox = Messenger(object: Handler(Looper.getMainLooper()) {
            override fun handleMessage(message: Message) {
                if(message.data.getLong("id") != id || finish == null) return
                if(message.what == PluginSandboxService.HOST_CALL) {
                    val call = message.data.getLong("call")
                    host(message.data.getString("request") ?: "") { response ->
                        if(finish != null) try { remote?.send(Message.obtain(null, PluginSandboxService.HOST_RESPONSE).apply { data = Bundle().apply { putLong("call", call); putString("value", response) } }) } catch(_: RemoteException) { cancel() }
                    }
                } else {
                    val status = message.data.getString("status")
                    complete(if(status == "ok") message.data.getString("value") else null, if(status == "ok") null else status ?: "runtime_failure")
                }
            }
        })
        val conn = object: ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                remote = Messenger(binder)
                try { remote!!.send(Message.obtain(null, PluginSandboxService.RUN).apply { replyTo = inbox; data = Bundle().apply {
                    putInt("v", 1); putLong("id", id); putBoolean("mediated", true); putByteArray("source", code.toByteArray(Charsets.UTF_8)); putByteArray("input", input.toByteArray(Charsets.UTF_8))
                } }) } catch(_: Exception) { complete(null, "runtime_failure") }
            }
            override fun onServiceDisconnected(name: ComponentName) { complete(null, "runtime_failure") }
            override fun onBindingDied(name: ComponentName) { complete(null, "runtime_failure") }
            override fun onNullBinding(name: ComponentName) { complete(null, "runtime_failure") }
        }
        context.packageManager.setComponentEnabledSetting(ComponentName(context, PluginSandboxService::class.java), android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED, android.content.pm.PackageManager.DONT_KILL_APP)
        connection = conn
        if(!context.bindService(Intent(context, PluginSandboxService::class.java), conn, Context.BIND_AUTO_CREATE)) complete(null, "runtime_unavailable")
        main.postDelayed({ if(connection === conn) complete(null, "deadline_exceeded") }, 16000)
    }
    fun cancel() { complete(null, "cancelled") }
    private fun complete(value: String?, error: String?) {
        val callback = finish ?: return; finish = null
        try { remote?.send(Message.obtain(null, PluginSandboxService.STOP)) } catch(_: Exception) { }
        connection?.let { try { context.unbindService(it) } catch(_: Exception) { } }
        remote = null; connection = null; callback(value,error)
    }
}
