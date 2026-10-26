package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject

object ReadingAnnotationsCodec {
    const val KEY = "reading:annotations:v1"
    private fun items(input: JSONObject): List<JSONObject> { val a = input.getJSONArray("items"); require(a.length() <= 20000); return (0 until a.length()).map { a.getJSONObject(it) } }
    fun validate(input: JSONObject, catalog: JSONObject): JSONObject {
        require(input.keys().asSequence().all { it in setOf("version", "items") } && input.get("version") is Int && input.getInt("version") == 1 && input.toString().length <= 10000000)
        val titles = catalog.getJSONArray("titles").let { a -> (0 until a.length()).map { a.getJSONObject(it) }.associateBy { it.getString("collectionId") to it.getString("id") } }
        val ids = mutableSetOf<String>()
        val fields = "id collectionId titleId sourceId sourceRevision resourceId start end quote before after kind note label color".split(' ').toSet()
        for (a in items(input)) {
            require(a.keys().asSequence().all { it in fields })
            for (field in fields - setOf("start", "end")) require(a.get(field) is String && a.getString(field).length <= 4096)
            for (field in listOf("id", "collectionId", "titleId", "sourceId", "sourceRevision", "resourceId")) require(a.getString(field).isNotBlank())
            require(ids.add(a.getString("id")))
            val title = titles[a.getString("collectionId") to a.getString("titleId")] ?: error("Annotation title is missing.")
            require(title.getString("subtype") == "ebook")
            val start = a.get("start"); val end = a.get("end")
            require((start is Int || start is Long) && (end is Int || end is Long))
            val first = (start as Number).toLong(); val last = (end as Number).toLong()
            require(first >= 0 && last >= first && last <= ReadingTextContent.MAX_CHARACTERS)
            val kind = a.getString("kind"); require(kind in setOf("bookmark", "highlight", "note"))
            require(if (kind == "bookmark") first == last && a.getString("quote").isEmpty() else first < last && last - first == a.getString("quote").length.toLong())
            require(a.getString("color") in setOf("yellow", "green", "blue", "rose"))
            val source = title.getJSONObject("source")
            if (a.getString("sourceId") == source.getString("id") && a.getString("sourceRevision") == source.getString("revision")) {
                val resources = title.getJSONArray("readingOrder")
                require((0 until resources.length()).any { resources.getJSONObject(it).getString("id") == a.getString("resourceId") })
            }
        }
        return input
    }
    fun withoutCollection(input: JSONObject, owner: String) = JSONObject().put("version", 1).put("items", JSONArray(items(input).filter { it.getString("collectionId") != owner }))
    fun retain(input: JSONObject, catalog: JSONObject): JSONObject {
        val a = catalog.getJSONArray("titles"); val ids = (0 until a.length()).map { a.getJSONObject(it).let { it.getString("collectionId") to it.getString("id") } }.toSet()
        return validate(JSONObject().put("version", 1).put("items", JSONArray(items(input).filter { it.getString("collectionId") to it.getString("titleId") in ids })), catalog)
    }
}
