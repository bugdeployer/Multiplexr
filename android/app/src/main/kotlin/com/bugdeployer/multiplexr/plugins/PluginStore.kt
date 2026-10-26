package com.bugdeployer.multiplexr.plugins

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

/** Immutable content-addressed packages plus one atomic registry pointer. No
 * package or credential is ever included in portable inventory. */
internal class PluginStore(private val root: File, private val clearCredentials: (String, Set<String>) -> Unit = { _, _ -> }, private val prepareSettings: (PluginPackage) -> Unit = {}) {
    private val packages = File(root, "packages").apply { mkdirs() }
    private val stages = File(root, "staging").apply { mkdirs() }
    private val registry = File(root, "registry.json")
    private val marker = File(root, "running")
    private var state = try { if(registry.exists()) PluginPackage.objectJson(registry.readBytes()).also { require(it.getInt("version") == 1 && it.getJSONObject("plugins").length() <= 128) } else emptyState() } catch(_: Exception) {
        registry.renameTo(File(root,"registry-corrupt-${System.currentTimeMillis()}.json"))
        emptyState().put("recovery", "Registry recovery: packages disabled; private data retained")
    }
    private fun emptyState() = JSONObject().put("version",1).put("plugins",JSONObject()).put("publishers",JSONObject())
    private fun publisher(id: String): String = rows().optJSONObject(id)?.optString("publisher") ?: state.optJSONObject("publishers")?.optString(id)?.takeIf { it.isNotEmpty() } ?: "unassigned"
    @Synchronized fun recovery() = state.optString("recovery")
    init {
        require(state.getInt("version") == 1)
        if (marker.exists()) { disableAll(); marker.delete() }
        stages.listFiles()?.forEach { it.delete() } // Staging never resumes/activates itself.
    }
    private fun rows() = state.getJSONObject("plugins")
    private fun persist(next: JSONObject) { atomic(registry, next.toString().toByteArray(Charsets.UTF_8)); state = next }
    @Synchronized fun inventory(): List<Map<String, Any?>> = rows().keys().asSequence().toList().sorted().map { id -> summary(id) }
    @Synchronized fun row(id: String): JSONObject = JSONObject(rows().getJSONObject(id).toString())
    @Synchronized fun summary(id: String): Map<String, Any?> {
        val r = row(id); val p = try { load(r.getString("active")) } catch(_: Exception) {
            return mapOf("id" to id,"name" to r.optString("name",id),"version" to r.optString("version"),"publisher" to r.optString("publisher"),"enabled" to false,"revision" to r.getLong("revision"),"error" to "Package integrity failed; roll back or remove","rollback" to r.has("previous"),"permissions" to emptyList<String>(),"origins" to emptyList<String>(),"collections" to emptyList<String>(),"handlers" to emptyList<String>())
        }
        return mapOf("instance" to r.getString("instance"), "id" to id, "name" to p.manifest.getString("name"), "version" to p.version,
            "contributions" to (0 until p.manifest.getJSONArray("contributions").length()).map { jsonMap(p.manifest.getJSONArray("contributions").getJSONObject(it)) }, "publisher" to p.publisher, "enabled" to r.getBoolean("enabled"), "error" to r.optString("error"),
            "requestedPermissions" to p.permissions.filter { it in PluginPackage.capabilities }, "requestedOrigins" to p.origins.toList(), "privateBytes" to privateFile(id).length(),
            "permissions" to PluginPackage.strings(r.getJSONArray("permissions")).toList(),
            "origins" to PluginPackage.strings(r.getJSONArray("origins")).toList(),
            "collections" to PluginPackage.strings(r.getJSONArray("collections")).toList(),
            "handlers" to (0 until p.manifest.getJSONArray("contributions").length()).mapNotNull { i -> p.manifest.getJSONArray("contributions").getJSONObject(i).optString("handler").takeIf { it.isNotEmpty() } },
            "rollback" to r.has("previous"), "revision" to r.getLong("revision"))
    }
    @Synchronized fun stage(bytes: ByteArray): Map<String, Any?> {
        val p = PluginPackage.parse(bytes); val token = UUID.randomUUID().toString()
        require((stages.listFiles()?.size ?: 0) < 8) { "Too many staged packages" }
        val old = rows().optJSONObject(p.id)
        val previous = old?.let { load(it.getString("active")) }
        require(previous == null || PluginPackage.compare(p.version, previous.version) > 0) { "An update must increase the version; use explicit rollback" }
        atomic(File(stages, token), bytes)
        return mapOf("token" to token, "id" to p.id, "name" to p.manifest.getString("name"), "version" to p.version,
            "publisher" to p.publisher, "permissions" to p.permissions.filter { it in PluginPackage.capabilities },
            "origins" to p.origins.toList(), "publisherChanged" to (publisher(p.id) != "unassigned" && publisher(p.id) != p.publisher),
            "expanded" to (old != null && (!PluginPackage.strings(old.getJSONArray("permissions")).containsAll(p.permissions.filter { it in PluginPackage.capabilities }) || !PluginPackage.strings(old.getJSONArray("origins")).containsAll(p.origins))),
            "expected" to (old?.getLong("revision") ?: 0L))
    }
    @Synchronized fun activate(token: String, expected: Long, permissions: Set<String>, origins: Set<String>, collections: Set<String>, publisherReviewed: Boolean) {
        require(token.matches(Regex("[a-f0-9-]{36}")))
        val file = File(stages, token); val p = PluginPackage.parse(file.readBytes())
        val old = rows().optJSONObject(p.id)
        require(old != null || rows().length() < 128)
        require((old?.getLong("revision") ?: 0L) == expected) { "Review expired; stage again" }
        require(publisher(p.id) == "unassigned" || publisher(p.id) == p.publisher || publisherReviewed) { "Publisher change requires review" }
        if (old != null) { val prev = load(old.getString("active")); require(prev.publisher == p.publisher || publisherReviewed) { "Publisher change requires review" }; require(PluginPackage.compare(p.version, prev.version) > 0) }
        val required = PluginPackage.strings(p.manifest.getJSONObject("capabilities").getJSONArray("required"))
        require(permissions.containsAll(required) && p.permissions.containsAll(permissions) && PluginPackage.capabilities.containsAll(permissions) && p.origins.containsAll(origins))
        require(collections.size <= 1000 && collections.all { it.length in 1..2048 })
        prepareSettings(p)
        val destination = File(packages, p.digest)
        if (!destination.exists()) atomic(destination, p.bytes)
        val next = JSONObject(state.toString())
        val r = JSONObject().put("instance",UUID.randomUUID().toString()).put("name",p.manifest.getString("name")).put("version",p.version).put("publisher",p.publisher).put("active", p.digest).put("enabled", false).put("revision", expected + 1)
            .put("permissions", JSONArray(permissions.toList())).put("origins", JSONArray(origins.toList()))
            .put("collections", JSONArray(collections.toList())).put("failures", 0).put("error", "")
        if(old != null) {
            if(old.has("working")) r.put("previous",old.getString("working")) else if(old.has("previous")) r.put("previous",old.getString("previous"))
            if(load(old.getString("active")).publisher != p.publisher) clearCredentials(p.id,PluginPackage.strings(old.getJSONArray("origins")))
        }
        next.getJSONObject("plugins").put(p.id, r); val publishers=next.optJSONObject("publishers") ?: JSONObject();require(publishers.has(p.id) || publishers.length() < 4096);publishers.put(p.id,p.publisher);next.put("publishers",publishers); persist(next); file.delete(); collectPackages()
    }
    @Synchronized fun enabled(id: String, enabled: Boolean) = change(id) { r ->
        if(r.has("resetPublisher")) { clearCredentials(id, PluginPackage.strings(r.getJSONArray("resetPublisher"))); r.remove("resetPublisher") }
        val p = load(r.getString("active")); require(!enabled || PluginPackage.strings(r.getJSONArray("permissions")).containsAll(PluginPackage.strings(p.manifest.getJSONObject("capabilities").getJSONArray("required"))))
        r.put("enabled", enabled).put("error", "").put("failures", 0) }
    @Synchronized fun discard(token: String) { require(token.matches(Regex("[a-f0-9-]{36}"))); File(stages,token).delete() }
    @Synchronized fun permissions(id: String,expected: Long,permissions: Set<String>,origins: Set<String>,collections: Set<String>) = change(id) { r ->
        require(r.getLong("revision") == expected); val p=load(r.getString("active"))
        require(p.permissions.containsAll(permissions) && PluginPackage.capabilities.containsAll(permissions) && p.origins.containsAll(origins) && collections.size <= 1000 && collections.all { it.length in 1..2048 })
        r.put("permissions",JSONArray(permissions.toList())).put("origins",JSONArray(origins.toList())).put("collections",JSONArray(collections.toList())).put("enabled",false)
    }
    @Synchronized fun success(id: String,revision: Long) { val next=JSONObject(state.toString());val r=next.getJSONObject("plugins").getJSONObject(id); if(r.getLong("revision") == revision && r.getBoolean("enabled")) { r.put("working",r.getString("active"));persist(next) } }
    @Synchronized fun disableAll() { val next = JSONObject(state.toString()); val rows = next.getJSONObject("plugins"); for(id in rows.keys()) { val r = rows.getJSONObject(id); r.put("enabled", false).put("revision", r.getLong("revision") + 1) }; persist(next) }
    @Synchronized fun rollback(id: String) = change(id) { r ->
        val old = load(r.getString("previous"));prepareSettings(old)
        require(old.id == id && old.publisher == r.getString("publisher")) { "Rollback publisher mismatch; reinstall with review" }
        require(PluginPackage.strings(r.getJSONArray("permissions")).containsAll(PluginPackage.strings(old.manifest.getJSONObject("capabilities").getJSONArray("required"))) && PluginPackage.strings(r.getJSONArray("origins")).containsAll(old.origins)) { "Rollback requires fresh permission review" }
        r.put("previous", r.getString("active")).put("name",old.manifest.getString("name")).put("version",old.version).put("active", old.digest).put("enabled", false).put("failures", 0).put("error", "")
    }
    @Synchronized fun remove(id: String, cleanup: Boolean) { val current=row(id);clearCredentials(id,PluginPackage.strings(current.getJSONArray("origins")));val next = JSONObject(state.toString()); next.getJSONObject("plugins").remove(id); persist(next); if(cleanup) privateFile(id).delete() }
    @Synchronized fun restoreSettings(id:String,revision:Long,publisher:String,operation:(PluginPackage)->Unit) {
        val p=packageFor(id,revision);require(p.publisher==publisher)
        enabled(id,false)
        operation(p)
    }
    @Synchronized fun withCredential(id: String,origin: String,operation: ()->Unit) {
        require(origin in PluginPackage.strings(row(id).getJSONArray("origins")))
        operation()
    }
    @Synchronized fun failure(id: String) = change(id) { r -> val count = r.optInt("failures") + 1; r.put("failures", count).put("error", "Runtime failure"); if(count >= 3) r.put("enabled", false) }
    @Synchronized fun packageFor(id: String, revision: Long): PluginPackage { val r = row(id); require(r.getBoolean("enabled") && r.getLong("revision") == revision) { "Plugin access revoked" }; return load(r.getString("active")) }
    @Synchronized fun startInvocation() { atomic(marker, byteArrayOf(1)) }
    @Synchronized fun endInvocation() { marker.delete() }
    @Synchronized fun portable(): String = JSONObject().put("version", 1).put("inventory", JSONArray(inventory().map { mapOf("id" to it["id"], "version" to it["version"], "publisher" to it["publisher"]) })).toString()
    @Synchronized fun withMutation(id: String,revision: Long,collection: String,operation: () -> Unit) {
        packageFor(id,revision);val r=row(id)
        require("catalog.propose" in PluginPackage.strings(r.getJSONArray("permissions")) && collection in PluginPackage.strings(r.getJSONArray("collections")))
        operation()
    }
    @Synchronized fun <T> withCapability(id: String,revision: Long,permission: String,collections: Set<String>,operation: (PluginPackage)->T): T {
        val p=packageFor(id,revision);val row=row(id)
        require(permission in PluginPackage.strings(row.getJSONArray("permissions")) && PluginPackage.strings(row.getJSONArray("collections")).containsAll(collections))
        return operation(p)
    }
    @Synchronized fun withSettings(id: String,revision: Long,permission: String,collections: Set<String>,operation: (PluginPackage)->Map<String,Any?>): Map<String,Any?> {
        val p=packageFor(id,revision);val row=row(id)
        require(permission in PluginPackage.strings(row.getJSONArray("permissions")) && PluginPackage.strings(row.getJSONArray("collections")).containsAll(collections))
        return operation(p)
    }
    @Synchronized fun privateRead(id: String, schema: Int, key: String): String? { validatePrivate(schema, key); return privateValues(id).optJSONObject(schema.toString())?.optString(key) }
    @Synchronized fun privateWrite(id: String, schema: Int, key: String, value: String?) {
        validatePrivate(schema, key); val data = privateValues(id); val section = data.optJSONObject(schema.toString()) ?: JSONObject()
        if(value == null) section.remove(key) else { require(value.toByteArray(Charsets.UTF_8).size <= 32768); section.put(key, value) }
        data.put(schema.toString(), section); val bytes = data.toString().toByteArray(Charsets.UTF_8); require(bytes.size <= 1048576) { "Plugin storage quota exceeded" }; atomic(privateFile(id), bytes)
    }
    @Synchronized fun clearPrivate(id: String) { privateFile(id).delete() }
    private fun collectPackages() { val keep = rows().keys().asSequence().flatMap { id -> val r = rows().getJSONObject(id); listOfNotNull(r.optString("active"), r.optString("previous"),r.optString("working")).asSequence() }.toSet(); packages.listFiles()?.filter { it.name !in keep }?.forEach { it.delete() } }
    private fun validatePrivate(schema: Int, key: String) { require(schema in 1..100000 && key.matches(Regex("[A-Za-z0-9_.-]{1,80}"))) }
    private fun privateFile(id: String): File { require(id.matches(Regex("[a-z][a-z0-9_.-]{1,79}"))); return File(root, "data-" + PluginPackage.sha((id+"\n"+publisher(id)).toByteArray(Charsets.UTF_8))) }
    private fun privateValues(id: String) = privateFile(id).let { if(it.exists()) JSONObject(it.readText()) else JSONObject() }
    private fun change(id: String, update: (JSONObject) -> Unit) { val next = JSONObject(state.toString()); val r = next.getJSONObject("plugins").getJSONObject(id); update(r); r.put("revision", r.getLong("revision") + 1); persist(next) }
    private fun load(digest: String): PluginPackage { require(digest.matches(Regex("[a-f0-9]{64}"))); val bytes = File(packages, digest).readBytes(); require(PluginPackage.sha(bytes) == digest); return PluginPackage.parse(bytes) }
    companion object {
        private fun jsonMap(value: Any?): Any? = when(value) {
            is JSONObject -> value.keys().asSequence().associateWith { jsonMap(value.get(it)) }
            is JSONArray -> (0 until value.length()).map { jsonMap(value.get(it)) }
            JSONObject.NULL -> null
            else -> value
        }

        fun atomic(file: File, bytes: ByteArray) { file.parentFile!!.mkdirs(); val temp = File(file.parentFile, file.name + ".pending"); FileOutputStream(temp).use { it.write(bytes); it.fd.sync() }; PluginAtomicReplace.move(temp, file) }
    }
}
