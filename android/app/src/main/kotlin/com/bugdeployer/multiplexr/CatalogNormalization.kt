package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject

/** A narrow, repeatable upgrade of existing records; identities never change. */
object CatalogNormalization {
    data class Plan(val collections: List<JSONObject>, val state: Map<String, JSONObject>,
        val remove: Set<String>, val before: JSONObject, val conflicts: List<String>)

    fun state(input: Map<String, JSONObject>): Pair<Map<String, JSONObject>, List<String>> {
        val grouped = input.entries.groupBy { runCatching { MediaStateKeys.canonical(it.key) }.getOrDefault(it.key) }
        val conflicts = mutableListOf<String>()
        val result = linkedMapOf<String, JSONObject>()
        for ((key, entries) in grouped) {
            // Preserve the value already preferred by current readers. Input order is
            // not a timestamp; it must never decide which settings/progress wins.
            val selected = entries.firstOrNull { it.key == key } ?: entries.sortedBy { it.key }.first()
            val value = JSONObject(selected.value.toString())
            if (entries.size > 1 && entries.any { it.value.toString() != selected.value.toString() }) conflicts.add(key)
            result[key] = value
        }
        return result to conflicts
    }

    fun plan(collections: List<JSONObject>, states: Map<String, JSONObject>): Plan {
        val changed = mutableListOf<JSONObject>(); val oldCollections = JSONArray()
        val owners = collections.map { it.getString("id") }.toMutableSet()
        for (collection in collections) if (collection.optString("type") == "audiobook") {
            oldCollections.put(JSONObject(collection.toString()))
            changed.add(JSONObject(collection.toString()).put("type", "audio").put("subtype", "audiobooks"))
        }
        val audio = states["audio:library"]
        if (audio != null) {
            AudioCatalogCodec.validate(audio)
            val books = audio.getJSONArray("books")
            for (i in 0 until books.length()) {
                val owner = books.getJSONObject(i).getJSONObject("id").getString("collectionId")
                if (owners.add(owner)) changed.add(JSONObject().put("id", owner).put("type", "audio").put("subtype", "audiobooks")
                    .put("name", if (owner == "audiobooks") "Audiobooks" else "Imported audiobooks")
                    .put("view", "list").put("player", "internal").put("roots", JSONArray())
                    .put("extensions", JSONArray(listOf("mp3", "m4b", "m4a", "flac", "ogg", "opus", "wav", "aac")))
                    .put("locked", false).put("includeInGlobalAudio", true))
            }
        }
        val (normalized, conflicts) = state(states)
        val updates = normalized.filter { (key, value) -> states[key]?.toString() != value.toString() }
        val removed = states.keys - normalized.keys
        val beforeState = JSONObject()
        for (key in (updates.keys + removed)) states[key]?.let { beforeState.put(key, JSONObject(it.toString())) }
        val created = changed.map { it.getString("id") }.filter { id -> collections.none { it.optString("id") == id } }
        return Plan(changed, updates, removed,
            JSONObject().put("collections", oldCollections).put("state", beforeState).put("createdCollections", JSONArray(created)), conflicts)
    }
}

interface CatalogMigrationStore {
    fun readState(key: String): JSONObject?
    fun collections(): List<JSONObject>
    fun states(): Map<String, JSONObject>
    fun putCollection(value: JSONObject)
    fun putState(key: String, value: JSONObject)
    fun deleteState(key: String)
    fun transaction(action: () -> Unit)
    fun legacyVideoQueue(): JSONObject? = null
}

/** Prepared journal survives process death; activation + completion commit together. */
object CatalogMigration {
    const val KEY = "catalog:migration:1"
    fun forgetState(store: CatalogMigrationStore, key: String) {
        val journal = store.readState(KEY) ?: return
        val before = journal.optJSONObject("before")?.optJSONObject("state") ?: return
        val remove = before.keys().asSequence().filter { candidate -> runCatching { MediaStateKeys.canonical(candidate) == MediaStateKeys.canonical(key) }.getOrDefault(false) }.toList()
        if (remove.isEmpty()) return
        for (candidate in remove) before.remove(candidate)
        store.putState(KEY, journal)
    }
    fun forgetCollection(store: CatalogMigrationStore, id: String) {
        val journal = store.readState(KEY) ?: return
        val before = journal.optJSONObject("before") ?: return
        val rows = before.optJSONArray("collections") ?: JSONArray()
        before.put("collections", JSONArray((0 until rows.length()).map { rows.getJSONObject(it) }.filter { it.optString("id") != id }))
        val created = before.optJSONArray("createdCollections") ?: JSONArray()
        before.put("createdCollections", JSONArray((0 until created.length()).map { created.getString(it) }.filter { it != id }))
        val states = before.optJSONObject("state") ?: JSONObject()
        for (key in states.keys().asSequence().toList()) {
            val next = CollectionStatePolicy.withoutCollection(key, states.getJSONObject(key), id)
            if (next == null) states.remove(key) else states.put(key, next)
        }
        before.optJSONObject("legacyQueue")?.let { before.put("legacyQueue", CollectionStatePolicy.withoutCollection("legacyVideoQueue", it, id)) }
        before.put("state", states)
        val conflicts = journal.optJSONArray("conflicts") ?: JSONArray()
        journal.put("conflicts", JSONArray((0 until conflicts.length()).map { conflicts.getString(it) }.filter { !CollectionStatePolicy.ownedBy(it, id) }))
        store.putState(KEY, journal)
    }
    fun ensure(store: CatalogMigrationStore) {
        val journal = store.readState(KEY)
        if (journal?.optString("status") == "complete" && journal.optInt("version") == 1) return
        if (journal == null) store.transaction {
            val plan = plan(store)
            store.putState(KEY, JSONObject().put("version", 1).put("status", "prepared").put("before", plan.before))
        } else require(journal.optInt("version") == 1 && journal.optString("status") == "prepared") { "Unsupported catalog maintenance journal." }
        store.transaction {
            // Re-read after a prepared/retried journal: retain intervening progress.
            val plan = plan(store)
            for (collection in plan.collections) store.putCollection(collection)
            for ((key, value) in plan.state) store.putState(key, value)
            for (key in plan.remove) store.deleteState(key)
            store.putState(KEY, JSONObject().put("version", 1).put("status", "complete")
                .put("before", plan.before).put("conflicts", JSONArray(plan.conflicts))
                .put("updatedCollections", plan.collections.size).put("updatedState", plan.state.size).put("removedAliases", plan.remove.size))
        }
    }
    private fun plan(store: CatalogMigrationStore): CatalogNormalization.Plan {
        val states = store.states().filterKeys { it != KEY }
        val plan = CatalogNormalization.plan(store.collections(), states)
        val legacy = if (states.containsKey("legacyVideoQueue")) null else store.legacyVideoQueue()
        if (legacy == null) return plan
        require(legacy.get("items") is JSONArray)
        return plan.copy(state = plan.state + ("legacyVideoQueue" to JSONObject(legacy.toString())),
            before = plan.before.put("legacyQueue", JSONObject(legacy.toString())))
    }
}
