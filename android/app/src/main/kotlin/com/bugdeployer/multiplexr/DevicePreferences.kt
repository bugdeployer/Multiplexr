package com.bugdeployer.multiplexr

import android.content.SharedPreferences

/** Preference persistence only. Authentication, window and permission effects
 * remain the activity host's responsibility and precede protected writes. */
internal class DevicePreferences(private val prefs: SharedPreferences) {
    fun appearance(values: Map<*, *>) = commit(DevicePreferencePolicy.appearance(values))
    fun security(values: Map<*, *>) = commit(DevicePreferencePolicy.security(values))
    fun category(id: String, enabled: Boolean): Boolean {
        DevicePreferencePolicy.category(id)
        return commit(mapOf("category_$id" to enabled))
    }
    fun lock(enabled: Boolean) = commit(mapOf("lockEnabled" to enabled))
    fun notifications(enabled: Boolean) = commit(mapOf("notifications" to enabled))
    private fun commit(values: Map<String, Any>): Boolean {
        val editor = prefs.edit()
        for ((key, value) in values) when (value) {
            is Boolean -> editor.putBoolean(key, value)
            is Int -> editor.putInt(key, value)
            is String -> editor.putString(key, value)
            else -> error("Unsupported preference value")
        }
        return editor.commit()
    }
}
