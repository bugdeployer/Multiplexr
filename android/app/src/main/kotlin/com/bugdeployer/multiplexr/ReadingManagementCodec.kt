package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject

object ReadingManagementCodec {
    const val KEY = "reading:management:v1"
    fun empty() = JSONObject().put("version", 1).put("entities", JSONArray()).put("collections", JSONArray()).put("jobs", JSONArray()).put("pageNotes", JSONArray())
    private fun fields(o: JSONObject, names: String) { require(o.keys().asSequence().toSet() == names.split(' ').toSet()) }
    private fun text(o: JSONObject, key: String, empty: Boolean = false, max: Int = 4096): String {
        val v = o.get(key); require(v is String && v.length <= max && (empty || v.isNotBlank())); return v
    }
    private fun rows(o: JSONObject, key: String, max: Int = 200000): List<JSONObject> {
        val a = o.getJSONArray(key); require(a.length() <= max); return (0 until a.length()).map { a.getJSONObject(it) }
    }
    private fun strings(a: JSONArray, max: Int, length: Int = 4096): List<String> {
        require(a.length() <= max); val values = (0 until a.length()).map { val s = a.get(it); require(s is String && s.isNotBlank() && s.length <= length); s }
        require(values.toSet().size == values.size); return values
    }
    fun cover(value: String) {
        require(value.length <= 2000000 && (value.isEmpty() || Regex("reading-cover:[a-f0-9]{64}").matches(value) ||
            value.startsWith("data:image/jpeg;base64,") && Regex("[A-Za-z0-9+/]*={0,2}").matches(value.substringAfter(','))))
    }
    private val metadata = setOf("title", "authors", "description", "language", "identifier", "comicStyle")
    private fun candidate(o: JSONObject) {
        require(o.keys().asSequence().all { it in metadata + setOf("coverUrl", "edition") })
        for (key in o.keys()) if (key == "authors") strings(o.getJSONArray(key), 100) else text(o, key, true)
        if (o.has("comicStyle")) require(o.getString("comicStyle") in setOf("comic", "manga", "manhua", "manhwa"))
        if (o.has("coverUrl")) {
            val uri = java.net.URI(o.getString("coverUrl"))
            require(uri.scheme == "https" && uri.host == "covers.openlibrary.org" && uri.userInfo == null && uri.fragment == null && uri.port in setOf(-1, 443) && Regex("/b/id/[1-9][0-9]*-[SML]\\.jpg").matches(uri.path))
        }
    }
    fun validate(input: JSONObject, catalog: JSONObject): JSONObject {
        require(input.toString().length <= 10000000); fields(input, "version entities collections jobs pageNotes" + (if (input.has("lists")) " lists" else "") + (if (input.has("spaces")) " spaces" else ""))
        require(input.get("version") is Int && input.getInt("version") == 1)
        val owners = rows(catalog, "collections", 10000).map { it.getString("id") }.toSet()
        fun ids(key: String) = rows(catalog, key).map { it.getString("collectionId") to it.getString("id") }.toSet()
        val titles = ids("titles"); val groups = ids("groups"); val seen = mutableSetOf<List<String>>()
        for (e in rows(input, "entities")) {
            fields(e, "collectionId id kind tags manualFields cover coverMode manualCover provider candidateId" + if(e.has("lastOpened")) " lastOpened" else "")
            if (e.has("lastOpened")) require((e.get("lastOpened") is Int || e.get("lastOpened") is Long) && e.getLong("lastOpened") >= 0)
            val owner = text(e, "collectionId"); val id = text(e, "id"); val kind = text(e, "kind")
            require(kind in setOf("title", "group") && owner to id in (if (kind == "title") titles else groups) && seen.add(listOf(owner, id, kind)))
            strings(e.getJSONArray("tags"), 100, 80); require(strings(e.getJSONArray("manualFields"), 6).all { it in metadata })
            cover(text(e, "cover", true, 2000000)); require(e.getString("coverMode") in setOf("fit", "crop") && e.get("manualCover") is Boolean)
            text(e, "provider", true); text(e, "candidateId", true)
        }
        val titleRows = rows(catalog, "titles").associateBy { it.getString("collectionId") to it.getString("id") }
        val listKeys = mutableSetOf<Pair<String, String>>()
        if (input.has("lists")) for (r in rows(input, "lists", 10000)) {
            fields(r, "collectionId id name titles"); val owner = text(r, "collectionId"); val id = text(r, "id"); text(r, "name")
            require(owner in owners && listKeys.add(owner to id) && strings(r.getJSONArray("titles"), 200000).all { owner to it in titles })
        }
        val spaceOwners = mutableSetOf<String>()
        if (input.has("spaces")) for (r in rows(input, "spaces", 10000)) {
            fields(r, "collectionId display"); val owner = text(r, "collectionId")
            require(owner in owners && spaceOwners.add(owner))
            val display = r.getJSONObject("display"); fields(display, "source artwork counts confirmExit hideWatched startTab pins")
            SpacePreferencesCodec.validate(JSONObject().put("ebook", display))
        }
        val noteIds = mutableSetOf<String>()
        for (n in rows(input, "pageNotes", 20000)) {
            fields(n, "id collectionId titleId sourceId sourceRevision pageId pageIndex offset kind note label")
            require(noteIds.add(text(n, "id"))); val owner = text(n, "collectionId"); val id = text(n, "titleId")
            val title = requireNotNull(titleRows[owner to id])
            require(title.getString("subtype") == "comics" || title.getString("format") == "pdf")
            text(n, "sourceId"); text(n, "sourceRevision"); text(n, "pageId"); text(n, "note", true); text(n, "label", true)
            require(n.get("pageIndex") is Int && n.getInt("pageIndex") in 0..199999 && n.get("offset") is Number && n.getDouble("offset").isFinite() && n.getDouble("offset") in 0.0..1.0 && n.getString("kind") in setOf("bookmark", "note"))
            val source = title.getJSONObject("source")
            if (source.getString("revision") == n.getString("sourceRevision") && source.getString("id") == n.getString("sourceId")) {
                val order = title.getJSONArray("readingOrder"); require(n.getInt("pageIndex") < order.length() && order.getJSONObject(n.getInt("pageIndex")).getString("id") == n.getString("pageId"))
            }
        }
        val collectionIds = mutableSetOf<String>()
        for (c in rows(input, "collections", 10000)) {
            fields(c, "collectionId layout sort openAction" + (if(c.has("cardSize")) " cardSize" else "") + (if(c.has("formats")) " formats" else "")); val owner = text(c, "collectionId")
            require(owner in owners && collectionIds.add(owner) && c.getString("layout") in setOf("grid", "list", "compact") && c.getString("sort") in setOf("title", "author", "source") && c.getString("openAction") in setOf("details", "open"))
            if(c.has("cardSize")) require(c.get("cardSize") is Number && c.getDouble("cardSize").isFinite() && c.getDouble("cardSize") in 120.0..280.0)
            if(c.has("formats")) {
                val collection = rows(catalog,"collections").single{it.getString("id")==owner}
                val allowed=if(collection.getString("subtype")=="ebook")setOf("epub","txt","pdf")else setOf("cbz","images")
                val formats=strings(c.getJSONArray("formats"),3);require(formats.isNotEmpty()&&formats.all{it in allowed})
            }
        }
        collectionIds.clear()
        for (j in rows(input, "jobs", 10000)) {
            fields(j, "collectionId provider remaining done total entries"+(if(j.has("implementationEpoch")) " implementationEpoch" else ""));if(j.has("implementationEpoch")) require(j.getString("implementationEpoch").matches(Regex("[a-f0-9]{64}"))); val owner = text(j, "collectionId")
            require(owner in owners && collectionIds.add(owner)); text(j, "provider")
            val remaining = strings(j.getJSONArray("remaining"), 20)
            require(j.get("done") is Int && j.get("total") is Int)
            val done = j.getInt("done"); val total = j.getInt("total")
            require(done in 0..20 && total in done..20 && remaining.size == total - done && remaining.all { owner to it in titles })
            val ids = mutableSetOf<String>()
            for (e in rows(j, "entries", 20)) {
                fields(e, "id status error candidates"); val id = text(e, "id")
                require(owner to id in titles && ids.add(id) && e.getString("status") in setOf("review", "failed", "noMatch", "applied")); text(e, "error", true)
                for (c in rows(e, "candidates", 20)) {
                    if(c.has("provider")) {
                        fields(c,"id values provider entity attribution"+(if(c.has("implementation")) " implementation" else ""))
                        val provider=text(c,"provider");require(text(c,"entity") in setOf("ebook","comic"));text(c,"attribution",true)
                        if(c.has("implementation")) {
                            val identity=c.getJSONObject("implementation");fields(identity,"plugin publisher version contribution instance permissionRevision collection")
                            val plugin=text(identity,"plugin");require(plugin.matches(Regex("[a-z][a-z0-9_-]*(\\.[a-z][a-z0-9_-]*)+")))
                            require(text(identity,"publisher").matches(Regex("[a-f0-9]{64}")))
                            com.bugdeployer.multiplexr.plugins.PluginPackage.version(text(identity,"version"))
                            require(text(identity,"contribution")==provider&&provider.startsWith("$plugin:")&&text(identity,"collection")==owner)
                            require(text(identity,"instance").matches(Regex("[a-f0-9-]{36}"))&&(identity.get("permissionRevision") is Int||identity.get("permissionRevision") is Long)&&identity.getLong("permissionRevision")>0)
                        }
                    } else fields(c,"id values")
                    text(c,"id");candidate(c.getJSONObject("values"))
                }
            }
        }
        return input
    }
    fun withoutCollection(input: JSONObject, owner: String): JSONObject = JSONObject(input.toString()).apply {
        for (field in listOf("entities", "collections", "jobs", "pageNotes", "lists", "spaces")) if (has(field)) put(field, JSONArray(rows(this, field).filter { it.getString("collectionId") != owner }))
    }
    fun retain(input: JSONObject, catalog: JSONObject): JSONObject {
        val owners = rows(catalog, "collections").map { it.getString("id") }.toSet()
        val titles = rows(catalog, "titles").map { it.getString("collectionId") to it.getString("id") }.toSet()
        val groups = rows(catalog, "groups").map { it.getString("collectionId") to it.getString("id") }.toSet()
        val next = JSONObject(input.toString())
        if (next.has("lists")) next.put("lists", JSONArray(rows(next, "lists").filter { it.getString("collectionId") in owners }.map { r ->
            val owner = r.getString("collectionId"); r.put("titles", JSONArray(strings(r.getJSONArray("titles"), 200000).filter { owner to it in titles }))
        }))
        if (next.has("spaces")) next.put("spaces", JSONArray(rows(next, "spaces").filter { it.getString("collectionId") in owners }))
        next.put("entities", JSONArray(rows(next, "entities").filter { it.getString("collectionId") to it.getString("id") in if (it.getString("kind") == "title") titles else groups }))
        next.put("pageNotes", JSONArray(rows(next, "pageNotes", 20000).filter { it.getString("collectionId") to it.getString("titleId") in titles }))
        next.put("collections", JSONArray(rows(next, "collections").filter { it.getString("collectionId") in owners }))
        next.put("jobs", JSONArray(rows(next, "jobs").filter { it.getString("collectionId") in owners }.map { j ->
            val owner = j.getString("collectionId"); val pending = strings(j.getJSONArray("remaining"), 20)
            val remaining = pending.filter { owner to it in titles }
            val entries = rows(j, "entries", 20)
            val removedDone = entries.count { owner to it.getString("id") !in titles && it.getString("id") !in pending }
            val done = maxOf(0, j.getInt("done") - removedDone)
            j.put("entries", JSONArray(entries.filter { owner to it.getString("id") in titles })).put("remaining", JSONArray(remaining)).put("done", done).put("total", done + remaining.size)
        }))
        return validate(next, catalog)
    }
    fun checkCommit(owner: String, current: JSONObject?, index: JSONObject?, management: JSONObject?, request: JSONObject) {
        if (!(ReadingIndexCodec.same(current, request.optJSONObject("expectedCatalog")) && ReadingIndexCodec.same(index, request.optJSONObject("expectedIndex")) && ReadingIndexCodec.same(management, request.optJSONObject("expectedManagement")))) throw ReadingManagementConflict()
        val next = ReadingCatalogCodec.validate(request.getJSONObject("catalog"))
        ReadingIndexCodec.validate(request.getJSONObject("index"), next); validate(request.getJSONObject("management"), next)
        fun other(value: JSONObject?, field: String, collection: Boolean = false): JSONArray = JSONArray(value?.let { (if (it.has(field)) rows(it, field) else emptyList()).filter { r -> r.optString(if (collection) "id" else "collectionId") != owner } }.orEmpty())
        for (field in listOf("collections", "groups", "titles", "memberships", "progress", "settings")) require(ReadingIndexCodec.same(other(current, field, field == "collections"), other(next, field, field == "collections"))) { "Cannot modify another reading collection." }
        for (field in listOf("entries", "roots", "orders", "replacements")) require(ReadingIndexCodec.same(other(index ?: ReadingIndexCodec.empty(), field), other(request.getJSONObject("index"), field)))
        for (field in listOf("entities", "collections", "jobs", "pageNotes", "lists", "spaces")) require(ReadingIndexCodec.same(other(management ?: empty(), field), other(request.getJSONObject("management"), field)))
    }
}

class ReadingManagementConflict : IllegalArgumentException("Reading data changed. Reload and retry.")
