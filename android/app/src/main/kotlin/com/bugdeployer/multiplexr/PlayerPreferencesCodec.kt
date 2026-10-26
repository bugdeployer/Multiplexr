package com.bugdeployer.multiplexr

import org.json.JSONObject

/** Portable app-owned player controls; no credentials or session state. */
object PlayerPreferencesCodec {
    const val KEY = "settings:players:v1"
    fun validate(value: JSONObject): JSONObject {
        require(value.opt("version") == 1) { "Unsupported player settings version." }
        require(value.keys().asSequence().all { it in setOf("version", "video", "music", "audiobooks") })
        for (kind in listOf("video", "music", "audiobooks")) if (value.has(kind)) {
            val options = value.getJSONObject(kind)
            require(options.keys().asSequence().all { it in setOf("backSeconds", "forwardSeconds", "shuffle", "repeat") })
            for (field in listOf("backSeconds", "forwardSeconds")) if (options.has(field)) {
                val raw = options.get(field)
                require(raw is Int && raw in setOf(5, 10, 15, 20, 30, 60)) { "Invalid skip interval." }
            }
            if (options.has("shuffle")) require(options.get("shuffle") is Boolean)
            if (options.has("repeat")) require(options.get("repeat") in setOf("", "off", "all", "one"))
        }
        return value
    }
}
