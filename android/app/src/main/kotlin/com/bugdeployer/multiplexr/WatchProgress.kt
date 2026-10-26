package com.bugdeployer.multiplexr

import org.json.JSONObject

/** Shared by foreground saves and the media service. Never erase completion on a zero-position save. */
object WatchProgress {
    fun start(asset: JSONObject) { asset.put("hiddenFromContinue", false).put("lastPlayedAt", System.currentTimeMillis()) }
    fun copyHistory(latest: JSONObject, target: JSONObject) {
        for (field in listOf("positionMs", "watched", "hiddenFromContinue", "lastPlayedAt", "completedAt")) {
            if (latest.has(field)) target.put(field, latest.get(field))
        }
    }
    fun apply(asset: JSONObject, position: Long, duration: Long) {
        val total = if (duration > 0) duration else asset.optLong("durationMs")
        val point = position.coerceAtLeast(0)
        if (duration > 0) asset.put("durationMs", duration)
        val previous = asset.optLong("positionMs")
        asset.put("positionMs", point)
        if (point > 0 && point != previous) {
            asset.put("lastPlayedAt", System.currentTimeMillis())
            // 95% avoids marking a movie watched merely on entering long end credits.
            if (total > 0 && point >= total * 0.95) {
                asset.put("watched", true)
                if (asset.optLong("completedAt") == 0L) asset.put("completedAt", System.currentTimeMillis())
            }
        }
    }
}
