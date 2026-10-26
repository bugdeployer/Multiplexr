package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject

/** Music owns its catalog; audiobook chapter/source codecs remain unchanged. */
object MusicCatalogCodec {
    private val text = setOf("title", "artist", "album", "albumArtist", "genre", "cover", "coverSource", "recordingId", "releaseId", "releaseGroupId", "metadataSource")
    private val numbers = setOf("year", "disc", "track", "durationMs")
    private val corrections = setOf("title", "artist", "album", "albumArtist", "genre", "year", "disc", "track", "cover", "coverSource", "albumId")
    fun validate(value: JSONObject): JSONObject {
        require(value.getInt("version") == 1 && value.keys().asSequence().all { it in setOf("version", "tracks", "artwork") })
        val artwork = value.optJSONObject("artwork") ?: JSONObject()
        require(artwork.length() <= 50000)
        for(key in artwork.keys()) require(Regex("[0-9a-f]{64}").matches(key) && artwork.get(key) is String && (artwork.getString(key).startsWith("data:image/") || artwork.getString(key).contains("/files/music-artwork/")))
        val tracks = value.getJSONArray("tracks")
        require(tracks.length() <= 200000)
        val ids = mutableSetOf<String>(); val sources = mutableSetOf<String>()
        for (i in 0 until tracks.length()) {
            val track = tracks.getJSONObject(i)
            require(track.keys().asSequence().all { it in setOf("id", "source", "rootId", "folderId", "albumId", "metadata", "available", "overrides") })
            val id = track.getJSONObject("id")
            require(id.getString("kind") == "music" && id.getString("collectionId").isNotBlank() && id.getString("itemId").isNotBlank())
            require(ids.add(JSONArray(listOf(id.getString("collectionId"), id.getString("itemId"))).toString()))
            require(track.getString("rootId").isNotBlank() && track.getString("folderId").isNotBlank() && track.get("available") is Boolean)
            if (!track.isNull("albumId")) require(track.get("albumId") is String)
            val file = track.getJSONObject("source")
            require(file.getString("id").isNotBlank() && file.getString("uri").startsWith("content://"))
            require(sources.add(JSONArray(listOf(id.getString("collectionId"), file.getString("id"))).toString()))
            for (key in file.keys()) when (key) {
                "id", "uri", "filename", "title", "album", "artist", "author", "genre" -> require(file.get(key) is String)
                "disc", "track", "durationMs" -> integer(file.get(key))
                else -> error("Unknown Music source field.")
            }
            val metadata = track.getJSONObject("metadata")
            require(metadata.getString("title").isNotBlank())
            for (key in metadata.keys()) when (key) {
                in text -> require(metadata.get(key) is String)
                in numbers -> integer(metadata.get(key))
                else -> error("Unknown Music metadata field.")
            }
            for(data in listOf(metadata, track.getJSONObject("overrides"))) {
                val cover = data.optString("cover")
                if(cover.startsWith("artwork:")) require(artwork.has(cover.substring(8)))
            }
            val overrides = track.getJSONObject("overrides")
            for (key in overrides.keys()) {
                require(key in corrections)
                when {
                    key == "albumId" -> require(overrides.isNull(key) || overrides.get(key) is String)
                    key == "year" && overrides.isNull(key) -> Unit
                    key in numbers -> integer(overrides.get(key))
                    else -> require(overrides.get(key) is String)
                }
            }
        }
        return value
    }
    fun packArtwork(input: JSONObject): JSONObject {
        val result=JSONObject(input.toString());val previous=result.optJSONObject("artwork") ?: JSONObject();val images=JSONObject()
        val tracks=result.getJSONArray("tracks")
        for(i in 0 until tracks.length()) for(field in listOf("metadata","overrides")) {
            val data=tracks.getJSONObject(i).getJSONObject(field);var cover=data.optString("cover")
            if(cover.startsWith("artwork:")) cover=previous.getString(cover.substring(8))
            if(cover.startsWith("data:image/")) {
                val hash=java.security.MessageDigest.getInstance("SHA-256").digest(cover.toByteArray(Charsets.UTF_8)).joinToString(""){"%02x".format(it)}
                images.put(hash,cover);data.put("cover","artwork:$hash")
            } else if(data.has("cover")) data.put("cover",cover)
        }
        result.remove("artwork");if(images.length()>0)result.put("artwork",images)
        return validate(result)
    }
    private fun integer(value: Any) { require((value is Int || value is Long) && (value as Number).toLong() >= 0) }
}
