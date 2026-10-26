package com.bugdeployer.multiplexr

import org.json.JSONObject

/** Reconnect only after the whole traversal, when both old and new candidates are unambiguous. */
object ScanIdentity {
    fun reconnect(previous: Map<String, JSONObject>, found: MutableMap<String, JSONObject>, roots: Set<String>, report: (String) -> Unit = {}): Map<String, String> {
        val result = mutableMapOf<String, String>()
        for ((key, scanned) in found.toMap()) {
            if (key in previous || scanned.optLong("size") <= 0) continue
            fun sameFile(other: JSONObject) = other.optString("filename") == scanned.optString("filename") && other.optLong("size") == scanned.optLong("size")
            val candidates = previous.entries.filter { (id, value) ->
                id !in found && id !in result.values && sameFile(value) &&
                    (!value.optBoolean("available", true) || (value.optString("rootUri").isNotEmpty() && value.optString("rootUri") !in roots))
            }
            if (candidates.isEmpty()) continue
            if (found.values.count { sameFile(it) } != 1 || candidates.size != 1) {
                report("${scanned.optString("filename")}: ambiguous reconnect. Existing history was kept; review the matching files.")
                continue
            }
            val old = candidates.single()
            val merged = JSONObject(old.value.toString())
            for (field in listOf("collectionId", "uri", "filename", "size", "modified", "rootUri", "relativePath", "available", "durationMs", "width", "height", "thumbnail", "contentSubtype")) {
                if (scanned.has(field)) merged.put(field, scanned.get(field))
            }
            val from = old.value.optString("contentSubtype")
            val to = scanned.optString("contentSubtype")
            if (from in listOf("movies", "tv") && to in listOf("movies", "tv") && from != to) merged.put("metadataStatus", "review")
            found.remove(key)
            found[old.key] = merged
            result[key] = old.key
        }
        return result
    }

}
