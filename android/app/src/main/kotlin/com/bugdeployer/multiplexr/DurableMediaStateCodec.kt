package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject

/** Portable state has explicit fields; legacy progress can infer its ID from its key. */
object DurableMediaStateCodec {
    private val kinds = setOf("video", "audiobook", "music")
    private fun identity(input: JSONObject): JSONObject {
        require(input.getString("kind") in kinds)
        for (key in listOf("collectionId", "itemId")) require(input.get(key) is String && input.getString(key).isNotBlank())
        return JSONObject().put("kind", input.getString("kind")).put("collectionId", input.getString("collectionId")).put("itemId", input.getString("itemId"))
    }
    private fun number(input: JSONObject, name: String, fallback: Long = 0): Long {
        if (!input.has(name)) return fallback
        val value = input.get(name)
        require((value is Int || value is Long) && (value as Number).toLong() >= 0) { "Invalid $name." }
        return (value as Number).toLong()
    }
    private fun flag(input: JSONObject, name: String): Boolean {
        if (!input.has(name)) return false
        require(input.get(name) is Boolean)
        return input.getBoolean(name)
    }
    fun validate(key: String, input: JSONObject): JSONObject {
        if (key.startsWith("queue:")) {
            val kind = key.removePrefix("queue:"); require(kind in kinds)
            val items = input.getJSONArray("items"); require(items.length() <= 200000)
            val result = JSONArray(); val seen = mutableSetOf<String>()
            for (i in 0 until items.length()) {
                val id = identity(items.getJSONObject(i)); require(id.getString("kind") == kind)
                if (seen.add(id.toString())) result.put(id)
            }
            return JSONObject().put("items", result)
        }
        require(key.startsWith("progress:"))
        val parts = JSONArray(key.removePrefix("progress:"))
        require(parts.length() == 3 && (0..2).all { parts.get(it) is String && parts.getString(it).isNotBlank() })
        val id = identity(JSONObject().put("kind", parts.getString(0)).put("collectionId", parts.getString(1)).put("itemId", parts.getString(2)))
        if (input.has("id")) require(identity(input.getJSONObject("id")).toString() == id.toString()) { "Progress identity does not match its key." }
        val result = JSONObject().put("id", id).put("positionMs", number(input, "positionMs"))
        when (id.getString("kind")) {
            "video" -> result.put("durationMs", number(input, "durationMs")).put("watched", flag(input, "watched"))
            "music" -> { result.put("playCount", number(input, "playCount")); if(input.has("lastPlayedAt")) result.put("lastPlayedAt",number(input,"lastPlayedAt")) }
            "audiobook" -> {
                if (input.has("chapterId")) require(input.get("chapterId") is String)
                result.put("chapterId", input.optString("chapterId")).put("finished", flag(input, "finished"))
                val marks = input.optJSONArray("bookmarks") ?: JSONArray()
                require(!input.has("bookmarks") || input.get("bookmarks") is JSONArray)
                require(marks.length() <= 5000)
                val clean = JSONArray()
                for (i in 0 until marks.length()) {
                    val mark = marks.getJSONObject(i)
                    require(mark.get("chapterId") is String && mark.get("label") is String)
                    clean.put(JSONObject().put("chapterId", mark.getString("chapterId")).put("positionMs", number(mark, "positionMs")).put("label", mark.getString("label")))
                }
                result.put("bookmarks", clean)
                if (input.has("sleep") && !input.isNull("sleep")) {
                    val sleep = input.getJSONObject("sleep"); val mode = sleep.getString("mode")
                    require(mode in setOf("deadline", "endOfChapter"))
                    val timer = JSONObject().put("mode", mode)
                    if (mode == "deadline") { require(sleep.has("deadlineUtcMs")); timer.put("deadlineUtcMs", number(sleep, "deadlineUtcMs")) }
                    result.put("sleep", timer)
                }
            }
        }
        return result
    }

    fun retainBooks(queue: JSONObject, catalog: JSONObject): JSONObject {
        val books = catalog.getJSONArray("books")
        val ids = (0 until books.length()).map { books.getJSONObject(it).getJSONObject("id").let { id -> JSONArray(listOf(id.getString("collectionId"), id.getString("itemId"))).toString() } }.toSet()
        val clean = validate("queue:audiobook", queue).getJSONArray("items")
        val retained = JSONArray()
        for (i in 0 until clean.length()) {
            val id = clean.getJSONObject(i)
            if (JSONArray(listOf(id.getString("collectionId"), id.getString("itemId"))).toString() in ids) retained.put(id)
        }
        return JSONObject().put("items", retained)
    }
}
