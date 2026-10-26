package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject

/** Local execution receipts only. No commands, provider payloads or credentials. */
object JobReceiptCodec {
    const val KEY = "ui:jobs:v1"
    private val outcomes = setOf("running", "completed", "cancelled", "failed", "interrupted")
    fun validate(value: JSONObject): JSONObject {
        require(value.keys().asSequence().toSet() == setOf("version", "receipts"))
        require(value.get("version") == 1)
        val rows = value.getJSONArray("receipts")
        require(rows.length() <= 10000)
        val keys = mutableSetOf<String>()
        for (i in 0 until rows.length()) {
            val row = rows.getJSONObject(i)
            require(row.keys().asSequence().toSet() == setOf("key", "collections", "outcome"))
            val key = row.getString("key")
            require(key.isNotEmpty() && key.length <= 512 && keys.add(key))
            require(row.getString("outcome") in outcomes)
            val scopes = row.getJSONArray("collections")
            require(scopes.length() <= 1000)
            val seen = mutableSetOf<String>()
            for (j in 0 until scopes.length()) {
                val id = scopes.getString(j)
                require(id.isNotEmpty() && id.length <= 2048 && seen.add(id))
            }
        }
        return value
    }
    fun withoutCollection(value: JSONObject, id: String): JSONObject {
        validate(value)
        val rows = value.getJSONArray("receipts")
        return JSONObject().put("version", 1).put("receipts", JSONArray(
            (0 until rows.length()).map { rows.getJSONObject(it) }.filter { row ->
                val scopes = row.getJSONArray("collections")
                (0 until scopes.length()).none { scopes.getString(it) == id }
            }))
    }
}
