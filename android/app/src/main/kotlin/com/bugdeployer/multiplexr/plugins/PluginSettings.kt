package com.bugdeployer.multiplexr.plugins
import org.json.JSONObject
import org.json.JSONArray
import java.io.File

/** Non-secret, publisher-owned portable values. No executable code or grants. */
internal class PluginSettings(private val root: File) {
    private fun file(p: PluginPackage)=File(root,PluginPackage.sha((p.id+"\n"+p.publisher).toByteArray(Charsets.UTF_8)))
    private fun document(p: PluginPackage)=file(p).let { if(it.exists()) JSONObject(it.readText()) else JSONObject().put("schema",1).put("revision",0L).put("values",JSONObject()) }
    private fun fields(p: PluginPackage): Map<String,JSONObject> = buildMap {
        val sections=p.manifest.getJSONArray("contributions")
        for(i in 0 until sections.length()) { val section=sections.getJSONObject(i);if(section.getString("family")=="settings.section") { val f=section.getJSONArray("fields");for(j in 0 until f.length()) { val field=f.getJSONObject(j);put(field.getString("id"),field) } } }
    }
    @Synchronized fun prepare(p: PluginPackage) {
        val document=document(p);validatePortable(document,p.id);val fields=fields(p);val values=document.getJSONObject("values")
        for(key in values.keys()) { val address=JSONArray(key);val field=fields[address.getString(3)] ?: continue
            require(field.getString("type")!="credential" && address.getString(0) in PluginPackage.strings(field.getJSONArray("scopes"))) { "Settings migration requires reset" }
            PluginPackage.settingValue(field,values.get(key))
        }
    }
    @Synchronized fun restore(p:PluginPackage,source:JSONObject) {
        val restored=validatePortable(source,p.id);val known=fields(p);val values=restored.getJSONObject("values")
        for(key in values.keys()) {
            val address=JSONArray(key);val field=known[address.getString(3)]?:continue
            require(field.getString("type")!="credential"&&address.getString(0) in PluginPackage.strings(field.getJSONArray("scopes")))
            PluginPackage.settingValue(field,values.get(key))
        }
        val previous=document(p).getLong("revision");require(previous<Long.MAX_VALUE&&restored.getLong("revision")<Long.MAX_VALUE)
        restored.put("revision",maxOf(previous,restored.getLong("revision"))+1)
        PluginStore.atomic(file(p),restored.toString().toByteArray(Charsets.UTF_8))
    }
    @Synchronized fun export(p: PluginPackage): JSONObject = validatePortable(document(p),p.id)
    @Synchronized fun clear(p: PluginPackage) { file(p).delete() }
    @Synchronized fun clear(id: String,publisher: String) { File(root,PluginPackage.sha((id+"\n"+publisher).toByteArray(Charsets.UTF_8))).delete() }
    @Synchronized fun call(p: PluginPackage,method: String,params: JSONObject): Map<String,Any?> {
        val fields=fields(p)
        if(method=="settings.register") return mapOf("sections" to (0 until p.manifest.getJSONArray("contributions").length()).map { p.manifest.getJSONArray("contributions").getJSONObject(it) }.filter { it.getString("family")=="settings.section" }.map { it.getString("id") })
        val document=document(p);validatePortable(document,p.id);val values=document.getJSONObject("values");val revision=document.getLong("revision")
        if(method=="settings.changes") { require(integer(params.get("afterRevision")) && params.getLong("afterRevision") in 0..revision);return mapOf("events" to emptyList<Any>(),"resyncRequired" to true,"revision" to revision) }
        val id=params.getString("id");val field=fields[id] ?: error("Unknown setting")
        require(field.getString("type")!="credential") { "Credentials require host setup" }
        if(method=="settings.effective") {
            val lineage=params.getJSONArray("lineage");require(lineage.length() in 1..4)
            var value=field.get("default");var source:Int?=null;var previous=-1;var collection:String?=null
            for(i in 0 until lineage.length()) {
                val address=lineage.getJSONObject(i);val key=address(address,id);val scope=address.getString("scope");val index=listOf("app","collection","group","title").indexOf(scope)
                require(index>previous);previous=index
                if(scope!="app") { val c=address.getString("collection");require(collection==null||collection==c);collection=c }
                if(scope in PluginPackage.strings(field.getJSONArray("scopes")) && values.has(key)) { value=values.get(key);PluginPackage.settingValue(field,value);source=i }
            }
            return mapOf("value" to plain(value),"sourceIndex" to source,"revision" to revision)
        }
        require(method in setOf("settings.propose","settings.reset"))
        require(integer(params.get("expectedRevision")) && params.getLong("expectedRevision")==revision) { "Setting revision conflict" }
        val address=params.getJSONObject("address");val key=address(address,id)
        require(address.getString("scope") in PluginPackage.strings(field.getJSONArray("scopes")))
        if(method=="settings.reset") values.remove(key) else { val value=params.get("value");PluginPackage.settingValue(field,value);values.put(key,value) }
        require(revision < Long.MAX_VALUE);document.put("revision",revision+1)
        validatePortable(document,p.id);val bytes=document.toString().toByteArray(Charsets.UTF_8);require(bytes.size <= 1048576)
        PluginStore.atomic(file(p),bytes);return mapOf("revision" to revision+1)
    }
    companion object {
        private fun integer(value: Any)=value is Int || value is Long
        private fun plain(value: Any?): Any? = when(value) { JSONObject.NULL,null -> null;is JSONArray -> (0 until value.length()).map { plain(value.get(it)) };else -> value }
        fun address(address: JSONObject,id: String): String {
            val scope=address.getString("scope");require(scope in setOf("app","collection","group","title"))
            PluginPackage.exact(address,when(scope) { "app" -> setOf("scope");"collection" -> setOf("scope","collection");else -> setOf("scope","collection","entity") })
            val collection=address.optString("collection");val entity=address.optString("entity")
            require((scope=="app"||collection.length in 1..2048) && (scope in setOf("app","collection")||entity.length in 1..2048))
            return JSONArray(listOf(scope,collection,entity,id)).toString()
        }
        fun validatePortable(document: JSONObject,owner: String): JSONObject {
            PluginPackage.exact(document,setOf("schema","revision","values"));require(document.get("schema") is Int && document.getInt("schema")==1 && integer(document.get("revision")) && document.getLong("revision")>=0)
            val values=document.getJSONObject("values");require(values.length()<=4096 && document.toString().toByteArray(Charsets.UTF_8).size<=1048576)
            for(key in values.keys()) {
                val a=JSONArray(key);require(a.length()==4 && a.getString(0) in setOf("app","collection","group","title") && a.getString(1).length<=2048 && a.getString(2).length<=2048)
                val scope=a.getString(0);val collection=a.getString(1);val entity=a.getString(2)
                require(if(scope=="app") collection.isEmpty()&&entity.isEmpty() else collection.isNotEmpty()&&(if(scope=="collection") entity.isEmpty() else entity.isNotEmpty()))
                val id=a.getString(3);require(id.startsWith("$owner:")&&id.substringAfter(':').matches(Regex("[a-z][a-zA-Z0-9_.-]{0,79}")))
                val value=values.get(key);require(value is Boolean||value is Number&&value.toDouble().isFinite()||value is String&&value.length<=4096||value is JSONArray&&PluginPackage.strings(value).let { it.size<=100&&it.all { v -> v.length<=100 } })
            }
            return JSONObject(document.toString())
        }
    }
}
