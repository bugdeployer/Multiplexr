package com.bugdeployer.multiplexr
import com.bugdeployer.multiplexr.plugins.*
import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
class PluginSettingsTest {
    private fun plugin(): PluginPackage {
        val bytes=javaClass.getResourceAsStream("/plugins/installed-v1.json")!!.readBytes()
        val p=PluginPackage.parse(bytes)
        val manifest=JSONObject(p.manifest.toString())
        manifest.getJSONArray("contributions").put(JSONObject("""{"id":"org.example.installed:settings","family":"settings.section","fields":[{"id":"org.example.installed:enabled","type":"boolean","default":false,"scopes":["app","collection","title"]}]}"""))
        return p.copy(manifest=manifest)
    }
    @Test fun typedInheritanceResetAndRevisionConflicts() {
        val root=kotlin.io.path.createTempDirectory("settings-test").toFile()
        try {
            val s=PluginSettings(root);val p=plugin();val id="org.example.installed:enabled"
            fun write(rev:Int,value:Any)=JSONObject().put("id",id).put("address",JSONObject().put("scope","app")).put("expectedRevision",rev).put("value",value)
            assertEquals(1L,s.call(p,"settings.propose",write(0,true))["revision"])
            try { s.call(p,"settings.propose",write(0,false));fail() } catch(_:IllegalArgumentException) {}
            try { s.call(p,"settings.propose",write(1,"secret"));fail() } catch(_:IllegalArgumentException) {}
            val query=JSONObject().put("id",id).put("lineage",JSONArray().put(JSONObject().put("scope","app")).put(JSONObject().put("scope","collection").put("collection","books")))
            assertEquals(true,s.call(p,"settings.effective",query)["value"])
            assertEquals(0,s.call(p,"settings.effective",query)["sourceIndex"])
            s.call(p,"settings.reset",write(1,false))
            assertEquals(false,s.call(p,"settings.effective",query)["value"])
            assertNull(s.call(p,"settings.effective",query)["sourceIndex"])
            s.prepare(p);s.clear(p);assertEquals(0L,s.export(p).getLong("revision"))
        } finally { root.deleteRecursively() }
    }
    @Test fun namespacePublisherAndPortableAddressValidation() {
        val root=kotlin.io.path.createTempDirectory("settings-owner").toFile()
        try {
            val s=PluginSettings(root);val p=plugin();val id="org.example.installed:enabled"
            s.call(p,"settings.propose",JSONObject().put("id",id).put("address",JSONObject().put("scope","app")).put("expectedRevision",0).put("value",true))
            assertEquals(0L,s.export(p.copy(publisher="a".repeat(64))).getLong("revision"))
            val invalid=s.export(p);invalid.getJSONObject("values").put(JSONArray(listOf("title","","",id)).toString(),false)
            try { PluginSettings.validatePortable(invalid,p.id);fail() } catch(_:IllegalArgumentException) {}
            val changed=plugin();changed.manifest.getJSONArray("contributions").getJSONObject(1).getJSONArray("fields").getJSONObject(0).put("type","text").put("maxLength",30)
            try { s.prepare(changed);fail() } catch(_:IllegalArgumentException) {}
            assertEquals(true,s.call(p,"settings.effective",JSONObject().put("id",id).put("lineage",JSONArray().put(JSONObject().put("scope","app"))))["value"])
        } finally { root.deleteRecursively() }
    }
}
