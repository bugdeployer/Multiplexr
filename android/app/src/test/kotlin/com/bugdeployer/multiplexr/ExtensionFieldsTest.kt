package com.bugdeployer.multiplexr
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
class ExtensionFieldsTest {
    private val key="plugins:fields:[\"books\",\"ebook\",\"one\"]"
    private fun denied(operation:()->Unit) { try { operation();fail("Expected rejection") } catch(_:IllegalArgumentException) { } }
    @Test fun unknownNamespacesRoundTripAndCollectionDeletionOwnsData() {
        val state=ExtensionFieldsCodec.merge(key,null,"org.example.reader",JSONObject("{\"org.example.reader:rating\":5}"))
        assertEquals(5,ExtensionFieldsCodec.validate(key,JSONObject(state.toString())).getJSONObject("fields").getInt("org.example.reader:rating"))
        assertTrue(CollectionStatePolicy.exportable(key))
        assertNull(CollectionStatePolicy.withoutCollection(key,state,"books"))
        assertEquals(state.toString(),CollectionStatePolicy.withoutCollection(key,state,"other").toString())
        assertFalse(CollectionStatePolicy.writable(key,false))
    }
    @Test fun namespacesLimitsAndDeletionAreEnforced() {
        denied { ExtensionFieldsCodec.merge(key,null,"org.example.reader",JSONObject("{\"org.other:rating\":1}")) }
        denied { ExtensionFieldsCodec.merge(key,null,"org.example.reader",JSONObject().put("org.example.reader:notes","x".repeat(4097))) }
        val state=ExtensionFieldsCodec.merge(key,null,"org.example.reader",JSONObject("{\"org.example.reader:rating\":5}"))
        assertEquals(0,ExtensionFieldsCodec.merge(key,state,"org.example.reader",JSONObject("{\"org.example.reader:rating\":null}")).getJSONObject("fields").length())
    }
    @Test fun duplicateOperationCannotOverwriteLaterUserValue() {
        val first=ExtensionFieldsCodec.merge(key,null,"org.example.reader",JSONObject("{\"org.example.reader:rating\":5}"),"one")
        val newer=ExtensionFieldsCodec.merge(key,first,"org.example.reader",JSONObject("{\"org.example.reader:rating\":2}"),"two")
        val retry=ExtensionFieldsCodec.merge(key,newer,"org.example.reader",JSONObject("{\"org.example.reader:rating\":5}"),"one")
        assertEquals(2,retry.getJSONObject("fields").getInt("org.example.reader:rating"))
    }
}
