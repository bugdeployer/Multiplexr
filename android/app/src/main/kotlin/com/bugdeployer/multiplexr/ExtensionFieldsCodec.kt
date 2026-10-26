package com.bugdeployer.multiplexr
import org.json.JSONArray
import org.json.JSONObject

/** User-owned catalog values survive removal of code and unknown namespaces. */
object ExtensionFieldsCodec {
    const val PREFIX="plugins:fields:"
    private val owned=Regex("[a-z][a-z0-9_-]*(\\.[a-z][a-z0-9_-]*)+:[a-z][a-zA-Z0-9_.-]{0,79}")
    fun owner(key:String):String {
        require(key.startsWith(PREFIX));val parts=JSONArray(key.removePrefix(PREFIX))
        require(parts.length()==3 && parts.getString(0).length in 1..512 && parts.getString(2).length in 1..512)
        require(parts.getString(1) in setOf("movie","television","video","music","audiobook","ebook","comic"))
        return parts.getString(0)
    }
    private fun json(value:Any?,depth:Int=0) {
        require(depth<=8)
        when(value) {
            null, JSONObject.NULL -> Unit
            is String -> require(value.length<=4096)
            is Boolean -> Unit
            is Number -> require(value.toDouble().isFinite())
            is JSONArray -> { require(value.length()<=128);for(i in 0 until value.length())json(value.get(i),depth+1) }
            is JSONObject -> { require(value.length()<=64);for(key in value.keys()) { require(key.length in 1..200);json(value.get(key),depth+1) } }
            else -> error("Invalid extension value")
        }
    }
    fun validate(key:String,input:JSONObject):JSONObject {
        owner(key);require(input.keys().asSequence().toSet().all { it in setOf("version","fields","operations") } && input.has("fields") && input.getInt("version")==1)
        val operations=input.optJSONArray("operations") ?: JSONArray();require(operations.length()<=128)
        for(i in 0 until operations.length()) require(operations.getString(i).matches(Regex("[a-f0-9]{64}")))
        val fields=input.getJSONObject("fields");require(fields.length()<=128)
        for(name in fields.keys()) { require(owned.matches(name));json(fields.get(name)) }
        require(input.toString().toByteArray(Charsets.UTF_8).size<=32768)
        return JSONObject(input.toString())
    }
    fun merge(key:String,before:JSONObject?,plugin:String,patch:JSONObject,operation:String?=null):JSONObject {
        require(patch.length()<=64)
        val receipt=operation?.let { java.security.MessageDigest.getInstance("SHA-256").digest(it.toByteArray(Charsets.UTF_8)).joinToString("") { b -> "%02x".format(b) } }
        val operations=before?.optJSONArray("operations") ?: JSONArray()
        if(receipt!=null && (0 until operations.length()).any { operations.getString(it)==receipt }) return validate(key,before!!)
        val fields=if(before==null)JSONObject() else validate(key,before).getJSONObject("fields")
        for(name in patch.keys()) {
            require(name.startsWith("$plugin:") && owned.matches(name));val value=patch.get(name);json(value)
            if(value==JSONObject.NULL)fields.remove(name) else fields.put(name,value)
        }
        if(receipt!=null) { if(operations.length()>=128) operations.remove(0);operations.put(receipt) }
        return validate(key,JSONObject().put("version",1).put("fields",fields).put("operations",operations))
    }
}
