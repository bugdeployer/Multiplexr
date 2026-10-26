package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject

/** Device-local browsing state, not portable media/backup data or authorization. */
object BrowseStateCodec {
    private val routes = setOf("collection", "videos", "cinema", "audiobook-space", "audiobook-collection", "music-collection", "music-space")
    fun validate(key: String, value: JSONObject): JSONObject {
        require(key.startsWith("ui:browse:"))
        val scope = JSONArray(key.removePrefix("ui:browse:"))
        require(scope.length() == 2 && scope.get(0) is String && scope.getString(0) in routes)
        require(scope.isNull(1) || scope.get(1) is String)
        require(value.getString("routeId") == scope.getString(0))
        require((if (value.isNull("collectionId")) null else value.get("collectionId")) ==
            (if (scope.isNull(1)) null else scope.get(1)))
        for (field in listOf("query", "sort", "filter", "folder", "tag", "layout")) {
            require(value.get(field) is String && value.getString(field).length <= 4096)
        }
        require(value.get("tab") is Int && value.getInt("tab") in 0..2)
        if (value.has("defaultTab")) require(value.get("defaultTab") is Int && value.getInt("defaultTab") in 0..2)
        val offset = value.get("scrollOffset")
        require(offset is Number && offset.toDouble().isFinite() && offset.toDouble() >= 0 && offset.toDouble() <= 1_000_000_000)
        require(value.toString().length <= 32768)
        return value
    }
}
