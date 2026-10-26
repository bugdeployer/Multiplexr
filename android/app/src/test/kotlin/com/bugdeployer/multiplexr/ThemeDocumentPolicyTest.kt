package com.bugdeployer.multiplexr

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class ThemeDocumentPolicyTest {
    @Test fun dartAndAndroidShareDocumentBoundsFixture() {
        val fixture = generateSequence(File(".").canonicalFile) { it.parentFile }
            .map { File(it,"test/fixtures/theme_limits.json") }.first { it.isFile }
        val limits = JSONObject(fixture.readText())
        assertEquals(limits.getInt("packageBytes"),ThemeDocumentPolicy.MAX_PACKAGE)
        assertEquals(limits.getInt("installedBytes"),ThemeDocumentPolicy.MAX_INSTALLED)
    }
    private fun theme(version: Int) = JSONObject().put("format","multiplexr-theme").put("version",version)
        .put("tokens",JSONObject()).put("name","Test")
    @Test fun legacyLimitIsRetainedAndV2AllowsPackages() {
        ThemeDocumentPolicy.validate(theme(1).toString())
        ThemeDocumentPolicy.validate(theme(2).put("padding","x".repeat(20000)).toString())
        assertEquals(4194304,ThemeDocumentPolicy.MAX_PACKAGE)
        assertEquals(16777216,ThemeDocumentPolicy.MAX_INSTALLED)
    }
    @Test(expected=IllegalArgumentException::class) fun oversizedV1Rejected() {
        ThemeDocumentPolicy.validate(theme(1).put("padding","x".repeat(17000)).toString())
    }
    @Test(expected=IllegalArgumentException::class) fun oversizedV2Rejected() {
        ThemeDocumentPolicy.validate(theme(2).put("padding","x".repeat(4194304)).toString())
    }
    @Test(expected=IllegalArgumentException::class) fun nestingBoundedBeforeJsonParse() {
        ThemeDocumentPolicy.validate("[".repeat(13)+"0"+"]".repeat(13))
    }
    @Test fun bracesInsideStringsDoNotCountAsNesting() {
        ThemeDocumentPolicy.validate(theme(2).put("name","{[".repeat(20)).toString())
    }
}
