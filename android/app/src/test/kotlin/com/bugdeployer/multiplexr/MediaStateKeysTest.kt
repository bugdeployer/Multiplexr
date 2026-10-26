package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class MediaStateKeysTest {
    @Test fun folderIdentitiesUseTheSameProgressKeyAsFlutter() {
        val key = "progress:" + JSONArray(listOf("audiobook", "collection", "folder:provider:Audio/Saga/Book")).toString()
        assertEquals("progress:[\"audiobook\",\"collection\",\"folder:provider:Audio/Saga/Book\"]", MediaStateKeys.canonical(key))
        assertEquals(MediaStateKeys.canonical(key), MediaStateKeys.canonical(MediaStateKeys.canonical(key)))
        assertTrue(MediaStateKeys.aliases(key).contains(key))
    }
    @Test fun identityPunctuationSurvivesCanonicalization() {
        val key = "progress:" + JSONArray(listOf("audiobook", "a:[]", "folder/quoted\"/path")).toString()
        val values = JSONArray(MediaStateKeys.canonical(key).removePrefix("progress:"))
        assertEquals("folder/quoted\"/path", values.getString(2))
    }
}
