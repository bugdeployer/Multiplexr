package com.bugdeployer.multiplexr.plugins
import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

internal class PluginHost(private val activity: Activity, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newFixedThreadPool(4)
    private val settings = PluginSettings(File(activity.noBackupFilesDir,"plugin-platform/settings"))
    private val credentials = PluginCredentials(File(activity.noBackupFilesDir, "plugin-platform/credentials"))
    private val store = PluginStore(File(activity.noBackupFilesDir, "plugin-platform"), credentials::remove,settings::prepare)
    private val documents=PluginDocuments(activity,worker,store) { epoch }
    private val sessions=PluginSessions(store)
    private val http = PluginHttp()
    private val runtime = PluginRuntimeClient(activity)
    private val calls = java.util.concurrent.ConcurrentHashMap.newKeySet<okhttp3.Call>()
    private val approvals=mutableMapOf<String,Pair<Invocation,Pair<String,Long>>>()
    private val metadataPermits=mutableMapOf<String,Pair<Map<*,*>,Long>>()
    private var picker: MethodChannel.Result? = null
    @Volatile private var active: Invocation? = null
    @Volatile private var closed = false
    @Volatile private var epoch=0L
    private data class Invocation(val id: String, val revision: Long, val token: String)
    init { channel.setMethodCallHandler { call, result ->
        if(closed) { result.error("cancelled", "Plugin host closed", null); return@setMethodCallHandler }
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any,Any>()
        when(call.method) {
            "pick" -> { if(picker != null||documents.busy) result.error("busy", "Picker already open", null) else { picker = result; try { activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE) }, 91) } catch(_: Exception) { picker = null; result.error("picker", "Picker unavailable", null) } } }
            "cancel" -> { cancel(); result.success(null) }
            "importFile","exportFile" -> try { require(picker==null);documents.open(args,call.method=="exportFile",result) } catch(_:Exception) { result.error("document_operation","File picker unavailable or plugin access denied",null) }
            "sessionCandidates","sessionApply" -> try {
                val id=args["id"] as String;val revision=(args["revision"] as Number).toLong()
                if(call.method=="sessionCandidates") result.success(sessions.list(id,revision)) else { sessions.apply(id,revision,args["handle"] as String,org.json.JSONArray(args["commands"] as List<*>));result.success(null) }
            } catch(_: Exception) { result.error("permission_denied","Session changed or access ended",null) }
            "run" -> run(args,result)
            else -> {
                val mutates = call.method in setOf("activate", "enable", "disable", "disableAll", "rollback", "remove", "permissions", "resetSettings", "restoreSettings")
                if(mutates) cancel()
                val requestedEpoch=epoch
                worker.execute { try {
                    fun strings(key: String) = (args[key] as? List<*>)?.map { it as String }?.toSet() ?: emptySet()
                    val value: Any? = when(call.method) {
                        "list" -> store.inventory()
                        "status" -> store.recovery()
                        "stageUrl" -> { val url = args["url"] as String; val origin = java.net.URI(url).let { "https://" + it.host }; val data = http.get(url,setOf(origin),maximum = PluginPackage.MAX_BYTES,register = { require(calls.size < 8);calls.add(it) },unregister = { calls.remove(it) }, check = { check(!closed) }); require(data["status"] == 200); store.stage((data["body"] as String).toByteArray(Charsets.UTF_8)) }
                        "discard" -> { store.discard(args["token"] as String); null }
                        "permissions" -> { store.permissions(args["id"] as String,(args["expected"] as Number).toLong(),strings("permissions"),strings("origins"),strings("collections")); null }
                        "activate" -> { store.activate(args["token"] as String,(args["expected"] as Number).toLong(),strings("permissions"),strings("origins"),strings("collections"),args["publisherReviewed"] == true); null }
                        "enable" -> { store.enabled(args["id"] as String,true); null }
                        "disable" -> { store.enabled(args["id"] as String,false); null }
                        "disableAll" -> { store.disableAll(); null }
                        "rollback" -> { store.rollback(args["id"] as String); null }
                        "remove" -> { val id = args["id"] as String; val old = store.row(id); store.remove(id,args["cleanup"] == true); if(args["cleanup"] == true) settings.clear(id,old.getString("publisher")); null }
                        "restoreSettings" -> { store.restoreSettings(args["id"] as String,(args["revision"] as Number).toLong(),args["publisher"] as String) { p -> settings.restore(p,JSONObject(args["settings"] as Map<*,*>)) };null }
                        "resetSettings" -> { val id=args["id"] as String;val row=store.row(id);store.enabled(id,false);settings.clear(id,row.getString("publisher"));null }
                        "artworkHost" -> {
                            val id=args["id"] as String;val revision=(args["revision"] as Number).toLong();val generation=requestedEpoch
                            val p=store.withCapability(id,revision,"artwork.provide",strings("collections")) { it }
                            fun access() { require(!closed&&epoch==generation);store.packageFor(id,revision) }
                            val content=args["content"] as? String
                            val bytes=if(content!=null) {
                                require(content.length<=32768&&content.startsWith("data:image/png;base64,"));PluginEncoding.decode(content.substringAfter(','))
                            } else {
                                require("http.request" in PluginPackage.strings(store.row(id).getJSONArray("permissions")))
                                val response=http.get(args["url"] as String,PluginPackage.strings(store.row(id).getJSONArray("origins")),maximum=524288,binary=true,register={ require(calls.size<8);calls.add(it) },unregister={calls.remove(it)},check=::access)
                                require(response["status"]==200);PluginEncoding.decode(response["body"] as String)
                            }
                            access();require(bytes.size<=524288)
                            val bounds=android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds=true }
                            android.graphics.BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
                            require(bounds.outMimeType in setOf("image/jpeg","image/png","image/webp")&&bounds.outWidth in 1..8192&&bounds.outHeight in 1..8192&&bounds.outWidth.toLong()*bounds.outHeight<=16777216)
                            val image=com.bugdeployer.multiplexr.AudioArtwork.encode(bytes);access();image
                        }
                        "settingsHost" -> {
                            val method=args["method"] as String
                            require(method in setOf("settings.effective","settings.register","settings.propose","settings.reset","settings.changes"))
                            val params=JSONObject(args["params"] as Map<*, *>)
                            val addresses=params.optJSONArray("lineage") ?: org.json.JSONArray().apply { if(params.has("address")) put(params.getJSONObject("address")) }
                            val collections=(0 until addresses.length()).mapNotNull { addresses.getJSONObject(it).optString("collection").takeIf { c->c.isNotEmpty() } }.toSet()
                            store.withSettings(args["id"] as String,(args["revision"] as Number).toLong(),"settings.read",collections) { p -> settings.call(p,method,params) }
                        }
                        "portable" -> store.portable()
                        "credential" -> { val id = args["id"] as String; val origin = args["origin"] as String; store.withCredential(id,origin) { credentials.save(id,origin,args["value"] as String?) }; null }
                        "metadataPermit" -> { require(epoch==requestedEpoch);metadataPermit(args) }
                        "approve" -> approve(args)
                        "effect" -> effect(args)
                        else -> error("Unsupported operation")
                    }
                    main.post { if(!closed) { if(mutates) channel.invokeMethod("changed",null); result.success(value) } }
                } catch(_: Exception) { main.post { if(!closed) result.error("plugin_operation", "Plugin operation rejected. Check permissions, compatibility and package integrity.", null) } } }
            }
        }
    } }
    private fun run(args: Map<*, *>, result: MethodChannel.Result) { try {
        check(active == null)
        val invocation = Invocation(args["id"] as String,(args["revision"] as Number).toLong(),args["token"] as String)
        require(invocation.token.matches(Regex("[a-f0-9]{64}")))
        val p = store.packageFor(invocation.id,invocation.revision)
        val input = args["input"] as String;
        val envelope = JSONObject(input)
        require(envelope.getInt("v") == 1 && (0 until p.manifest.getJSONArray("contributions").length()).any { p.manifest.getJSONArray("contributions").getJSONObject(it).optString("handler") == envelope.getString("method") })
 require(input.toByteArray(Charsets.UTF_8).size <= 65536)
        active = invocation; store.startInvocation()
        runtime.run(p.code,input,{ request, reply ->
            if(active != invocation) reply(errorReply(request,"cancelled")) else channel.invokeMethod("hostCall",mapOf("token" to invocation.token,"request" to request),object: MethodChannel.Result {
                override fun success(value: Any?) { reply(if(active == invocation && value is String && value.toByteArray().size <= 65536) value else errorReply(request,"cancelled")) }
                override fun error(code: String,message: String?,details: Any?) { reply(errorReply(request,"permission_denied")) }
                override fun notImplemented() { reply(errorReply(request,"unsupported_capability")) }
            })
        }) { value,error ->
            val current = active == invocation; active = null; calls.forEach { it.cancel() }; calls.clear(); store.endInvocation()
            val valid = error == null && value != null && try {
                val response=JSONObject(value)
                PluginPackage.exact(response,setOf("v","id","result"))
                response.get("v") == 1 && response.getString("id") == envelope.getString("id")
            } catch(_: Exception) { false }
            if(valid && current) try { store.success(invocation.id,invocation.revision) } catch(_: Exception) { }
            if((error != null || !valid) && error != "cancelled") try { store.failure(invocation.id) } catch(_: Exception) { }
            channel.invokeMethod("changed",null)
            if(error == null && current) result.success(value) else result.error(error ?: "cancelled","Plugin invocation ended",null)
        }
    } catch(_: Exception) { active = null; result.error("permission_denied","Plugin unavailable or runtime disabled",null) } }
    @Synchronized private fun approve(args: Map<*, *>): String {
        val id=args["id"] as String;val revision=(args["revision"] as Number).toLong();val collection=args["collection"] as String
        require(approvals.size < 64)
        store.withMutation(id,revision,collection) { }
        val token=java.util.UUID.randomUUID().toString();approvals[token]=Invocation(id,revision,"") to (collection to (android.os.SystemClock.elapsedRealtime()+15000))
        return token
    }
    @Synchronized fun withMutation(args: Map<*, *>,operation: () -> Unit) {
        val approval=approvals.remove(args["approval"] as String) ?: error("Confirmation expired")
        require(args["plugin"] == null || args["plugin"] == approval.first.id)
        require(!closed && approval.second.first == args["collection"] && android.os.SystemClock.elapsedRealtime() < approval.second.second)
        store.withMutation(approval.first.id,approval.first.revision,approval.second.first,operation)
    }
    @Synchronized private fun metadataPermit(identity: Map<*,*>): String {
        metadataPermits.entries.removeIf { it.value.second < android.os.SystemClock.elapsedRealtime() }
        require(!closed && metadataPermits.size<64)
        val token=java.util.UUID.randomUUID().toString()
        metadataPermits[token]=identity.toMap() to (android.os.SystemClock.elapsedRealtime()+15000)
        return token
    }
    @Synchronized fun withMetadataCommit(request: Map<*, *>, operation: () -> Unit) {
        val permit=metadataPermits.remove(request["approval"] as String) ?: error("Plugin confirmation expired")
        require(android.os.SystemClock.elapsedRealtime()<permit.second)
        val identity=permit.first
        require(identity.all { (key,value) -> request[key]==value })
        val id=identity["plugin"] as String; val revision=(identity["permissionRevision"] as Number).toLong()
        val collection=identity["collection"] as String
        val contribution=identity["contribution"] as String
        val declaration=store.packageFor(id,revision).manifest.getJSONArray("contributions").let { rows ->
            (0 until rows.length()).map { rows.getJSONObject(it) }.single { it.getString("id")==contribution }
        }
        val permission=when(declaration.getString("family")) {
            "metadata.provider" -> "metadata.provide"
            "library.tool" -> "library.tools"
            "import.handler" -> "import.parse"
            else -> error("Contribution cannot commit metadata")
        }
        store.withCapability(id,revision,permission,setOf(collection)) { p ->
            val row=store.row(id)
            require(!closed && p.publisher==identity["publisher"] && p.version==identity["version"] && row.getString("instance")==identity["instance"])
            operation()
        }
    }
    private fun effect(args: Map<*, *>): Any? {
        val current = active ?: error("No invocation"); require(args["token"] == current.token)
        fun access() { check(active == current && !closed); store.packageFor(current.id,current.revision) }
        access(); val grants = store.row(current.id); val permissions = PluginPackage.strings(grants.getJSONArray("permissions")); val params = args["params"] as Map<*, *>
        return when(args["method"]) {
            "settings.register","settings.effective","settings.changes","settings.propose","settings.reset" -> settings(current,args["method"] as String,params)
            "imports.read" -> { require("import.parse" in permissions);documents.read(current.id,current.revision,params["handle"] as String) }
            "authorize" -> true
            "storage.read" -> { require("storage.private" in permissions); store.privateRead(current.id,(params["schema"] as Number).toInt(),params["key"] as String) }
            "storage.write" -> { privateWrite(current,params); null }
            "http.get" -> { require("http.request" in permissions); val url = params["url"] as String; val origins = PluginPackage.strings(grants.getJSONArray("origins")); val origin = PluginNetworkPolicy.url(url,origins).let { "https://${it.host}" }; val header = if(params["credential"] == true) { require("credentials.use" in permissions); credentials.header(current.id,origin) ?: error("Credential missing") } else null
                http.get(url,origins,header,register = { require(calls.size < 8);calls.add(it) },unregister = { calls.remove(it) },check = ::access) }
            else -> error("Unsupported effect")
        }
    }
    @Synchronized private fun settings(current: Invocation,method: String,params: Map<*, *>): Map<String,Any?> {
        require(active==current&&!closed)
        val addresses=(params["lineage"] as? List<*>)?.map { it as Map<*, *> } ?: listOfNotNull(params["address"] as? Map<*, *>)
        val collections=addresses.mapNotNull { it["collection"] as? String }.toSet()
        return store.withSettings(current.id,current.revision,if(method in setOf("settings.propose","settings.reset")) "settings.write" else "settings.read",collections) { p -> settings.call(p,method,JSONObject(params)) }
    }
    @Synchronized private fun privateWrite(current: Invocation,params: Map<*, *>) {
        require(active == current && !closed); store.packageFor(current.id,current.revision)
        require("storage.private" in PluginPackage.strings(store.row(current.id).getJSONArray("permissions")))
        require(params["schema"] is Int)
        store.privateWrite(current.id,params["schema"] as Int,params["key"] as String,params["value"] as String?)
    }
    fun onResult(code: Int,status: Int,intent: Intent?): Boolean {
        if(documents.onResult(code,status,intent)) return true
        if(code != 91) return false
        val result = picker ?: return true; picker = null; val uri = intent?.data
        if(status != Activity.RESULT_OK || uri == null) { result.success(null); return true }
        worker.execute { try {
            val bytes = activity.contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input); val out = ByteArrayOutputStream(); val buffer = ByteArray(8192)
                while(true) { val n = input.read(buffer); if(n < 0) break; require(out.size() + n <= PluginPackage.MAX_BYTES); out.write(buffer,0,n) }; out.toByteArray()
            }; val review = store.stage(bytes); main.post { if(!closed) result.success(review) }
        } catch(_: Exception) { main.post { if(!closed) result.error("package_invalid","Package signature, format or compatibility check failed",null) } } }
        return true
    }
    @Synchronized fun cancel() { epoch++; metadataPermits.clear(); documents.clear(); sessions.clear(); approvals.clear(); active = null; runtime.cancel(); calls.forEach { it.cancel() }; calls.clear() }
    fun close() { closed = true; cancel(); picker?.success(null); picker = null; channel.setMethodCallHandler(null); worker.shutdownNow() }
    private fun errorReply(request: String,code: String): String = JSONObject().put("v",1).put("id",try { JSONObject(request).opt("id") } catch(_: Exception) { JSONObject.NULL }).put("error",JSONObject().put("code",code)).toString()
}
