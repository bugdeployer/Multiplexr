package com.bugdeployer.multiplexr

import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class MediaSettingsTest {
    @Test fun backupRetainsCollectionAndScopedNavigationPreferences() {
        val collection = JSONObject().put("id", "a").put("name", "Audio").put("type", "audio").put("subtype", "audiobooks").put("view", "grid").put("player", "internal").put("roots", JSONArray()).put("extensions", JSONArray(listOf("mp3"))).put("openAction", "details").put("audioRate", 1.25)
        val key = "media:settings:" + JSONArray(listOf("a", "series:saga"))
        val settings = JSONObject().put("openAction", "play").put("rate", 1.5)
        val backup = BackupCodec.export(listOf(collection), emptyList(), JSONArray(), mapOf(key to settings))
        assertEquals("details", backup.getJSONArray("collections").getJSONObject(0).getString("openAction"))
        assertEquals(1.25, backup.getJSONArray("collections").getJSONObject(0).getDouble("audioRate"), 0.0)
        assertEquals(1.5, backup.getJSONObject("state").getJSONObject(key).getDouble("rate"), 0.0)
    }
    @Test fun rejectsCredentialsAndInvalidRatesInEntitySettings() {
        val key = "media:settings:" + JSONArray(listOf("a", "book"))
        for (value in listOf(JSONObject().put("token", "secret"), JSONObject().put("rate", -1), JSONObject().put("openAction", "unknown"))) {
            try { MediaSettingsCodec.validate(key, value); fail("Invalid settings accepted") } catch (_: IllegalArgumentException) {}
        }
    }
    @Test fun audiobookSpaceUsesSameValidatedPreferenceSchema() {
        val settings = JSONObject().put("audiobooks", JSONObject().put("startTab", 2).put("hideWatched", true).put("confirmExit", true))
        assertEquals(2, SpacePreferencesCodec.validate(settings).getJSONObject("audiobooks").getInt("startTab"))
    }
}
