package com.bugdeployer.multiplexr

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

/** One SQLite authority. Canonical writes and alias cleanup are one transaction. */
object LibraryStateStore {
    fun raw(db: SQLiteDatabase, key: String): JSONObject? = db.query("library_state", arrayOf("payload"), "id=?", arrayOf(key), null, null, null).use {
        if (it.moveToFirst()) JSONObject(it.getString(0)) else null
    }
    fun read(db: SQLiteDatabase, key: String): JSONObject? = MediaStateKeys.aliases(key).firstNotNullOfOrNull { raw(db, it) }
    fun transaction(db: SQLiteDatabase, action: () -> Unit) {
        if (db.inTransaction()) { action(); return }
        db.beginTransaction()
        try { action(); db.setTransactionSuccessful() } finally { db.endTransaction() }
    }
    fun putRaw(db: SQLiteDatabase, key: String, value: JSONObject) {
        check(db.insertWithOnConflict("library_state", null, ContentValues().apply {
            put("id", key); put("payload", value.toString())
        }, SQLiteDatabase.CONFLICT_REPLACE) != -1L)
    }
    fun put(db: SQLiteDatabase, key: String, value: JSONObject) = transaction(db) {
        val canonical = MediaStateKeys.canonical(key)
        putRaw(db, canonical, value)
        for (alias in MediaStateKeys.aliases(key)) if (alias != canonical) db.delete("library_state", "id=?", arrayOf(alias))
    }
    fun delete(db: SQLiteDatabase, key: String) = transaction(db) {
        for (alias in MediaStateKeys.aliases(key)) db.delete("library_state", "id=?", arrayOf(alias))
        CatalogMigration.forgetState(migrationStore(db), key)
    }
    fun migrationStore(db: SQLiteDatabase, legacyQueue: (() -> JSONObject?)? = null): CatalogMigrationStore = object : CatalogMigrationStore {
        override fun legacyVideoQueue() = legacyQueue?.invoke()
        override fun readState(key: String) = raw(db, key)
        override fun collections(): List<JSONObject> = db.query("collections", arrayOf("payload"), null, null, null, null, "rowid ASC").use { cursor ->
            buildList { while (cursor.moveToNext()) add(JSONObject(cursor.getString(0))) }
        }
        override fun states(): Map<String, JSONObject> = db.query("library_state", arrayOf("id", "payload"), null, null, null, null, "rowid ASC").use { cursor ->
            buildMap { while (cursor.moveToNext()) put(cursor.getString(0), JSONObject(cursor.getString(1))) }
        }
        override fun putCollection(value: JSONObject) {
            check(db.insertWithOnConflict("collections", null, ContentValues().apply { put("id", value.getString("id")); put("payload", value.toString()) }, SQLiteDatabase.CONFLICT_REPLACE) != -1L)
        }
        override fun putState(key: String, value: JSONObject) = putRaw(db, key, value)
        override fun deleteState(key: String) { db.delete("library_state", "id=?", arrayOf(key)) }
        override fun transaction(action: () -> Unit) = transaction(db, action)
    }
}
