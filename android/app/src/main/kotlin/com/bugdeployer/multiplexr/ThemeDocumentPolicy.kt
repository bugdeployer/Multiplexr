package com.bugdeployer.multiplexr

import org.json.JSONObject

/** Shared with Dart schema fixtures: V1 stays 16 KB; V2 JSON packages cap at 4 MB. */
object ThemeDocumentPolicy {
    const val MAX_PACKAGE = 4194304
    const val MAX_INSTALLED = 16777216
    fun validate(text: String) {
        val bytes = text.toByteArray(Charsets.UTF_8).size
        require(bytes <= MAX_PACKAGE) { "Theme exceeds 4 MB." }
        var depth = 0; var quoted = false; var escaped = false
        for (character in text) {
            if (quoted) {
                if (escaped) escaped = false
                else if (character == '\\') escaped = true
                else if (character == '"') quoted = false
            } else when (character) {
                '"' -> quoted = true
                '{', '[' -> { depth++; require(depth <= 12) { "Theme nesting exceeds 12 levels." } }
                '}', ']' -> depth--
            }
        }
        val value = JSONObject(text)
        require(value.optString("format") == "multiplexr-theme")
        when (value.getInt("version")) {
            1 -> require(bytes <= 16384) { "V1 themes exceed 16 KB." }
            2 -> {
                require(value.get("tokens") is JSONObject)
                require((value.optJSONArray("assets")?.length() ?: 0) <= 64)
            }
            else -> error("Unsupported theme version.")
        }
    }
}
