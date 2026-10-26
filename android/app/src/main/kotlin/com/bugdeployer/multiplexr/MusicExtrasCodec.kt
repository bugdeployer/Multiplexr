package com.bugdeployer.multiplexr
import org.json.JSONArray
import org.json.JSONObject

object MusicExtrasCodec {
    fun validate(value: JSONObject, owners: Set<String>? = null): JSONObject {
        require(value.getInt("version") == 1 && value.keys().asSequence().all { it in setOf("version", "titles", "albums", "playlists") })
        val titles = value.getJSONObject("titles"); require(titles.length() <= 200000)
        for (key in titles.keys()) {
            val id = JSONArray(key); require(id.length() == 3 && id.getString(0) == "music" && id.getString(1).isNotBlank() && id.getString(2).isNotBlank())
            require(owners == null || id.getString(1) in owners)
            val flags = titles.getJSONObject(key)
            for (field in flags.keys()) when(field) {
                "favorite" -> require(flags.get(field) is Boolean)
                "addedAt" -> require((flags.get(field) is Int || flags.get(field) is Long) && flags.getLong(field) >= 0)
                "tags" -> { val tags = flags.getJSONArray(field); require(tags.length() <= 200); for (i in 0 until tags.length()) require(tags.get(i) is String && tags.getString(i).length in 1..100) }
                else -> error("Unknown Music flag")
            }
        }
        val albums = value.getJSONObject("albums"); require(albums.length() <= 50000)
        for (key in albums.keys()) {
            val id = JSONArray(key); require(id.length() == 2 && (0..1).all { id.getString(it).isNotBlank() })
            require(owners == null || id.getString(0) in owners)
            val metadata = albums.getJSONObject(key)
            for (field in metadata.keys()) when(field) {
                "title", "artist", "cover", "coverSource", "releaseId", "releaseGroupId", "metadataSource" -> require(metadata.get(field) is String)
                "manualFields" -> { val fields=metadata.getJSONArray(field); for(i in 0 until fields.length()) require(fields.getString(i) in setOf("title","artist","year")) }
                "year" -> require(metadata.isNull(field) || ((metadata.get(field) is Int || metadata.get(field) is Long) && metadata.getLong(field) >= 0))
                else -> error("Unknown album field")
            }
        }
        val playlists = value.getJSONArray("playlists"); require(playlists.length() <= 10000); val ids = mutableSetOf<String>()
        for (i in 0 until playlists.length()) {
            val p = playlists.getJSONObject(i)
            require(p.getInt("version") == 1 && p.getString("id").isNotBlank() && ids.add(p.getString("id")) && p.getString("name").isNotBlank())
            require(p.keys().asSequence().all { it in setOf("version", "id", "name", "collectionId", "entries") })
            val owner = if (p.isNull("collectionId")) null else p.getString("collectionId").also { require(it.isNotBlank()) }
            require(owners == null || owner == null || owner in owners)
            val entries = p.getJSONArray("entries"); require(entries.length() <= 1000); val occurrences = mutableSetOf<String>()
            for (j in 0 until entries.length()) {
                val e = entries.getJSONObject(j)
                require(e.getString("id").isNotBlank() && occurrences.add(e.getString("id")) && e.getString("collectionId").isNotBlank() && e.getString("titleId").isNotBlank())
                require(owner == null || e.getString("collectionId") == owner)
                require(owners == null || e.getString("collectionId") in owners)
            }
        }
        return value
    }
    fun withoutCollection(input: JSONObject, collectionId: String): JSONObject {
        val result = JSONObject(input.toString())
        for (field in listOf("titles", "albums")) {
            val values = result.getJSONObject(field)
            for (key in values.keys().asSequence().toList()) if (JSONArray(key).getString(if (field == "titles") 1 else 0) == collectionId) values.remove(key)
        }
        val playlists = result.getJSONArray("playlists")
        result.put("playlists", JSONArray((0 until playlists.length()).map { playlists.getJSONObject(it) }
            .filter { it.optString("collectionId") != collectionId }.map { p ->
                val entries = p.getJSONArray("entries")
                p.put("entries", JSONArray((0 until entries.length()).map { entries.getJSONObject(it) }.filter { it.getString("collectionId") != collectionId }))
            }))
        return validate(result)
    }
}
