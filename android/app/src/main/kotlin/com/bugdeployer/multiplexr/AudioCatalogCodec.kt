package com.bugdeployer.multiplexr

import org.json.JSONObject

/** The initial audio catalog contains books, never video assets or music metadata. */
object AudioCatalogCodec {
    fun validate(value: JSONObject): JSONObject {
        require(value.getInt("version") == 1) { "Unsupported audio library version." }
        require(value.keys().asSequence().all { it in setOf("version", "books", "seriesMetadata") })
        if (value.has("seriesMetadata")) require(value.get("seriesMetadata") is JSONObject)
        value.optJSONObject("seriesMetadata")?.let { groups ->
            require(groups.length() <= 10000)
            for (key in groups.keys()) {
                val group = groups.getJSONObject(key)
                require(group.getString("id") == key && group.getString("collectionId").isNotBlank() && group.getString("title").isNotBlank())
                for (field in group.keys()) require(field in setOf("id", "collectionId", "title", "author", "description", "cover") && group.get(field) is String)
            }
        }
        val books = value.getJSONArray("books")
        require(books.length() <= 10000)
        val identities = mutableSetOf<String>()
        val allUris = mutableSetOf<String>()
        for (i in 0 until books.length()) {
            val book = books.getJSONObject(i)
            require(book.keys().asSequence().all { it in setOf("id", "metadata", "files", "chapters") })
            val id = book.getJSONObject("id")
            require(id.getString("kind") == "audiobook" && id.getString("collectionId").isNotBlank() &&
                id.getString("itemId").isNotBlank() && identities.add(org.json.JSONArray(listOf(id.getString("collectionId"), id.getString("itemId"))).toString()))
            val metadata = book.getJSONObject("metadata")
            require(metadata.getString("title").isNotBlank())
            for (key in metadata.keys()) when (key) {
                "tags" -> { val tags = metadata.getJSONArray(key); require(tags.length() <= 200); for (t in 0 until tags.length()) require(tags.get(t) is String && tags.getString(t).length <= 100) }
                "seriesOrder" -> require(metadata.get(key) is Number && metadata.getDouble(key).isFinite() && metadata.getDouble(key) >= 0)
                else -> require(key in setOf("title", "author", "narrator", "series", "seriesId", "description", "language", "cover", "coverSource", "providerId", "metadataSource", "publisher", "publicationDate") && metadata.get(key) is String)
            }
            val files = book.getJSONArray("files")
            require(files.length() in 1..1000)
            val uris = mutableSetOf<String>()
            val chapterIds = mutableSetOf<String>()
            val sourceFiles = mutableMapOf<String, JSONObject>()
            for (j in 0 until files.length()) {
                val file = files.getJSONObject(j)
                require(file.keys().asSequence().all { it in setOf("id", "uri", "filename", "title", "album", "artist", "author", "genre", "durationMs", "disc", "track") })
                require(file.getString("uri").startsWith("content://") && uris.add(file.getString("uri")) && allUris.add(org.json.JSONArray(listOf(id.getString("collectionId"), file.getString("uri"))).toString()))
                require(file.optString("id", file.getString("uri")).isNotBlank() && chapterIds.add(file.optString("id", file.getString("uri"))))
                sourceFiles[file.optString("id", file.getString("uri"))] = file
                file.getString("filename")
                for (key in listOf("title", "album", "artist", "author", "genre")) if (file.has(key)) require(file.get(key) is String)
                for (key in listOf("durationMs", "disc", "track")) if (file.has(key)) {
                    require((file.get(key) is Int || file.get(key) is Long) && file.getLong(key) >= 0)
                }
            }
            book.optJSONArray("chapters")?.let { chapters ->
                require(chapters.length() in 1..1000)
                val ids = mutableSetOf<String>()
                val previousEnds = mutableMapOf<String, Long?>()
                val ordered = (0 until chapters.length()).map { chapters.getJSONObject(it) }.sortedWith(compareBy<JSONObject> { it.getString("fileId") }.thenBy { it.optLong("startMs", 0) })
                for (c in ordered) {
                    require(c.keys().asSequence().all { it in setOf("id", "fileId", "title", "startMs", "endMs") })
                    require(c.getString("id").isNotBlank() && ids.add(c.getString("id")) && c.getString("title").isNotBlank())
                    val fileId = c.getString("fileId")
                    val source = sourceFiles[fileId] ?: throw IllegalArgumentException("Chapter source is missing.")
                    val start = c.optLong("startMs", 0)
                    val end = if (c.has("endMs")) c.getLong("endMs") else null
                    require(start >= 0 && (end == null || end > start))
                    val duration = source.optLong("durationMs", 0)
                    require(duration == 0L || (start < duration && (end == null || end <= duration)))
                    require(!previousEnds.containsKey(fileId) || (previousEnds[fileId] != null && start >= previousEnds[fileId]!!))
                    previousEnds[fileId] = end
                }
            }
        }
        return value
    }
}
