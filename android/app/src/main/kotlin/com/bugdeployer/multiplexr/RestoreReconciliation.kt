package com.bugdeployer.multiplexr

import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder

/** Existing SAF grants survive index restore; source files are verified by scan. */
object RestoreReconciliation {
    private fun tree(uri: String): Pair<String, String>? = runCatching {
        val parsed = URI(uri)
        val encoded = Regex("/tree/([^/]+)").find(parsed.rawPath.orEmpty())?.groupValues?.get(1) ?: return null
        parsed.authority to URLDecoder.decode(encoded.replace("+", "%2B"), "UTF-8")
    }.getOrNull()
    fun granted(root: String, readableGrants: Set<String>): Boolean {
        if (root in readableGrants) return true
        val target = tree(root) ?: return false
        return readableGrants.any { grant ->
            val owner = tree(grant)
            owner != null && owner.first == target.first &&
                (target.second == owner.second || target.second.startsWith(owner.second.trimEnd('/') + "/"))
        }
    }
    fun collection(input: JSONObject, readableGrants: Set<String>): JSONObject {
        val item = JSONObject(input.toString())
        val roots = item.getJSONArray("roots"); val health = JSONObject()
        for (i in 0 until roots.length()) {
            val uri = roots.getJSONObject(i).getString("uri")
            health.put(uri, if (granted(uri, readableGrants)) "Permission retained — scan to verify files" else "Unavailable — reselect this root folder")
        }
        return item.put("rootHealth", health).put("lastScanAt", 0)
    }
}
