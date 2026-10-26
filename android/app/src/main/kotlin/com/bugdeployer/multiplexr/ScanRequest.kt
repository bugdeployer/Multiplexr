package com.bugdeployer.multiplexr

/** Backward compatible protocol; generation belongs to a request, not persisted media. */
data class ScanRequest(val id: String, val requestId: String?) {
    companion object {
        fun decode(raw: Any?): ScanRequest {
            val id = if (raw is String) raw else (raw as? Map<*, *>)?.get("id") as? String
            val token = (raw as? Map<*, *>)?.get("requestId")
            require(!id.isNullOrBlank() && (token == null || token is String && token.isNotBlank() && token.length <= 128))
            return ScanRequest(id, token as? String)
        }
    }
    fun progress(found: Int, folder: String): Map<String, Any> = buildMap {
        put("id", id); put("found", found); put("folder", folder)
        requestId?.let { put("requestId", it) }
    }
    fun result(warnings: List<String>): Any = requestId?.let { mapOf("requestId" to it, "warnings" to warnings) } ?: warnings
}
