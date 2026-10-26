package com.bugdeployer.multiplexr
import org.json.JSONObject

object AssetFlags {
    fun apply(asset: JSONObject, action: String, enabled: Boolean): Boolean {
        require(action in listOf("favorite", "watchLater", "watched", "clearMatches", "hideContinue"))
        if (action == "clearMatches") {
            if (asset.optString("metadataSource") == "manual") return false
            for (field in listOf("metadata", "providerId", "seriesId", "episodeId", "poster", "backdrop", "localPoster", "localBackdrop", "seriesBackdrop", "localSeriesBackdrop")) asset.remove(field)
            asset.put("metadataSource", "filename").put("metadataStatus", "")
        } else if (action == "hideContinue") asset.put("hiddenFromContinue", enabled)
        else asset.put(action, enabled)
        if (action == "watched") asset.put("positionMs", 0).put("completedAt", if (enabled) System.currentTimeMillis() else 0L).put("hiddenFromContinue", false)
        return true
    }
}
