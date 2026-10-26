package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject

/** Persist references, not stale URIs, artwork copies or authorization grants. */
object MusicSessionCodec {
    fun validate(value: JSONObject): JSONObject {
        require(value.getInt("version") == 1 && value.keys().asSequence().all { it in setOf("version", "entries", "traversal", "currentEntryId", "positionMs", "repeat", "scopeCollectionId", "shuffled") })
        if (value.has("shuffled")) require(value.get("shuffled") is Boolean)
        require((value.get("positionMs") is Int || value.get("positionMs") is Long) && value.getLong("positionMs") >= 0)
        require(value.getString("repeat") in setOf("off", "one", "all"))
        val entries = value.getJSONArray("entries"); val ids = mutableSetOf<String>()
        require(entries.length() in 1..1000)
        val local = value.getString("scopeCollectionId")
        for (i in 0 until entries.length()) {
            val entry = entries.getJSONObject(i); val owner = entry.getJSONObject("owner")
            require(entry.keys().asSequence().all { it in setOf("entryId", "owner") })
            require(entry.getString("entryId").isNotBlank() && ids.add(entry.getString("entryId")))
            require(owner.getString("kind") == "music" && owner.getString("collectionId").isNotBlank() && owner.getString("itemId").isNotBlank())
            require(local.isEmpty() || owner.getString("collectionId") == local)
        }
        require(value.getString("currentEntryId") in ids)
        val order = value.getJSONArray("traversal").let { a -> (0 until a.length()).map { a.getString(it) } }
        require(order.size == ids.size && order.toSet() == ids)
        return value
    }
    fun snapshot(input: JSONObject, index: Int, position: Long): JSONObject {
        val files = input.getJSONArray("files")
        val byId = (0 until files.length()).associate { files.getJSONObject(it).getString("id") to files.getJSONObject(it) }
        val canonical = input.optJSONArray("canonicalEntryIds") ?: JSONArray(byId.keys.toList())
        return validate(JSONObject().put("version", 1).put("entries", JSONArray((0 until canonical.length()).map {
            val file = byId.getValue(canonical.getString(it))
            JSONObject().put("entryId", file.getString("id")).put("owner", file.getJSONObject("owner"))
        })).put("traversal", JSONArray(byId.keys.toList())).put("currentEntryId", files.getJSONObject(index).getString("id")).put("positionMs", position)
            .put("repeat", input.optString("repeat", "off")).put("scopeCollectionId", input.optString("scopeCollectionId")).put("shuffled", input.optBoolean("shuffled")))
    }
    fun withoutCollection(input: JSONObject, collectionId: String): JSONObject? {
        validate(input)
        if (input.getString("scopeCollectionId") == collectionId) return null
        val value = JSONObject(input.toString()); val entries = value.getJSONArray("entries")
        val keep = (0 until entries.length()).map { entries.getJSONObject(it) }.filter { it.getJSONObject("owner").getString("collectionId") != collectionId }
        if (keep.isEmpty()) return null
        value.put("entries", JSONArray(keep))
        val keepIds = keep.map { it.getString("entryId") }.toSet()
        val order = value.getJSONArray("traversal")
        value.put("traversal", JSONArray((0 until order.length()).map { order.getString(it) }.filter { it in keepIds }))
        if (keep.none { it.getString("entryId") == value.getString("currentEntryId") }) value.put("currentEntryId", keep.first().getString("entryId")).put("positionMs", 0)
        return validate(value)
    }
}
