package com.bugdeployer.multiplexr

import org.json.JSONObject
class MetadataConflict : IllegalStateException("Metadata changed while reviewing. Reopen the match.")
object MetadataPatch {
    private val top = setOf("poster", "backdrop", "seriesBackdrop", "providerId", "metadataSource", "metadataStatus", "seriesId", "episodeId")
    fun apply(current: JSONObject, request: JSONObject): JSONObject {
        val result = JSONObject(current.toString())
        val metadata = result.optJSONObject("metadata") ?: JSONObject()
        val source = result.optString("metadataSource", "filename")
        // Dart projects filename metadata without requiring it to be stored.
        // Materialize only absent values so a selective online match retains
        // the effective title/year/episode fields the user chose to keep.
        if (source == "filename") request.optJSONObject("inferred")?.let { inferred ->
            for (key in inferred.keys()) {
                require(inferred.get(key) is String)
                if (!metadata.has(key) || metadata.optString(key).isEmpty()) metadata.put(key, inferred.get(key))
            }
        }
        val fields = request.getJSONObject("fields")
        val expected = request.getJSONObject("expected")
        for (key in expected.keys()) {
            require(key in top || key in setOf("filename", "relativePath", "rootUri") || key.startsWith("metadata."))
            val actual = when {
                key.startsWith("metadata.") -> metadata.opt(key.removePrefix("metadata."))
                key == "metadataSource" -> source
                key in setOf("metadataStatus", "relativePath", "rootUri") -> result.optString(key, "")
                else -> result.opt(key)
            }
            if (!same(actual, expected.opt(key)) && !(fields.has(key) && same(actual, fields.opt(key)))) throw MetadataConflict()
        }
        for (key in fields.keys()) require(expected.has(key) && (key in top || key.startsWith("metadata.")))
        for (key in fields.keys()) {
            val value = fields.get(key)
            if (key.startsWith("metadata.")) {
                val name = key.removePrefix("metadata.")
                require(name !in setOf("tags", "groupId", "groupOrder", "season", "episode", "structuralSeriesId"))
                require(value is String)
                // Manually corrected series membership remains authoritative.
                if (name == "series" && metadata.optString("groupId").isNotBlank()) continue
                metadata.put(name, value)
            } else {
                if (key in setOf("providerId", "seriesId", "episodeId")) require(value == JSONObject.NULL || value is Number) else require(value == JSONObject.NULL || value is String)
                if (key in setOf("poster", "backdrop", "seriesBackdrop") && !same(result.opt(key), value)) {
                    result.put("local" + key.replaceFirstChar { it.uppercaseChar() }, JSONObject.NULL)
                }
                result.put(key, value)
            }
        }
        // Freeze pre-match ownership; provider IDs and display names may change.
        request.optString("groupAnchor").takeIf { it.isNotBlank() }?.let {
            if (metadata.optString("structuralSeriesId").isBlank()) metadata.put("structuralSeriesId", it)
        }
        return result.put("metadata", metadata)
    }
    private fun same(a: Any?, b: Any?): Boolean = (a == null || a == JSONObject.NULL) && (b == null || b == JSONObject.NULL) || a == b
}
