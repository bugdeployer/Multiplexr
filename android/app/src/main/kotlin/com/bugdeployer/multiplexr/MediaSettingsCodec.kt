package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject

object MediaSettingsCodec {
    fun validate(key: String, value: JSONObject): JSONObject {
        require(key.startsWith("media:settings:"))
        val identity = JSONArray(key.removePrefix("media:settings:"))
        require(identity.length() == 2 && (0..1).all { identity.get(it) is String && identity.getString(it).isNotBlank() })
        require(value.keys().asSequence().all { it in setOf("openAction", "rate") })
        require(value.optString("openAction", "automatic") in setOf("automatic", "details", "play"))
        if (value.has("rate")) require(value.get("rate") is Number && value.getDouble("rate").let { it == 0.0 || it.isFinite() && it in 0.5..3.0 })
        return value
    }
}
