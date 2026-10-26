package com.bugdeployer.multiplexr
import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import java.io.File
class ReadingSpacesTest {
    private fun fixture() = JSONObject(File("../../test/fixtures/reading-spaces-v1.json").readText())
    @Test fun sharedReadingSpaceAndListCases() {
        val f=fixture(); val cases=f.getJSONArray("cases")
        for(i in 0 until cases.length()) {
            val c=cases.getJSONObject(i);val value=JSONObject(f.getJSONObject("management").toString());val path=c.getJSONArray("path");var target:Any=value
            for(j in 0 until path.length()-1)target=when(val t=target){is JSONObject->t.get(path.getString(j));is JSONArray->t.get(path.getInt(j));else->error("path")}
            when(val t=target){is JSONObject->t.put(path.getString(path.length()-1),c.get("value"));is JSONArray->t.put(path.getInt(path.length()-1),c.get("value"))}
            assertEquals(c.getString("name"),c.getBoolean("valid"),runCatching{ReadingManagementCodec.validate(value,f.getJSONObject("catalog"))}.isSuccess)
        }
    }
    @Test fun readingListsAndLocalSpaceSurvivePortableBackup() {
        val f=fixture();val m=f.getJSONObject("management");val catalog=f.getJSONObject("catalog")
        val global=JSONObject().put("ebook",m.getJSONArray("spaces").getJSONObject(0).getJSONObject("display"))
        val backup=BackupCodec.export(emptyList(),emptyList(),JSONArray(),mapOf(ReadingCatalogCodec.KEY to catalog,ReadingManagementCodec.KEY to m,"spaces:display" to global))
        val state=BackupCodec.validate(backup).getJSONObject("state")
        assertTrue(ReadingIndexCodec.same(m,state.getJSONObject(ReadingManagementCodec.KEY)))
        assertTrue(ReadingIndexCodec.same(global,state.getJSONObject("spaces:display")))
    }
    @Test fun deletedOwnersPruneListsAndLocalSpacesWithoutAffectingOtherOwners() {
        val f=fixture();val m=f.getJSONObject("management");val catalog=f.getJSONObject("catalog")
        val kept=ReadingManagementCodec.retain(m,ReadingCatalogCodec.withoutCollection(catalog,"comics"))
        assertEquals(1,kept.getJSONArray("lists").length());assertEquals(1,kept.getJSONArray("spaces").length())
        val removed=ReadingManagementCodec.retain(m,ReadingCatalogCodec.withoutCollection(catalog,"books:[]"))
        assertEquals(0,removed.getJSONArray("lists").length());assertEquals(0,removed.getJSONArray("spaces").length());assertEquals(1,removed.getJSONArray("pageNotes").length())
    }
    @Test fun newOptionalRowsCannotModifyAnotherOwnersListsOrSpace() {
        val f=fixture();val catalog=f.getJSONObject("catalog");val index=f.getJSONObject("index");val m=f.getJSONObject("management")
        fun request()=JSONObject().put("catalog",JSONObject(catalog.toString())).put("index",JSONObject(index.toString())).put("management",JSONObject(m.toString())).put("expectedCatalog",JSONObject(catalog.toString())).put("expectedIndex",JSONObject(index.toString())).put("expectedManagement",JSONObject(m.toString()))
        val list=request();list.getJSONObject("management").getJSONArray("lists").getJSONObject(0).put("name","Foreign update")
        assertTrue(runCatching{ReadingManagementCodec.checkCommit("comics",catalog,index,m,list)}.isFailure)
        val space=request();space.getJSONObject("management").getJSONArray("spaces").getJSONObject(0).getJSONObject("display").put("artwork",false)
        assertTrue(runCatching{ReadingManagementCodec.checkCommit("comics",catalog,index,m,space)}.isFailure)
        ReadingManagementCodec.checkCommit("books:[]",catalog,index,m,list)
    }
    @Test fun deletedTitlePrunesOnlyItsCuratedReference() {
        val f=fixture();val catalog=f.getJSONObject("catalog");val titles=catalog.getJSONArray("titles")
        catalog.put("titles",JSONArray((0 until titles.length()).map{titles.getJSONObject(it)}.filter{it.getString("id")!="standalone"}))
        val retained=ReadingManagementCodec.retain(f.getJSONObject("management"),catalog)
        assertEquals("volume",retained.getJSONArray("lists").getJSONObject(0).getJSONArray("titles").getString(0))
        assertEquals(1,retained.getJSONArray("lists").getJSONObject(0).getJSONArray("titles").length())
    }
    @Test fun cacheControlsOnlyClearIdlePrivateSessionFolders() {
        val root=java.nio.file.Files.createTempDirectory("reading-cache-test").toFile()
        try {
            val text=ReadingTextFiles(java.io.File(root,"text")){error("No source requested")}
            val idle=java.io.File(root,"text/session-idle").apply{mkdirs()};java.io.File(idle,"snapshot").writeBytes(ByteArray(1024))
            val unrelated=java.io.File(root,"source.epub").apply{writeText("User source")}
            val other=java.io.File(root,"text/unrelated").apply{writeText("Keep")}
            assertEquals(1028L,text.cacheBytes());text.clearIdleCache()
            assertFalse(idle.exists());assertTrue(unrelated.exists());assertTrue(other.exists());assertEquals(4L,text.cacheBytes())
        } finally {root.deleteRecursively()}
    }

}
