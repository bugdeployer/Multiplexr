package com.bugdeployer.multiplexr

/** Framework-free validation shared by every native preference write path. */
internal object DevicePreferencePolicy {
    val appearanceFlags = setOf("dark", "followSystem", "compact", "reduceMotion", "pixel")
    val paletteKeys = setOf("darkBase", "darkAccent", "lightBase", "lightAccent")
    val viewKeys = setOf("libraryView", "spacesView")
    val securityFlags = setOf("useBiometrics", "hidePreviews", "protectScreen")
    val categories = setOf("completed", "errors", "activity")
    fun appearance(values: Map<*, *>): Map<String, Any> = validate(values,
        appearanceFlags + paletteKeys + viewKeys + "themeState")
    fun security(values: Map<*, *>): Map<String, Any> = validate(values, securityFlags + "lockDelay")
    fun category(id: String) { require(id in categories) { "Unknown notification category" } }
    private fun validate(values: Map<*, *>, allowed: Set<String>): Map<String, Any> {
        val result = linkedMapOf<String, Any>()
        for ((key, value) in values) {
            require(key is String && key in allowed) { "Unknown preference" }
            val valid = when (key) {
                in appearanceFlags, in securityFlags -> value is Boolean
                in paletteKeys -> value is Int && value in 0..10000
                in viewKeys -> value is Int && value in 0..2
                "lockDelay" -> value is Int && value in setOf(0, 30, 60, 300)
                "themeState" -> value is String && value.toByteArray(Charsets.UTF_8).size <= ThemeDocumentPolicy.MAX_INSTALLED
                else -> false
            }
            require(valid) { "Invalid preference: $key" }
            result[key] = value!!
        }
        return result
    }
}
