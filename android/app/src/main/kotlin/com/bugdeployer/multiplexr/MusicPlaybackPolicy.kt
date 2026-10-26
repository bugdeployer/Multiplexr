package com.bugdeployer.multiplexr

import org.json.JSONObject

/** Pure policy shared by initial dispatch and queue transitions. */
object MusicPlaybackPolicy {
    fun owner(input: JSONObject, index: Int): JSONObject = input.getJSONArray("files").getJSONObject(index).getJSONObject("owner")
    fun validate(input: JSONObject) {
        require(input.getJSONObject("id").getString("kind") == "music")
        val files = input.getJSONArray("files")
        require(files.length() in 1..1000)
        val ids = mutableSetOf<String>()
        val local = input.optString("scopeCollectionId")
        for (i in 0 until files.length()) {
            val file = files.getJSONObject(i); val owner = owner(input, i)
            require(owner.getString("kind") == "music" && owner.getString("collectionId").isNotBlank() && owner.getString("itemId").isNotBlank())
            require(local.isEmpty() || owner.getString("collectionId") == local)
            require(file.getString("id").isNotBlank() && ids.add(file.getString("id")) && file.getString("uri").startsWith("content://"))
        }
        require(input.optString("repeat", "off") in setOf("off", "all", "one"))
        input.optJSONArray("canonicalEntryIds")?.let { order ->
            val values = (0 until order.length()).map { order.getString(it) }
            require(values.size == ids.size && values.toSet() == ids)
        }
    }
    fun allowed(input: JSONObject, index: Int, collection: JSONObject?, track: JSONObject?): Boolean {
        if (collection == null || track == null || !track.optBoolean("available")) return false
        val owner = owner(input, index)
        if (collection.optString("id") != owner.optString("collectionId") || collection.optString("type") != "audio" || collection.optString("subtype") != "music") return false
        if (track.getJSONObject("id").toString() != owner.toString() &&
            (track.getJSONObject("id").optString("collectionId") != owner.optString("collectionId") || track.getJSONObject("id").optString("itemId") != owner.optString("itemId"))) return false
        if (track.getJSONObject("source").optString("uri") != input.getJSONArray("files").getJSONObject(index).optString("uri")) return false
        return if (input.optString("scopeCollectionId").isEmpty())
            !collection.optBoolean("locked") && collection.optBoolean("includeInGlobalAudio", true)
        else input.getString("scopeCollectionId") == collection.getString("id")
    }
}
