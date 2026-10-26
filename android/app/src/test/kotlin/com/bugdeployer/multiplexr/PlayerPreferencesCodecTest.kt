package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PlayerPreferencesCodecTest {
    private fun settings() = JSONObject("""{"version":1,"video":{"backSeconds":5,"forwardSeconds":20,"shuffle":false,"repeat":""},"music":{"shuffle":true,"repeat":"all"}}""")
    @Test fun playerSettingsSurviveBackupAndCollectionRemoval() {
        val value = settings()
        assertTrue(CollectionStatePolicy.exportable(PlayerPreferencesCodec.KEY))
        assertTrue(CollectionStatePolicy.writable(PlayerPreferencesCodec.KEY, false))
        assertFalse(CollectionStatePolicy.writable("settings:security", false))
        assertFalse(CollectionStatePolicy.writable("music:session", false))
        assertTrue(CollectionStatePolicy.writable("music:session", true))
        val backup = BackupCodec.export(emptyList(), emptyList(), JSONArray(), mapOf(PlayerPreferencesCodec.KEY to value))
        val restored = BackupCodec.validate(backup).getJSONObject("state").getJSONObject(PlayerPreferencesCodec.KEY)
        assertEquals(20, restored.getJSONObject("video").getInt("forwardSeconds"))
        assertTrue(restored.getJSONObject("music").getBoolean("shuffle"))
        assertEquals(value.toString(), CollectionStatePolicy.withoutCollection(PlayerPreferencesCodec.KEY, value, "removed")!!.toString())
    }
    @Test fun malformedControlsAndVersionsAreRejected() {
        for (value in listOf(
            settings().put("version", 2),
            settings().put("version", 1.5),
            settings().put("video", JSONObject().put("backSeconds", -1)),
            settings().put("video", JSONObject().put("backSeconds", 10.5)),
            settings().put("music", JSONObject().put("shuffle", "true")),
            settings().put("music", JSONObject().put("repeat", "unknown")),
            settings().put("credential", "not-allowed")
        )) assertTrue(runCatching { PlayerPreferencesCodec.validate(value) }.isFailure)
    }
}
