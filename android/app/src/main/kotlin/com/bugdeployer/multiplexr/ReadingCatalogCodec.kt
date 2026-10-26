package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI

/** Exact reading v1 schema. This namespace never enters legacy collection/audio codecs. */
object ReadingCatalogCodec {
    const val KEY = "reading:library:v1"
    private fun fields(o: JSONObject, names: String) {
        val allowed = names.split(' ').toSet()
        require(o.keys().asSequence().all { it in allowed }) { "Unknown reading field." }
    }
    private fun text(o: JSONObject, key: String, empty: Boolean = false): String {
        val v = o.get(key); require(v is String && v.length <= 4096 && (empty || v.isNotBlank()))
        return v
    }
    private fun flag(o: JSONObject, key: String) { require(o.get(key) is Boolean) }
    private fun integer(o: JSONObject, key: String, max: Int = 200000): Int {
        val v = o.get(key); require((v is Int || v is Long) && (v as Number).toLong() in 0..max.toLong())
        return (v as Number).toInt()
    }
    private fun fraction(o: JSONObject, key: String) = range(o, key, 0.0, 1.0)
    private fun range(o: JSONObject, key: String, min: Double, max: Double) {
        val n = o.get(key); require(n is Number && n.toDouble().isFinite() && n.toDouble() in min..max)
    }
    private fun list(o: JSONObject, key: String, max: Int = 200000): List<JSONObject> {
        val a = o.getJSONArray(key); require(a.length() <= max)
        return (0 until a.length()).map { a.getJSONObject(it) }
    }
    private fun subtype(o: JSONObject) = text(o, "subtype").also { require(it in setOf("ebook", "comics")) }
    private fun id(o: JSONObject) = text(o, "collectionId") to text(o, "id")
    private fun uri(value: String): URI {
        require(!Regex("[\\x00-\\x20<>\"{}|\\\\^`]").containsMatchIn(value))
        return URI(value)
    }
    private fun content(value: String) {
        val uri = uri(value)
        require(uri.scheme == "content" && Regex("^[A-Za-z0-9._-]+$").matches(uri.rawAuthority ?: ""))
    }
    internal fun metadata(o: JSONObject) {
        fields(o, "title authors description language identifier comicStyle")
        text(o, "title"); for (key in listOf("description", "language", "identifier")) text(o, key, true)
        val authors = o.getJSONArray("authors"); require(authors.length() <= 100)
        for (i in 0 until authors.length()) { val a = authors.get(i); require(a is String && a.isNotBlank() && a.length <= 4096) }
        if (o.has("comicStyle")) require(text(o, "comicStyle") in setOf("comic", "manga", "manhua", "manhwa"))
    }
    private fun location(o: JSONObject, text: Boolean) {
        require(integer(o, "version") == 1)
        if (text) {
            fields(o, "version kind resourceId locatorType locator progression before highlight after")
            require(text(o, "kind") == "text"); text(o, "resourceId"); fraction(o, "progression")
            for (key in listOf("before", "highlight", "after")) text(o, key, true)
            val locator = text(o, "locator")
            when (text(o, "locatorType")) {
                "textOffset" -> require(Regex("^(0|[1-9][0-9]{0,14})$").matches(locator))
                "epubCfi" -> require(locator.startsWith("epubcfi(") && locator.endsWith(")"))
                "cssSelector" -> Unit
                else -> error("Unknown text locator.")
            }
        } else {
            fields(o, "version kind pageId pageIndex offset")
            require(text(o, "kind") == "page"); text(o, "pageId"); integer(o, "pageIndex", 199999); fraction(o, "offset")
        }
    }
    private fun preferences(o: JSONObject, subtype: String) {
        val common = setOf("palette")
        val allowed = common + if (subtype == "ebook") setOf("reader_epub", "reader_txt", "reader_pdf", "pdfMode", "pdfFit", "fontSize", "lineHeight", "margin", "textMode", "fontAsset", "fontWeight", "paragraphSpacing", "alignment", "readerForeground", "readerBackground") else setOf("comicMode", "direction", "fit", "cropBorders", "volumeKeys", "tapZones", "spreads", "readerForeground", "readerBackground")
        require(o.keys().asSequence().all { it in allowed })
        for (key in o.keys()) when (key) {
            "reader_epub", "reader_txt", "reader_pdf" -> { val v = text(o, key); require(v in setOf("internal", "ask") || Regex("^app:[a-zA-Z0-9_]+(?:\\.[a-zA-Z0-9_]+)+$").matches(v)) }
            "fontSize" -> range(o, key, 8.0, 72.0)
            "lineHeight" -> range(o, key, 1.0, 3.0)
            "margin" -> range(o, key, 0.0, 96.0)
            "paragraphSpacing" -> range(o, key, 0.0, 64.0)
            "fontWeight" -> { val v = o.get(key); require((v is Int || v is Long) && (v as Number).toLong() in 100L..900L && v.toLong() % 100 == 0L) }
            "alignment" -> require(text(o, key) in setOf("start", "justify", "center"))
            "readerForeground", "readerBackground" -> { val v = o.get(key); require((v is Int || v is Long) && (v as Number).toLong() in 0xff000000L..0xffffffffL) }
            "pdfMode", "textMode" -> require(text(o, key) in setOf("paged", "scroll"))
            "cropBorders", "volumeKeys" -> flag(o, key)
            "tapZones" -> require(text(o, key) in setOf("standard", "inverted", "off"))
            "spreads" -> require(text(o, key) in setOf("single", "landscape"))
            "comicMode" -> require(text(o, key) in setOf("paged", "webtoon"))
            "direction" -> require(text(o, key) in setOf("ltr", "rtl"))
            "pdfFit", "fit" -> require(text(o, key) in setOf("page", "width"))
            "palette" -> require(text(o, key) in setOf("system", "day", "sepia", "dark", "custom"))
            "fontAsset" -> require(Regex("^[a-zA-Z0-9_-]{1,128}$").matches(text(o, key)))
        }
    }
    fun validate(input: JSONObject): JSONObject {
        require(input.toString().length <= 10_000_000) { "Reading snapshot exceeds storage limit." }
        fields(input, "version collections groups titles memberships progress settings")
        require(integer(input, "version") == 1)
        val collections = list(input, "collections", 10000)
        val owners = linkedMapOf<String, JSONObject>()
        for (c in collections) {
            fields(c, "id name subtype locked includeInGlobal roots")
            val key = text(c, "id"); require(owners.put(key, c) == null)
            text(c, "name"); subtype(c); flag(c, "locked"); flag(c, "includeInGlobal")
            val roots = mutableSetOf<String>()
            for (r in list(c, "roots", 100)) {
                fields(r, "uri name"); val uri = text(r, "uri"); content(uri); text(r, "name", true); require(roots.add(uri))
            }
        }
        val groups = linkedMapOf<Pair<String, String>, JSONObject>()
        for (g in list(input, "groups")) {
            fields(g, "collectionId id subtype metadata")
            val key = id(g); require(groups.put(key, g) == null)
            require(owners[key.first]?.getString("subtype") == subtype(g)); metadata(g.getJSONObject("metadata"))
        }
        val titles = linkedMapOf<Pair<String, String>, JSONObject>()
        val sourceIds = mutableSetOf<Pair<String, String>>()
        for (t in list(input, "titles")) {
            fields(t, "collectionId id subtype role format metadata source readingOrder")
            val key = id(t); require(titles.put(key, t) == null)
            val type = subtype(t); val owner = owners[key.first] ?: error("Missing reading collection.")
            require(owner.getString("subtype") == type)
            val role = text(t, "role"); require(role in setOf("publication", "volume", "issue", "chapter"))
            val format = text(t, "format"); require(format in if (type == "ebook") setOf("epub", "txt", "pdf") else setOf("cbz", "images"))
            metadata(t.getJSONObject("metadata"))
            if (type == "ebook") require(role != "issue" && !t.getJSONObject("metadata").has("comicStyle"))
            val source = t.getJSONObject("source"); fields(source, "id uri name rootUri revision available")
            require(sourceIds.add(key.first to text(source, "id")))
            content(text(source, "uri")); text(source, "name", true); text(source, "revision"); flag(source, "available")
            val root = text(source, "rootUri"); require(list(owner, "roots", 100).any { it.getString("uri") == root })
            val resources = list(t, "readingOrder"); require(resources.isNotEmpty())
            val ids = mutableSetOf<String>(); val hrefs = mutableSetOf<String>()
            for (r in resources) {
                fields(r, "id href label"); require(ids.add(text(r, "id"))); text(r, "label", true)
                val href = text(r, "href"); require(hrefs.add(href))
                val uri = uri(href)
                require(!uri.isAbsolute && uri.rawAuthority == null && uri.rawQuery == null && uri.rawFragment == null &&
                    !uri.path.startsWith("/") && !uri.path.contains('\\') && !uri.path.contains('\u0000') && uri.path.split('/').none { it == ".." })
            }
        }
        val parents = mutableSetOf<Pair<String, String>>()
        for (m in list(input, "memberships")) {
            fields(m, "collectionId parentId titleId order")
            val owner = text(m, "collectionId"); val title = owner to text(m, "titleId")
            require(groups.containsKey(owner to text(m, "parentId")) && titles.containsKey(title) && parents.add(title))
            integer(m, "order")
        }
        require(titles.all { (id, t) -> t.getString("subtype") != "comics" || id in parents })
        val progressIds = mutableSetOf<Pair<String, String>>()
        for (p in list(input, "progress")) {
            fields(p, "collectionId id sourceId sourceRevision location finished")
            val key = id(p); require(progressIds.add(key)); val title = titles[key] ?: error("Missing reading title.")
            val sourceId = text(p, "sourceId"); val revision = text(p, "sourceRevision"); flag(p, "finished")
            val loc = p.getJSONObject("location"); val isText = title.getString("format") in setOf("epub", "txt"); location(loc, isText)
            val source = title.getJSONObject("source")
            if (sourceId == source.getString("id") && revision == source.getString("revision")) {
                val resources = list(title, "readingOrder")
                if (isText) require(resources.any { it.getString("id") == loc.getString("resourceId") })
                else { val index = loc.getInt("pageIndex"); require(index < resources.size && resources[index].getString("id") == loc.getString("pageId")) }
            }
        }
        val settingIds = mutableSetOf<List<String?>>()
        for (s in list(input, "settings")) {
            fields(s, "scope subtype collectionId entityId values")
            val type = subtype(s); val scope = text(s, "scope"); require(scope in setOf("app", "collection", "group", "title"))
            val owner = if (s.has("collectionId")) text(s, "collectionId") else null
            val entity = if (s.has("entityId")) text(s, "entityId") else null
            require(settingIds.add(listOf(type, scope, owner, entity)))
            if (scope == "app") require(owner == null && entity == null)
            else {
                require(owner != null && owners[owner]?.getString("subtype") == type)
                when (scope) {
                    "collection" -> require(entity == null)
                    "group" -> require(entity != null && groups.containsKey(owner to entity))
                    "title" -> require(entity != null && titles.containsKey(owner to entity))
                }
            }
            preferences(s.getJSONObject("values"), type)
        }
        return input
    }

    fun requireSeparateOwners(input: JSONObject, legacyIds: Set<String>) {
        require(list(input, "collections", 10000).none { it.getString("id") in legacyIds }) { "Reading and legacy collection identities collide." }
    }

    fun withoutCollection(input: JSONObject, collectionId: String): JSONObject {
        val next = JSONObject(input.toString())
        for (field in listOf("collections", "groups", "titles", "memberships", "progress", "settings")) {
            val rows = list(next, field)
            next.put(field, JSONArray(rows.filter {
                if (field == "collections") it.getString("id") != collectionId
                else it.optString("collectionId") != collectionId
            }))
        }
        return validate(next)
    }
}
