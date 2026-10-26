package com.bugdeployer.multiplexr.plugins
import org.json.JSONObject
import org.json.JSONArray
import java.io.File

/** Restored inventory is information only. No enabled flags, grants, code,
 * credential data, URLs or package paths can be imported through this codec. */
internal object PluginPortable {
    const val KEY = "plugins:portable"
    fun validate(value: JSONObject): JSONObject {
        PluginPackage.exact(value,setOf("version","inventory")); require(value.get("version") is Int && value.getInt("version") == 1)
        val rows=value.getJSONArray("inventory"); require(rows.length() <= 128); val seen=mutableSetOf<String>();val clean=JSONArray()
        for(i in 0 until rows.length()) {
            val row=rows.getJSONObject(i); PluginPackage.exact(row,if(row.has("settings")) setOf("id","version","publisher","settings") else setOf("id","version","publisher"))
            val id=row.getString("id");require(id.length <= 80 && id.matches(Regex("[a-z][a-z0-9_-]*(\\.[a-z][a-z0-9_-]*)+")) && seen.add(id))
            PluginPackage.version(row.getString("version"));require(row.getString("publisher").matches(Regex("[a-f0-9]{64}")))
            if(row.has("settings")) PluginSettings.validatePortable(row.getJSONObject("settings"),id)
            clean.put(JSONObject(row.toString()))
        }
        return JSONObject().put("version",1).put("inventory",clean)
    }
    fun merge(current: JSONObject,restored: JSONObject?): JSONObject {
        val rows=linkedMapOf<String,JSONObject>()
        for(doc in listOfNotNull(restored,current)) {
            val inventory=validate(doc).getJSONArray("inventory")
            for(i in 0 until inventory.length()) { val row=inventory.getJSONObject(i);rows[row.getString("id")]=row }
        }
        return validate(JSONObject().put("version",1).put("inventory",JSONArray(rows.values.toList())))
    }
    fun read(root: File): JSONObject {
        val rows=JSONArray(); val registry=File(root,"registry.json")
        if(registry.exists()) try {
            val plugins=JSONObject(registry.readText()).getJSONObject("plugins")
            require(plugins.length() <= 128)
            for(id in plugins.keys()) {
                val digest=plugins.getJSONObject(id).getString("active");require(digest.matches(Regex("[a-f0-9]{64}")))
                val file=File(root,"packages/$digest");require(file.length() <= PluginPackage.MAX_BYTES)
                val bytes=file.readBytes();require(PluginPackage.sha(bytes) == digest)
                val p=PluginPackage.parse(bytes)
                rows.put(JSONObject().put("id",p.id).put("version",p.version).put("publisher",p.publisher).put("settings",PluginSettings(File(root,"settings")).export(p)))
            }
        } catch(_: Exception) { return JSONObject().put("version",1).put("inventory",JSONArray()) }
        return validate(JSONObject().put("version",1).put("inventory",rows))
    }
}
