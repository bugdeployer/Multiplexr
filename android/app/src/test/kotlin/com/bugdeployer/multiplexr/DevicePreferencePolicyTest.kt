package com.bugdeployer.multiplexr
import org.junit.Assert.*
import org.junit.Test
class DevicePreferencePolicyTest {
    @Test fun acceptsScopedPreferences() {
        assertEquals(mapOf("dark" to true, "libraryView" to 2), DevicePreferencePolicy.appearance(mapOf("dark" to true, "libraryView" to 2)))
        assertEquals(mapOf("lockDelay" to 30), DevicePreferencePolicy.security(mapOf("lockDelay" to 30)))
        DevicePreferencePolicy.category("errors")
    }
    @Test fun rejectsWholeBatchBeforeAnyWrite() {
        for (values in listOf(mapOf("dark" to true, "lockEnabled" to false), mapOf("libraryView" to 3), mapOf("dark" to "true"), mapOf("unknown" to true))) {
            try { DevicePreferencePolicy.appearance(values); fail("Expected rejection") } catch (_: IllegalArgumentException) { }
        }
        try { DevicePreferencePolicy.security(mapOf("lockDelay" to 7)); fail("Expected rejection") } catch (_: IllegalArgumentException) { }
        try { DevicePreferencePolicy.category("alerts"); fail("Expected rejection") } catch (_: IllegalArgumentException) { }
    }
    @Test fun themeLimitCountsUtf8Bytes() {
        DevicePreferencePolicy.appearance(mapOf("themeState" to "x".repeat(ThemeDocumentPolicy.MAX_INSTALLED)))
        try { DevicePreferencePolicy.appearance(mapOf("themeState" to "\u754c".repeat(6000000))); fail("Expected rejection") } catch (_: IllegalArgumentException) { }
    }
}
