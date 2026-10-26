package com.bugdeployer.multiplexr.plugins

/** A provider denial is a valid reply, not an interpreter crash. */
internal object PluginReply {
    private val errors = setOf("invalid_request", "invalid_response", "version_mismatch", "unsupported_capability", "permission_denied", "not_found", "conflict", "cancelled", "deadline_exceeded", "resource_limit", "message_too_large", "busy", "plugin_error", "runtime_failure")
    fun valid(raw: String, id: String): Boolean = try {
        require(raw.toByteArray(Charsets.UTF_8).size <= 65536)
        val value = PluginPackage.objectJson(raw.toByteArray(Charsets.UTF_8))
        val failure = value.has("error")
        PluginPackage.exact(value, setOf("v", "id", if (failure) "error" else "result"))
        require(value.get("v") == 1 && value.getString("id") == id)
        if (failure) {
            val error = value.getJSONObject("error")
            PluginPackage.exact(error, setOf("code"))
            require(error.getString("code") in errors)
        }
        true
    } catch (_: Exception) { false }
}
