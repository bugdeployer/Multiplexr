package com.bugdeployer.multiplexr
import org.json.JSONArray
import org.json.JSONObject

/** Durable non-secret library state; provider credentials never belong in backups. */
object CollectionStatePolicy {
    fun writable(key: String, deleting: Boolean) = key == "ui:jobs:v1" || key == PlayerPreferencesCodec.KEY || key in setOf(ReadingCatalogCodec.KEY, ReadingAnnotationsCodec.KEY) || key.startsWith("ui:browse:") || key.startsWith("spaces:audiobooks:") || key.startsWith("media:settings:") || key.startsWith("metadata:") || key.startsWith("progress:") || key.startsWith("queue:") || key == "audio:library" || key == "music:library" || key == "music:extras" || key.startsWith("spaces:music:") || key == "spaces:display" || key == "ui:backup" || (key == "music:session" && deleting)

    /** Return a detached value with this owner's shared references removed. */
    fun withoutCollection(key: String, input: JSONObject, collectionId: String): JSONObject? {
        if (ownedBy(key, collectionId)) return null
        val value = JSONObject(input.toString())
        fun pairs(items: JSONArray): JSONArray = JSONArray((0 until items.length()).map { items.getString(it) }
            .filter { runCatching { JSONArray(it).getString(0) != collectionId }.getOrDefault(true) })
        when {
            key == JobReceiptCodec.KEY -> return JobReceiptCodec.withoutCollection(value, collectionId)
            key == ReadingManagementCodec.KEY -> return ReadingManagementCodec.withoutCollection(value, collectionId)
            key == ReadingAnnotationsCodec.KEY -> return ReadingAnnotationsCodec.withoutCollection(value, collectionId)
            key == ReadingIndexCodec.KEY -> return ReadingIndexCodec.withoutCollection(value, collectionId)
            key == ReadingCatalogCodec.KEY -> return ReadingCatalogCodec.withoutCollection(value, collectionId)
            key == "music:extras" -> return MusicExtrasCodec.withoutCollection(value, collectionId)
            key == "music:session" -> return MusicSessionCodec.withoutCollection(value, collectionId)
            key == "music:library" -> {
                val tracks = value.getJSONArray("tracks")
                value.put("tracks", JSONArray((0 until tracks.length()).map { tracks.getJSONObject(it) }
                    .filter { it.getJSONObject("id").getString("collectionId") != collectionId }))
            }
            key.startsWith("queue:") -> {
                val items = value.optJSONArray("items") ?: return value
                value.put("items", JSONArray((0 until items.length()).map { items.getJSONObject(it) }.filter { it.optString("collectionId") != collectionId }))
            }
            key == "legacyVideoQueue" -> value.optJSONArray("items")?.let { value.put("items", pairs(it)) }
            key == "spaces:display" -> for (name in value.keys()) {
                val space = value.optJSONObject(name) ?: continue
                space.optJSONArray("pins")?.let { space.put("pins", pairs(it)) }
            }
            key.startsWith("spaces:audiobooks:") -> value.optJSONArray("pins")?.let { value.put("pins", pairs(it)) }
        }
        return value
    }
    fun exportable(key: String) = key.startsWith(ExtensionFieldsCodec.PREFIX) || key == "plugins:portable" || key == PlayerPreferencesCodec.KEY || key in setOf(ReadingCatalogCodec.KEY, ReadingIndexCodec.KEY, ReadingAnnotationsCodec.KEY, ReadingManagementCodec.KEY) || key.startsWith("progress:") || key.startsWith("queue:") || key.startsWith("media:settings:") || key.startsWith("spaces:audiobooks:") || key.startsWith("spaces:music:") || key in setOf("audio:library", "music:library", "music:session", "music:extras", "spaces:display")
    fun ownedBy(key: String, collectionId: String): Boolean {
        if (key in setOf("metadata:$collectionId", "metadata:audiobooks:$collectionId", "spaces:audiobooks:$collectionId", "spaces:music:$collectionId", "metadata:music:$collectionId")) return true
        return try {
            when {
                key.startsWith(ExtensionFieldsCodec.PREFIX) -> ExtensionFieldsCodec.owner(key) == collectionId
                key.startsWith("ui:browse:") -> JSONArray(key.removePrefix("ui:browse:")).opt(1) == collectionId
                key.startsWith("metadata:series:") -> JSONArray(key.removePrefix("metadata:series:")).optString(0) == collectionId
                key.startsWith("media:settings:") -> JSONArray(key.removePrefix("media:settings:")).optString(0) == collectionId
                key.startsWith("progress:") -> JSONArray(key.removePrefix("progress:")).optString(1) == collectionId
                else -> false
            }
        } catch (_: Exception) { false }
    }
}
