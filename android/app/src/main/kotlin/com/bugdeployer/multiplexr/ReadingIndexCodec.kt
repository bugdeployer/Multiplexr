package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject

class ReadingScanConflict : IllegalStateException("Reading library changed while reviewing. Scan again before applying.")

object ReadingIndexCodec {
    const val KEY = "reading:index:v1"
    private val metadataFields = setOf("title", "authors", "description", "language", "identifier", "comicStyle")
    fun entry(entries: JSONArray, collectionId: String, titleId: String): JSONObject = (0 until entries.length()).map { entries.getJSONObject(it) }
        .single { it.getString("collectionId") == collectionId && it.getString("id") == titleId }
    fun empty() = JSONObject().put("version", 1).put("entries", JSONArray()).put("roots", JSONArray()).put("replacements", JSONArray()).put("orders", JSONArray())
    private fun rows(o: JSONObject, key: String, max: Int = 200000): List<JSONObject> {
        val array = o.getJSONArray(key); require(array.length() <= max)
        return (0 until array.length()).map { array.getJSONObject(it) }
    }
    private fun fields(o: JSONObject, names: String) { require(o.keys().asSequence().all { it in names.split(' ') }) }
    private fun text(o: JSONObject, name: String): String {
        val v = o.get(name); require(v is String && v.isNotBlank() && v.length <= 4096); return v
    }
    fun validate(input: JSONObject, catalog: JSONObject): JSONObject {
        fields(input, "version entries roots replacements orders"); require(input.get("version") is Int && input.getInt("version") == 1 && input.toString().length <= 10000000)
        ReadingCatalogCodec.validate(catalog)
        val titles = rows(catalog, "titles").associateBy { it.getString("collectionId") to it.getString("id") }
        val collections = rows(catalog, "collections", 10000).associateBy { it.getString("id") }
        val ids = mutableSetOf<Pair<String, String>>()
        for (e in rows(input, "entries")) {
            fields(e, "collectionId id sourceKey rootUri relativePath fingerprint metadata cover manualFields manualOrder manualCover encoding")
            val key = text(e, "collectionId") to text(e, "id"); require(ids.add(key))
            val title = titles[key] ?: error("Reading index owner is missing.")
            require(title.getJSONObject("source").getString("rootUri") == text(e, "rootUri"))
            text(e, "sourceKey"); text(e, "relativePath"); require(Regex("[a-f0-9]{64}").matches(text(e, "fingerprint")))
            ReadingCatalogCodec.metadata(e.getJSONObject("metadata"))
            val manual = e.getJSONArray("manualFields"); require(manual.length() <= metadataFields.size)
            val values = (0 until manual.length()).map { manual.get(it) }; require(values.toSet().size == values.size && values.all { it is String && it in metadataFields })
            require(e.get("manualOrder") is Boolean)
            require(e.get("manualCover") is Boolean)
            require(e.get("encoding") is String && e.getString("encoding") in setOf("", "utf-8", "utf-16le", "utf-16be", "windows-1252"))
            val cover = e.get("cover"); require(cover is String && cover.length <= 2000000)
            require(cover.isEmpty() || Regex("reading-cover:[a-f0-9]{64}").matches(cover) ||
                cover.startsWith("data:image/jpeg;base64,") && Regex("[A-Za-z0-9+/]*={0,2}").matches(cover.substringAfter(',')))
        }
        val roots = mutableSetOf<Pair<String, String>>()
        for (r in rows(input, "roots", 1000000)) {
            fields(r, "collectionId uri complete"); val owner = text(r, "collectionId"); val uri = text(r, "uri")
            val c = collections[owner] ?: error("Missing root owner.")
            require(roots.add(owner to uri) && rows(c, "roots", 100).any { it.getString("uri") == uri } && r.get("complete") is Boolean)
        }
        for (r in rows(input, "replacements", 10000)) {
            fields(r, "collectionId from to"); val c = collections[text(r, "collectionId")] ?: error("Missing replacement owner.")
            val from = java.net.URI(text(r, "from")); val to = text(r, "to")
            require(from.scheme == "content" && !from.host.isNullOrEmpty() && from.toString() != to && rows(c, "roots", 100).any { it.getString("uri") == to })
        }
        val orderedOwners = mutableSetOf<String>()
        for (o in rows(input, "orders", 10000)) {
            fields(o, "collectionId ids"); val owner = text(o, "collectionId"); require(owner in collections && orderedOwners.add(owner))
            val array = o.getJSONArray("ids"); require(array.length() <= 200000)
            val ids = (0 until array.length()).map { array.get(it) }; require(ids.toSet().size == ids.size)
            require(ids.all { it is String && titles.containsKey(owner to it) })
        }
        return input
    }
    fun withoutCollection(input: JSONObject, owner: String): JSONObject {
        val next = JSONObject(input.toString())
        for (key in listOf("entries", "roots", "replacements", "orders")) next.put(key, JSONArray(rows(next, key, 1000000).filter { it.getString("collectionId") != owner }))
        return next
    }
    fun retain(input: JSONObject, catalog: JSONObject): JSONObject {
        val owners = rows(catalog, "collections", 10000).map { it.getString("id") }.toSet()
        val titles = rows(catalog, "titles").associateBy { it.getString("collectionId") to it.getString("id") }
        val ids = titles.keys
        val next = JSONObject(input.toString())
        next.put("entries", JSONArray(rows(next, "entries").filter { it.getString("collectionId") to it.getString("id") in ids }.map { e ->
            e.put("rootUri", titles[e.getString("collectionId") to e.getString("id")]!!.getJSONObject("source").getString("rootUri"))
        }))
        val roots = rows(catalog, "collections", 10000).associate { c -> c.getString("id") to rows(c, "roots", 100).map { it.getString("uri") }.toSet() }
        for (field in listOf("roots", "replacements", "orders")) next.put(field, JSONArray(rows(next, field, 1000000).filter {
            val owner = it.getString("collectionId")
            owner in owners && (field == "orders" || (if (field == "roots") it.getString("uri") else it.getString("to")) in roots[owner].orEmpty())
        }))
        for (o in rows(next, "orders", 10000)) {
            val a = o.getJSONArray("ids"); val owner = o.getString("collectionId")
            o.put("ids", JSONArray((0 until a.length()).map { a.getString(it) }.filter { owner to it in ids }))
        }
        return validate(next, catalog)
    }
    fun restoredCatalog(input: JSONObject): JSONObject {
        val next = JSONObject(input.toString())
        for (t in rows(next, "titles")) t.getJSONObject("source").put("available", false)
        return ReadingCatalogCodec.validate(next)
    }
    fun restoredIndex(input: JSONObject): JSONObject {
        val next = JSONObject(input.toString())
        for (r in rows(next, "roots", 1000000)) r.put("complete", false)
        return next
    }
    private fun structural(value: Any?): Any? = when(value) {
        null, JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { structural(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { structural(value.get(it)) }
        else -> value
    }
    fun same(a: Any?, b: Any?) = structural(a) == structural(b)
    fun checkCommit(owner: String, current: JSONObject?, currentIndex: JSONObject?, expected: JSONObject?, expectedIndex: JSONObject?, next: JSONObject, index: JSONObject) {
        if (!same(current, expected) || !same(currentIndex, expectedIndex)) throw ReadingScanConflict()
        require(current != null)
        validate(index, next)
        require(same(ReadingCatalogCodec.withoutCollection(current, owner), ReadingCatalogCodec.withoutCollection(next, owner))) { "Scan cannot change another collection." }
        require(same(withoutCollection(currentIndex ?: empty(), owner), withoutCollection(index, owner))) { "Scan cannot change another collection's evidence." }
    }
}
