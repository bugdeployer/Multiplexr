package com.bugdeployer.multiplexr.plugins

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.X509EncodedKeySpec

internal data class PluginPackage(val manifest: JSONObject, val code: String, val publisher: String,
    val digest: String, val origins: Set<String>, val bytes: ByteArray) {
    val id get() = manifest.getString("id")
    val version get() = manifest.getString("version")
    val permissions get() = strings(manifest.getJSONObject("capabilities").getJSONArray("required")) + strings(manifest.getJSONObject("capabilities").getJSONArray("optional"))
    companion object {
        const val MAX_BYTES = 524288
        val capabilities = setOf("runtime.ping", "catalog.read", "catalog.propose", "http.request", "storage.private", "credentials.use", "settings.read", "settings.write", "metadata.provide", "artwork.provide", "sources.discover", "import.parse", "export.create", "library.tools", "events.subscribe", "sessions.control", "media.describe", "ui.present")
        fun parse(bytes: ByteArray): PluginPackage {
            require(bytes.size in 1..MAX_BYTES) { "Package limit exceeded" }
            val outer = objectJson(bytes)
            val outerText=Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString()
            require(Regex("\"(?:format|payload|publicKey|signature)\"\\s*:").findAll(outerText).count()==4) { "Duplicate envelope fields" }
            exact(outer, setOf("format", "payload", "publicKey", "signature"))
            require(outer.getString("format") == "multiplexr-plugin-1") { "Signed installation package required" }
            val payload = PluginEncoding.decode(outer.getString("payload"))
            require(payload.size <= 350000)
            val publicBytes = PluginEncoding.decode(outer.getString("publicKey"))
            require(publicBytes.size <= 256)
            val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(publicBytes)) as ECPublicKey
            require(key.params.order.toString(16) == "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551") { "P-256 key required" }
            val signature = PluginEncoding.decode(outer.getString("signature"))
            require(signature.size <= 80 && Signature.getInstance("SHA256withECDSA").run { initVerify(key); update(payload); verify(signature) }) { "Invalid publisher signature" }
            val body = objectJson(payload)
            require(canonical(body).toByteArray(Charsets.UTF_8).contentEquals(payload)) { "Noncanonical signed payload" }
            exact(body, setOf("manifest", "files", "digests", "networkOrigins", "host"))
            val host = body.getJSONObject("host"); exact(host, setOf("min", "max"))
            require(host.get("min") is Int && host.get("max") is Int && host.getInt("min") == 1 && host.getInt("max") >= 1) { "Incompatible host" }
            val manifest = body.getJSONObject("manifest")
            require(manifest.toString().toByteArray(Charsets.UTF_8).size <= 65536)
            exact(manifest, setOf("id", "name", "version", "protocol", "entry", "capabilities", "contributions"))
            require(manifest.getString("id").matches(Regex("[a-z][a-z0-9_-]*(\\.[a-z][a-z0-9_-]*)+")) && manifest.getString("id").length <= 80)
            require(manifest.getString("name").length in 1..200 && manifest.getString("entry") == "plugin.js")
            version(manifest.getString("version"))
            val protocol = manifest.getJSONObject("protocol"); exact(protocol, setOf("min", "max"))
            require(protocol.get("min") is Int && protocol.get("max") is Int && protocol.getInt("min") == 1 && protocol.getInt("max") >= 1)
            val caps = manifest.getJSONObject("capabilities"); exact(caps, setOf("required", "optional"))
            val required = strings(caps.getJSONArray("required")); val optional = strings(caps.getJSONArray("optional"))
            require(required.size <= 64 && optional.size <= 64 && required.all { it in capabilities } && (required + optional).all { it.matches(Regex("[a-z][a-zA-Z0-9]*(\\.[a-z][a-zA-Z0-9]*)+")) }) { "Unsupported capability" }
            val contributions = manifest.getJSONArray("contributions"); require(contributions.length() <= 64)
            val ids = mutableSetOf<String>()
            val families = setOf("metadata.provider", "artwork.provider", "source.provider", "import.handler", "export.handler", "library.tool", "event.handler", "ui.action", "ui.section", "ui.destination", "settings.section", "session.hook", "media.descriptor")
            for (i in 0 until contributions.length()) {
                val c = contributions.getJSONObject(i)
                require(c.getString("family") in families && c.getString("id").startsWith(manifest.getString("id") + ":") && c.getString("id").substringAfter(":").matches(Regex("[a-z][a-zA-Z0-9_.-]{0,79}")) && ids.add(c.getString("id")) && c.getString("title").length in 1..200)
                require(c.keys().asSequence().all { it in setOf("id", "family", "title", "description", "icon", "schemaVersion", "scopes", "fields", "handler", "events", "engine", "extensions") })
                if(c.has("events")) require(c.getString("family")=="event.handler"&&strings(c.getJSONArray("events")).let { it.isNotEmpty()&&it.size<=2&&it.all { e->e in setOf("org.multiplexr:application.ready","org.multiplexr:library.changed") } })
                if(c.getString("family")=="media.descriptor") {
                    exact(c,setOf("id","family","title","engine","extensions"))
                    val engines=mapOf("reader.epub" to setOf("epub"),"reader.text" to setOf("txt"),"reader.pdf" to setOf("pdf"),"reader.comic" to setOf("cbz","cbr"),"player.audio" to setOf("mp3","m4a","m4b","aac","flac","ogg","oga","opus","wav"),"player.video" to setOf("mp4","mkv","mov","webm","m4v","avi","ts","m2ts","3gp"))
                    val codecs=strings(c.getJSONArray("extensions"));require(codecs.isNotEmpty()&&codecs.size<=16&&engines[c.getString("engine")]?.containsAll(codecs)==true)
                } else if (c.getString("family") != "settings.section") require(c.getString("handler").matches(Regex("[a-z][a-zA-Z0-9]*(\\.[a-z][a-zA-Z0-9]*)+")))
                else validateSettings(c,manifest.getString("id"),ids)
            }
            val files = body.getJSONObject("files"); exact(files, setOf("plugin.js"))
            val digests = body.getJSONObject("digests"); exact(digests, setOf("plugin.js"))
            val code = files.getString("plugin.js"); require(code.toByteArray(Charsets.UTF_8).size in 1..65536)
            require(sha(code.toByteArray(Charsets.UTF_8)) == digests.getString("plugin.js")) { "File digest mismatch" }
            val origins = strings(body.getJSONArray("networkOrigins")); require(origins.size <= 16)
            origins.forEach { origin(it) }
            return PluginPackage(manifest, code, sha(publicBytes), sha(bytes), origins, bytes.copyOf())
        }
        private fun validateSettings(section: JSONObject,owner: String,ids: MutableSet<String>) {
            require(section.get("schemaVersion") is Int && section.getInt("schemaVersion") == 1)
            require(section.getString("description").length in 1..1000 && section.getString("icon") in setOf("settings","book","music","video","palette","extension"))
            val scopes=strings(section.getJSONArray("scopes"));require(scopes.isNotEmpty() && scopes.all { it in setOf("app","collection","group","title") })
            val fields=section.getJSONArray("fields");require(fields.length() in 1..64)
            val byId=mutableMapOf<String,JSONObject>()
            for(i in 0 until fields.length()) {
                val f=fields.getJSONObject(i);val id=f.getString("id")
                require(id.startsWith("$owner:") && id.substringAfter(':').matches(Regex("[a-z][a-zA-Z0-9_.-]{0,79}")) && ids.add(id))
                require(f.keys().asSequence().all { it in setOf("id","type","label","description","accessibleLabel","default","scopes","min","max","maxLength","choices","visibleWhen","enabledWhen") })
                require(f.getString("label").length in 1..200 && f.getString("accessibleLabel").length in 1..200)
                val ownScopes=strings(f.getJSONArray("scopes"));require(ownScopes.isNotEmpty() && scopes.containsAll(ownScopes))
                when(f.getString("type")) {
                    "credential" -> require(!f.has("default"))
                    "number" -> { require(f.get("min") is Number && f.get("max") is Number && f.getDouble("min").isFinite() && f.getDouble("max").isFinite() && f.getDouble("min") <= f.getDouble("max"));settingValue(f,f.get("default")) }
                    "text" -> { require(f.get("maxLength") is Int && f.getInt("maxLength") in 1..4096);settingValue(f,f.get("default")) }
                    "enum","multiSelect" -> { require(strings(f.getJSONArray("choices")).size in 1..100 && strings(f.getJSONArray("choices")).all { it.length in 1..100 });settingValue(f,f.get("default")) }
                    "boolean" -> settingValue(f,f.get("default"))
                    else -> error("Invalid setting type")
                }
                byId[id]=f
            }
            val visiting=mutableSetOf<String>();val visited=mutableSetOf<String>()
            fun visit(id: String) {
                require(id !in visiting) { "Cyclic setting condition" };if(id in visited)return
                visiting.add(id);val f=byId[id] ?: error("Unknown condition field")
                for(key in listOf("visibleWhen","enabledWhen")) if(f.has(key)) {
                    val condition=f.getJSONObject(key);exact(condition,setOf("field","equals"));val dependency=condition.getString("field")
                    val target=byId[dependency] ?: error("Unknown condition field");require(target.getString("type") != "credential")
                    val v=condition.get("equals");require(v is String || v is Boolean || v is Number);settingValue(target,v);visit(dependency)
                }
                visiting.remove(id);visited.add(id)
            }
            byId.keys.forEach { visit(it) }
        }
        fun settingValue(field: JSONObject,value: Any) { require(when(field.getString("type")) {
            "boolean" -> value is Boolean
            "number" -> value is Number && value.toDouble().isFinite() && value.toDouble() >= field.getDouble("min") && value.toDouble() <= field.getDouble("max")
            "text" -> value is String && value.length <= field.getInt("maxLength")
            "enum" -> value is String && value in strings(field.getJSONArray("choices"))
            "multiSelect" -> value is JSONArray && strings(field.getJSONArray("choices")).containsAll(strings(value))
            else -> false
        }) }
        fun version(value: String): List<Int> {
            require(value.length <= 80 && value.matches(Regex("(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)"))) { "Installation versions require release semver" }
            return value.split('.').map { it.toInt() }
        }
        fun compare(a: String, b: String): Int {
            val x = version(a); val y = version(b)
            for (i in 0..2) if (x[i] != y[i]) return x[i].compareTo(y[i])
            return 0
        }
        fun origin(value: String): URI {
            val u = URI(value)
            require(u.scheme == "https" && u.host != null && u.userInfo == null && u.rawQuery == null && u.rawFragment == null && (u.port == -1 || u.port == 443) && u.rawPath.isNullOrEmpty() && value == "https://" + u.host) { "Canonical HTTPS origin required" }
            return u
        }
        fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        fun strings(array: JSONArray): Set<String> {
            val list = (0 until array.length()).map { require(array.get(it) is String); array.getString(it) }
            require(list.size == list.toSet().size)
            return list.toSet()
        }
        fun exact(value: JSONObject, names: Set<String>) { require(value.keys().asSequence().toSet() == names) { "Unexpected package fields" } }
        fun objectJson(bytes: ByteArray): JSONObject {
            val text = Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString()
            var depth = 0; var string = false; var escaped = false
            for (c in text) { if (string) { if (escaped) escaped = false else if (c == '\\') escaped = true else if (c == '"') string = false }
                else if (c == '"') string = true else if (c == '{' || c == '[') { depth++; require(depth <= 24) } else if (c == '}' || c == ']') depth-- }
            require(!string && depth == 0)
            val parser=org.json.JSONTokener(text);val value=parser.nextValue();require(value is JSONObject && parser.nextClean()=='\u0000');return value
        }
        fun canonical(value: Any?): String = when(value) {
            null, JSONObject.NULL -> "null"
            is JSONObject -> value.keys().asSequence().toList().sorted().joinToString(",", "{", "}") { quote(it) + ":" + canonical(value.get(it)) }
            is JSONArray -> (0 until value.length()).joinToString(",", "[", "]") { canonical(value.get(it)) }
            is String -> quote(value)
            is Boolean, is Int, is Long -> value.toString()
            is Number -> { require(value.toDouble().isFinite()); java.math.BigDecimal(value.toString()).stripTrailingZeros().toPlainString() }
            else -> error("Invalid JSON")
        }
        private fun quote(value: String): String = buildString {
            append('"'); for(c in value) when(c) {
                '"' -> append("\\\""); '\\' -> append("\\\\"); '\b' -> append("\\b"); '\u000c' -> append("\\f"); '\n' -> append("\\n"); '\r' -> append("\\r"); '\t' -> append("\\t")
                else -> if(c.code < 32) append("\\u%04x".format(c.code)) else append(c)
            }; append('"')
        }
    }
}
