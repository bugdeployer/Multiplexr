package com.bugdeployer.multiplexr

import org.json.JSONArray

/** Android escapes slashes in JSON strings; Flutter does not. Keep one durable key. */
object MediaStateKeys {
    private fun prefix(key: String) = listOf("progress:", "media:settings:", "ui:browse:").firstOrNull(key::startsWith)
    fun canonical(key: String): String {
        val prefix = prefix(key) ?: return key
        return prefix + JSONArray(key.removePrefix(prefix)).toString().replace("\\/", "/")
    }
    fun aliases(key: String): List<String> {
        val prefix = prefix(key) ?: return listOf(key)
        val array = JSONArray(key.removePrefix(prefix))
        return listOf(canonical(key), key, prefix + array.toString()).distinct()
    }
}
