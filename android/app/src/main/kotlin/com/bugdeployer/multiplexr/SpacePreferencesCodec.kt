package com.bugdeployer.multiplexr

import org.json.JSONObject
import org.json.JSONArray

object SpacePreferencesCodec {
    fun validate(value: JSONObject): JSONObject {
        require(value.keys().asSequence().all { it in setOf("cinema", "videos", "audiobooks", "music", "ebook", "comics") })
        for (name in value.keys()) {
            val space = value.getJSONObject(name)
            require(space.keys().asSequence().all { it in setOf("source", "artwork", "counts", "confirmExit", "hideWatched", "startTab", "pins") })
            for (flag in listOf("artwork", "counts", "confirmExit", "hideWatched")) if (space.has(flag)) require(space.get(flag) is Boolean)
            if (space.has("source")) require(space.getString("source") in setOf("recent", "favorites", "progress", "pinned"))
            if (space.has("startTab")) require(space.get("startTab") is Int && space.getInt("startTab") in 0..2)
            if (space.has("pins")) {
                val pins = space.getJSONArray("pins"); require(pins.length() <= 3)
                val seen = mutableSetOf<String>()
                for (i in 0 until pins.length()) {
                    val key = pins.getString(i); require(key.length <= 4000 && seen.add(key))
                    val pair = JSONArray(key); require(pair.length() == 2 && pair.get(0) is String && pair.get(1) is String && pair.getString(0).isNotEmpty() && pair.getString(1).isNotEmpty())
                }
            }
        }
        return value
    }
}
