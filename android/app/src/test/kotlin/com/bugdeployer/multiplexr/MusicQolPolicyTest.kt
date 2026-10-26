package com.bugdeployer.multiplexr
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MusicQolPolicyTest {
 private fun track(id:String,available:Boolean)=JSONObject().put("id",JSONObject().put("kind","music").put("collectionId","c").put("itemId",id))
  .put("source",JSONObject().put("id",id).put("uri","content://$id").put("filename","Song.mp3").put("durationMs",60000))
  .put("rootId","root-$id").put("folderId","folder-$id").put("albumId","album")
  .put("metadata",JSONObject().put("title","Title $id").put("cover","data:image/png;base64,AAAA"))
  .put("overrides",JSONObject().put("title","Manual $id")).put("available",available)
 private fun extras()=JSONObject().put("version",1).put("titles",JSONObject().put("[\"music\",\"c\",\"old\"]",JSONObject().put("favorite",true)))
  .put("albums",JSONObject()).put("playlists",JSONArray().put(JSONObject().put("version",1).put("id","p").put("name","Mix").put("collectionId",JSONObject.NULL).put("entries",JSONArray().put(JSONObject().put("id","one").put("collectionId","c").put("titleId","new")).put(JSONObject().put("id","two").put("collectionId","c").put("titleId","old")))))
 @Test fun relinkKeepsOldIdentityAndMetadataAndRemapsAllPlaylistOccurrences() {
  val catalog=JSONObject().put("version",1).put("tracks",JSONArray().put(track("old",false)).put(track("new",true)))
  val result=MusicRelinkPolicy.apply(catalog,extras(),"c","old","new")
  val tracks=result.first.getJSONArray("tracks");assertEquals(1,tracks.length())
  val kept=tracks.getJSONObject(0);assertEquals("old",kept.getJSONObject("id").getString("itemId"));assertEquals("content://new",kept.getJSONObject("source").getString("uri"))
  assertEquals("Manual old",kept.getJSONObject("overrides").getString("title"));assertTrue(kept.getBoolean("available"))
  val entries=result.second.getJSONArray("playlists").getJSONObject(0).getJSONArray("entries")
  assertEquals("old",entries.getJSONObject(0).getString("titleId"));assertEquals("one",entries.getJSONObject(0).getString("id"));assertEquals("two",entries.getJSONObject(1).getString("id"))
  assertEquals(2,catalog.getJSONArray("tracks").length())
 }
 @Test fun relinkRejectsWrongOwnerAndNonmissingSources() {
  val input=JSONObject().put("version",1).put("tracks",JSONArray().put(track("old",true)).put(track("new",true)))
  assertTrue(runCatching{MusicRelinkPolicy.apply(input,extras(),"c","old","new")}.isFailure)
  assertTrue(runCatching{MusicRelinkPolicy.apply(input,extras(),"other","old","new")}.isFailure)
 }
 @Test fun portableArtworkIsDeduplicatedAndValidated() {
  val tracks=JSONArray();for(i in 0..99)tracks.put(track("$i",true))
  val packed=MusicCatalogCodec.packArtwork(JSONObject().put("version",1).put("tracks",tracks))
  assertEquals(1,packed.getJSONObject("artwork").length())
  assertTrue(packed.getJSONArray("tracks").getJSONObject(0).getJSONObject("metadata").getString("cover").startsWith("artwork:"))
  packed.getJSONObject("artwork").keys().asSequence().toList().forEach{packed.getJSONObject("artwork").remove(it)}
  assertTrue(runCatching{MusicCatalogCodec.validate(packed)}.isFailure)
 }
 @Test fun albumManualFieldProvenanceSurvivesBackupCodecValidation() {
  val input=extras();input.getJSONObject("albums").put("[\"c\",\"album\"]",JSONObject().put("title","Mine").put("year",2026).put("metadataSource","musicbrainz").put("manualFields",JSONArray(listOf("title","artist"))))
  assertEquals(2,MusicExtrasCodec.validate(input).getJSONObject("albums").getJSONObject("[\"c\",\"album\"]").getJSONArray("manualFields").length())
 }
}
