package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject

/** Explicit fields prevent accidental credential/private-cache export. No app preferences are included. */
object BackupCodec {
    private val collectionFields = "id name type subtype view player roots extensions locked includeInGlobalCinema includeInGlobalVideos includeInGlobalAudio autoplayNext openAction audioRate allowFolders sort filter cardSize folder".split(' ')
    private val assetFields = "id collectionId uri filename metadata size modified durationMs width height positionMs favorite watchLater seriesId seriesBackdrop episodeId watched hiddenFromContinue lastPlayedAt completedAt rootUri relativePath metadataStatus poster backdrop providerId metadataSource addedAt contentSubtype".split(' ')
    private fun pick(value: JSONObject, fields: List<String>): JSONObject = JSONObject().also { result -> for (key in fields) if (value.has(key)) result.put(key, value.get(key)) }
    fun export(collections: List<JSONObject>, assets: List<JSONObject>, queue: JSONArray, state: Map<String, JSONObject>): JSONObject = validate(JSONObject()
        .put("format", "multiplexr-library").put("version", 1).put("createdAt", System.currentTimeMillis())
        .put("collections", JSONArray(collections.map { pick(it, collectionFields) }))
        .put("assets", JSONArray(assets.map { pick(it, assetFields) }))
        .put("queue", queue).put("state", JSONObject(state)))
    private fun typed(value: JSONObject, strings: List<String> = emptyList(), booleans: List<String> = emptyList(), integers: List<String> = emptyList()) {
        for (field in strings) if (value.has(field) && !value.isNull(field)) require(value.get(field) is String) { "Invalid text field: $field" }
        for (field in booleans) if (value.has(field)) require(value.get(field) is Boolean) { "Invalid boolean field: $field" }
        for (field in integers) if (value.has(field) && !value.isNull(field)) {
            val number = value.get(field); require((number is Int || number is Long) && (number as Number).toLong() >= 0) { "Invalid integer field: $field" }
        }
    }
    fun validate(input: JSONObject): JSONObject {
        require(input.optString("format") == "multiplexr-library" && input.optInt("version") == 1) { "Unsupported backup format or version." }
        val collections = input.getJSONArray("collections"); val assets = input.getJSONArray("assets")
        require(collections.length() <= 10000 && assets.length() <= 200000) { "Backup exceeds supported limits." }
        val ids = mutableSetOf<String>(); val assetIds = mutableSetOf<String>()
        val cleanCollections = JSONArray(); val cleanAssets = JSONArray()
        for (i in 0 until collections.length()) {
            val c = collections.getJSONObject(i)
            typed(c, strings = listOf("id", "name", "type", "subtype", "view", "player", "sort", "filter", "folder"), booleans = listOf("locked", "includeInGlobalCinema", "includeInGlobalVideos", "autoplayNext", "allowFolders"))
            if (c.has("openAction")) require(c.getString("openAction") in setOf("automatic", "details", "play"))
            if (c.has("audioRate")) require(c.get("audioRate") is Number && c.getDouble("audioRate").isFinite() && c.getDouble("audioRate") in 0.5..3.0)
            if (c.has("cardSize")) require(c.get("cardSize") is Number && c.getDouble("cardSize").isFinite() && c.getDouble("cardSize") in 100.0..300.0) { "Invalid card size." }
            require(c.getString("id").isNotBlank() && ids.add(c.getString("id"))) { "Duplicate or empty collection identity." }
            require(c.getString("name").isNotBlank() && c.getString("type") in listOf("video", "audiobook", "audio")) { "Unsupported collection media type." }
            if (c.has("includeInGlobalAudio")) require(c.get("includeInGlobalAudio") is Boolean)
            require(c.getString("subtype") in when (c.getString("type")) {
                "audio" -> listOf("audiobooks", "music")
                "audiobook" -> listOf("audiobooks", "videos", "cinema", "movies", "tv")
                else -> listOf("videos", "cinema", "movies", "tv")
            })
            require(c.getString("view") in listOf("grid", "list", "netflix", "posterWall", "compact"))
            require(c.getString("player") in listOf("internal", "external"))
            val roots = c.getJSONArray("roots"); val cleanRoots = JSONArray()
            for (j in 0 until roots.length()) {
                val root = roots.getJSONObject(j)
                typed(root, strings = listOf("uri", "name", "contentSubtype"))
                if (root.has("contentSubtype")) require(root.getString("contentSubtype") in listOf("movies", "tv"))
                require(root.getString("uri").startsWith("content://")); root.getString("name")
                cleanRoots.put(pick(root, listOf("uri", "name", "contentSubtype")))
            }
            require(c.getJSONArray("extensions").length() > 0)
            for (j in 0 until c.getJSONArray("extensions").length()) require(c.getJSONArray("extensions").get(j) is String)
            cleanCollections.put(pick(c, collectionFields).put("roots", cleanRoots))
        }
        for (i in 0 until assets.length()) {
            val a = assets.getJSONObject(i)
            typed(a, strings = listOf("id", "collectionId", "uri", "filename", "seriesBackdrop", "rootUri", "relativePath", "metadataStatus", "poster", "backdrop", "metadataSource", "contentSubtype"),
                booleans = listOf("favorite", "watchLater", "watched", "hiddenFromContinue"),
                integers = listOf("size", "modified", "durationMs", "width", "height", "positionMs", "seriesId", "episodeId", "lastPlayedAt", "completedAt", "providerId", "addedAt"))
            require(a.getString("collectionId") in ids && a.getString("id").isNotBlank())
            val key = JSONArray(listOf(a.getString("collectionId"), a.getString("id"))).toString()
            require(assetIds.add(key)) { "Duplicate asset identity." }
            require(a.getString("uri").startsWith("content://")); a.getString("filename")
            // Unmatched scans may rely entirely on filename inference in Flutter.
            if (a.has("metadata") && !a.isNull("metadata")) {
                val metadata = a.getJSONObject("metadata")
                for (keyName in metadata.keys()) require(metadata.get(keyName) is String) { "Metadata values must be text." }
            }
            for (field in listOf("positionMs", "durationMs", "lastPlayedAt", "completedAt")) if (a.has(field)) require(a.getLong(field) >= 0)
            cleanAssets.put(pick(a, assetFields))
        }
        val queue = input.optJSONArray("queue") ?: JSONArray(); val cleanQueue = JSONArray(); val seen = mutableSetOf<String>()
        for (i in 0 until queue.length()) {
            val key = queue.getString(i); val pair = JSONArray(key)
            require(pair.length() == 2)
            val canonical = JSONArray(listOf(pair.getString(0), pair.getString(1))).toString()
            if (canonical in assetIds && seen.add(canonical)) cleanQueue.put(canonical)
        }
        val state = input.optJSONObject("state") ?: JSONObject(); val cleanState = JSONObject()
        require(state.keys().asSequence().none { it.startsWith("reading:") && it !in setOf(ReadingCatalogCodec.KEY, ReadingIndexCodec.KEY, ReadingAnnotationsCodec.KEY, ReadingManagementCodec.KEY) }) { "Unsupported reading state version." }
        if (state.has(ReadingCatalogCodec.KEY)) {
            val reading = ReadingCatalogCodec.validate(state.getJSONObject(ReadingCatalogCodec.KEY))
            ReadingCatalogCodec.requireSeparateOwners(reading, ids)
            cleanState.put(ReadingCatalogCodec.KEY, reading)
        }
        if (state.has(ReadingIndexCodec.KEY)) {
            val index = ReadingIndexCodec.validate(state.getJSONObject(ReadingIndexCodec.KEY), state.getJSONObject(ReadingCatalogCodec.KEY))
            val entries = index.getJSONArray("entries")
            require((0 until entries.length()).none { entries.getJSONObject(it).getString("cover").startsWith("reading-cover:") }) { "Reading covers must be portable in a backup." }
            cleanState.put(ReadingIndexCodec.KEY, index)
        }
        if (state.has(ReadingAnnotationsCodec.KEY)) cleanState.put(ReadingAnnotationsCodec.KEY,
            ReadingAnnotationsCodec.validate(state.getJSONObject(ReadingAnnotationsCodec.KEY), state.getJSONObject(ReadingCatalogCodec.KEY)))
        if (state.has(ReadingManagementCodec.KEY)) {
            val managed = ReadingManagementCodec.validate(state.getJSONObject(ReadingManagementCodec.KEY), state.getJSONObject(ReadingCatalogCodec.KEY))
            val entities = managed.getJSONArray("entities")
            require((0 until entities.length()).none { entities.getJSONObject(it).getString("cover").startsWith("reading-cover:") }) { "Reading covers must be portable in a backup." }
            cleanState.put(ReadingManagementCodec.KEY, managed)
        }
        if(state.has(com.bugdeployer.multiplexr.plugins.PluginPortable.KEY)) cleanState.put(com.bugdeployer.multiplexr.plugins.PluginPortable.KEY, com.bugdeployer.multiplexr.plugins.PluginPortable.validate(state.getJSONObject(com.bugdeployer.multiplexr.plugins.PluginPortable.KEY)))
        val normalized = CatalogNormalization.state(state.keys().asSequence().filter(CollectionStatePolicy::exportable).associateWith { state.getJSONObject(it) }).first
        for ((key, value) in normalized) if (key.startsWith("progress:") || key.startsWith("queue:")) cleanState.put(key, DurableMediaStateCodec.validate(key, value))
        for ((key, value) in normalized) if (key.startsWith("media:settings:")) cleanState.put(key, MediaSettingsCodec.validate(key, value))
        for (key in state.keys()) if (key.startsWith("spaces:audiobooks:")) { val local = state.getJSONObject(key); SpacePreferencesCodec.validate(JSONObject().put("audiobooks", local)); cleanState.put(key, local) }
        if (state.has("spaces:display")) cleanState.put("spaces:display", SpacePreferencesCodec.validate(state.getJSONObject("spaces:display")))
        if (state.has("audio:library")) cleanState.put("audio:library", AudioCatalogCodec.validate(state.getJSONObject("audio:library")))
        if (state.has("music:library")) {
            val music = MusicCatalogCodec.validate(state.getJSONObject("music:library"))
            val owners = (0 until cleanCollections.length()).map { cleanCollections.getJSONObject(it) }
                .filter { it.optString("type") == "audio" && it.optString("subtype") == "music" }.map { it.getString("id") }.toSet()
            val tracks = music.getJSONArray("tracks")
            require((0 until tracks.length()).all { tracks.getJSONObject(it).getJSONObject("id").getString("collectionId") in owners })
            cleanState.put("music:library", music)
        }
        if (state.has("music:extras")) cleanState.put("music:extras", MusicExtrasCodec.validate(state.getJSONObject("music:extras"), (0 until cleanCollections.length()).map { cleanCollections.getJSONObject(it) }.filter { it.optString("type") == "audio" && it.optString("subtype") == "music" }.map { it.getString("id") }.toSet()))
        for (key in state.keys()) if (key.startsWith("spaces:music:")) { val local = state.getJSONObject(key); SpacePreferencesCodec.validate(JSONObject().put("music", local)); cleanState.put(key,local) }
        if (state.has(PlayerPreferencesCodec.KEY)) cleanState.put(PlayerPreferencesCodec.KEY, PlayerPreferencesCodec.validate(state.getJSONObject(PlayerPreferencesCodec.KEY)))
        if (state.has("music:session")) cleanState.put("music:session", MusicSessionCodec.validate(state.getJSONObject("music:session")))
        for(key in state.keys()) if(key.startsWith(ExtensionFieldsCodec.PREFIX)) {
            val owner=ExtensionFieldsCodec.owner(key)
            val readingOwners=cleanState.optJSONObject(ReadingCatalogCodec.KEY)?.optJSONArray("collections") ?: JSONArray()
            require(owner in ids || (0 until readingOwners.length()).any { readingOwners.getJSONObject(it).getString("id")==owner })
            cleanState.put(key,ExtensionFieldsCodec.validate(key,state.getJSONObject(key)))
        }
        return JSONObject().put("format", "multiplexr-library").put("version", 1).put("createdAt", input.optLong("createdAt"))
            .put("collections", cleanCollections).put("assets", cleanAssets).put("queue", cleanQueue).put("state", cleanState)
    }
}
