package com.bugdeployer.multiplexr
import org.json.JSONArray
import org.json.JSONObject

object MusicRelinkPolicy {
 fun apply(catalog:JSONObject,extras:JSONObject,collectionId:String,missingId:String,replacementId:String):Pair<JSONObject,JSONObject> {
  require(missingId!=replacementId)
  val result=JSONObject(catalog.toString()); val tracks=result.getJSONArray("tracks")
  fun owns(t:JSONObject,item:String)=t.getJSONObject("id").let{it.getString("collectionId")==collectionId && it.getString("itemId")==item}
  val values=(0 until tracks.length()).map{tracks.getJSONObject(it)}
  val missing=values.single{owns(it,missingId)};val replacement=values.single{owns(it,replacementId)}
  require(!missing.getBoolean("available") && replacement.getBoolean("available"))
  for(field in listOf("source","rootId","folderId")) missing.put(field,replacement.get(field))
  missing.put("available",true)
  missing.getJSONObject("metadata").put("durationMs",replacement.getJSONObject("source").optLong("durationMs"))
  result.put("tracks",JSONArray(values.filterNot{owns(it,replacementId)}))
  val data=JSONObject(extras.toString());val titles=data.getJSONObject("titles")
  val oldKey=JSONArray(listOf("music",collectionId,missingId)).toString();val newKey=JSONArray(listOf("music",collectionId,replacementId)).toString()
  val oldFlags=titles.optJSONObject(oldKey) ?: JSONObject();val newFlags=titles.optJSONObject(newKey) ?: JSONObject()
  for(key in newFlags.keys()) if(!oldFlags.has(key)) oldFlags.put(key,newFlags.get(key))
  titles.put(oldKey,oldFlags);titles.remove(newKey)
  val playlists=data.getJSONArray("playlists")
  for(i in 0 until playlists.length()) { val entries=playlists.getJSONObject(i).getJSONArray("entries");for(j in 0 until entries.length()) {val e=entries.getJSONObject(j);if(e.getString("collectionId")==collectionId && e.getString("titleId")==replacementId)e.put("titleId",missingId)} }
  return MusicCatalogCodec.validate(result) to MusicExtrasCodec.validate(data)
 }
}
