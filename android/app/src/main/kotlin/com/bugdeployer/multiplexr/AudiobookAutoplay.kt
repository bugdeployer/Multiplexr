package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject

/** Mirrors the catalog series identity and ordering without crossing collection boundaries. */
object AudiobookAutoplay {
    fun series(book: JSONObject): String {
        val meta = book.getJSONObject("metadata")
        return meta.optString("seriesId").ifBlank { meta.optString("series").trim().lowercase(java.util.Locale.ROOT) }
            .ifBlank { "standalone:" + book.getJSONObject("id").getString("itemId") }
    }
    private fun natural(a: String, b: String): Int {
        val tokens = Regex("[0-9]+|[^0-9]+")
        val x = tokens.findAll(a.lowercase(java.util.Locale.ROOT)).map { it.value }.toList()
        val y = tokens.findAll(b.lowercase(java.util.Locale.ROOT)).map { it.value }.toList()
        for (i in 0 until minOf(x.size, y.size)) {
            val n = x[i].toBigIntegerOrNull(); val m = y[i].toBigIntegerOrNull()
            val order = if (n != null && m != null) n.compareTo(m) else x[i].compareTo(y[i])
            if (order != 0) return order
        }
        return x.size.compareTo(y.size)
    }
    fun next(books: JSONArray, currentId: JSONObject): JSONObject? {
        val collection = currentId.getString("collectionId")
        val current = (0 until books.length()).map { books.getJSONObject(it) }.firstOrNull {
            it.getJSONObject("id").optString("collectionId") == collection && it.getJSONObject("id").optString("itemId") == currentId.getString("itemId")
        } ?: return null
        val candidates = (0 until books.length()).map { books.getJSONObject(it) }.filter {
            it.getJSONObject("id").optString("collectionId") == collection && series(it) == series(current)
        }.sortedWith { a, b ->
            fun order(v: JSONObject) = v.getJSONObject("metadata").optDouble("seriesOrder", 0.0).let { if (it == 0.0) Double.POSITIVE_INFINITY else it }
            val comparison = order(a).compareTo(order(b))
            if (comparison != 0) comparison else natural(a.getJSONObject("metadata").getString("title"), b.getJSONObject("metadata").getString("title"))
        }
        val index = candidates.indexOf(current)
        return candidates.getOrNull(index + 1)
    }
    fun request(book: JSONObject, progress: JSONObject? = null): JSONObject {
        val metadata = book.getJSONObject("metadata")
        val files = book.getJSONArray("files")
        val chapters = book.getJSONArray("chapters")
        val queue = JSONArray()
        for (i in 0 until chapters.length()) {
            val chapter = chapters.getJSONObject(i)
            val file = (0 until files.length()).map { files.getJSONObject(it) }.first { it.optString("id", it.getString("uri")) == chapter.getString("fileId") }
            queue.put(JSONObject(chapter.toString()).put("uri", file.getString("uri")))
        }
        val id = book.getJSONObject("id")
        val savedId = progress?.optJSONObject("id")
        val belongs = savedId != null && listOf("kind", "collectionId", "itemId").all { savedId.optString(it) == id.optString(it) }
        val resume = if (belongs && progress?.optBoolean("finished") != true) (0 until queue.length()).firstOrNull { queue.getJSONObject(it).getString("id") == progress?.optString("chapterId") } else null
        return JSONObject().put("id", id).put("title", metadata.getString("title"))
            .put("creator", metadata.optString("author")).put("files", queue).put("index", resume ?: 0).put("positionMs", if (resume != null) progress!!.optLong("positionMs").coerceAtLeast(0) else 0)
    }
}
