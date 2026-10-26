package com.bugdeployer.multiplexr

import java.io.*
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class ReadingTextTest {
    @Test fun structuredResourcesPreserveCanonicalAnnotationOffsets() {
        val content = ReadingTextContent.xhtml("""<html><body><p id="start">Hello <a href="#note">note</a>.</p><img src="images/map.png" alt="Map"/><p id="note">Footnote 🚀.</p></body></html>""".toByteArray())
        assertEquals("Hello note.\n[Map]\n\nFootnote 🚀.\n", content.text)
        assertEquals(19, content.anchors["note"])
        val link = content.elements.single { it.getString("kind") == "link" }
        assertEquals(6, link.getInt("offset"))
        assertEquals("#note", link.getString("href"))
        assertEquals("note", link.getString("label"))
        val image = content.elements.single { it.getString("kind") == "image" }
        assertEquals(12, image.getInt("offset"))
        assertEquals("images/map.png", image.getString("href"))
        assertEquals(content.text, content.json().getString("text"))
    }
    private fun fixture(name: String): JSONObject = generateSequence(File(".").canonicalFile) { it.parentFile }
        .map { File(it, "test/fixtures/$name") }.first { it.isFile }.let { JSONObject(it.readText()) }
    private fun title() = fixture("reading-v1.json").getJSONObject("base").getJSONArray("titles").getJSONObject(0)
    private fun epub(): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip -> for ((name, text) in listOf("OPS/chapter1.xhtml" to "<html><body><h1 id=\"heading\">Heading</h1><p>Hello <strong>reader</strong> &amp; world.</p></body></html>",
            "OPS/chapter2.xhtml" to "<html><body><p>Other chapter with a secret phrase.</p></body></html>")) {
            zip.putNextEntry(ZipEntry(name)); zip.write(text.toByteArray()); zip.closeEntry()
        } }
        return out.toByteArray()
    }
    @Test fun normalizedXhtmlHasStableUtf16OffsetsSemanticStylesAndAnchorsWithoutExecutingScriptsOrLoadingExternalDtd() {
        val bytes = """<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "https://example.com/external.dtd"><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Hidden</title><style>red</style></head><body><h1 id="heading">Heading</h1><p id="p">Hello <strong>reader</strong> &amp; <em>world</em> 🚀.</p><script>secret script</script><img src="https://example.com/image" alt="Picture"/></body></html>""".toByteArray()
        val a = ReadingTextContent.xhtml(bytes); val b = ReadingTextContent.xhtml(bytes)
        assertEquals(a.text, b.text); assertEquals(a.anchors, b.anchors)
        assertTrue(a.text.contains("Hello reader & world 🚀.")); assertTrue(a.text.contains("[Picture]"))
        assertFalse(a.text.contains("secret")); assertFalse(a.text.contains("Hidden")); assertFalse(a.text.contains("red"))
        assertEquals(0, a.anchors["heading"])
        assertTrue(a.styles.any { it.getString("kind") == "bold" && a.text.substring(it.getInt("start"), it.getInt("end")) == "reader" })
        assertEquals(a.text.indexOf("Hello"), a.anchors["p"])
    }
    @Test fun nonSpineFootnotesAreLocalBoundedAndDoNotChangeTheReadingOrder() {
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            for ((path, text) in listOf("OPS/chapter1.xhtml" to """<html><body><p>Text <a href="notes.xhtml#note">1</a>.</p></body></html>""",
                "OPS/notes.xhtml" to """<html><body><p id="note">A footnote.</p></body></html>""")) {
                zip.putNextEntry(ZipEntry(path)); zip.write(text.toByteArray()); zip.closeEntry()
            }
        }
        val bytes = output.toByteArray()
        val cache = java.nio.file.Files.createTempDirectory("linked-note-").toFile()
        val files = ReadingTextFiles(cache) { ByteArrayInputStream(bytes) }
        try {
            val original = title()
            val token = files.open(original, JSONObject().put("fingerprint", ReadingPublication.hash(bytes)))
            val content = files.linkedResource(token, "first", "notes.xhtml#note")
            assertEquals("A footnote.\n", content.text)
            assertEquals(0, content.anchors["note"])
            assertEquals(2, original.getJSONArray("readingOrder").length())
            assertTrue(runCatching { files.linkedResource(token, "first", "https://example.com/notes") }.isFailure)
            assertTrue(runCatching { files.linkedResource(token, "first", "../../secret.xhtml") }.isFailure)
            files.close(token)
        } finally { files.closeAll(); cache.deleteRecursively() }
    }
    @Test fun textDecodingNormalizesNewlinesAndRejectsUnsafeXmlOrInvalidEncoding() {
        assertEquals("a\nb\nc🚀", ReadingTextContent.plain("\uFEFFa\r\nb\rc🚀".toByteArray(Charsets.UTF_16LE), "utf-16le").text)
        for (xml in listOf("<!DOCTYPE html [<!ENTITY x SYSTEM='file:///secret'>]><html>&x;</html>", "<html><p>broken</html>")) {
            assertTrue(runCatching { ReadingTextContent.xhtml(xml.toByteArray()) }.isFailure)
        }
        assertTrue(runCatching { ReadingTextContent.plain(byteArrayOf(-1, -1), "utf-8") }.isFailure)
        assertTrue(runCatching { ReadingTextContent.xhtml("<html/>".toByteArray(Charsets.UTF_16LE)) }.isFailure)
    }
    @Test fun verifiedArchiveResourcesSearchOfflineAndCloseRemovesSpoolWithoutTouchingSource() {
        val bytes = epub(); val cache = java.nio.file.Files.createTempDirectory("reader-session-").toFile()
        val files = ReadingTextFiles(cache) { ByteArrayInputStream(bytes) }
        try {
            val token = files.open(title(), JSONObject().put("fingerprint", ReadingPublication.hash(bytes)))
            val resource = files.resource(token, "first")
            assertTrue(resource.text.contains("Hello reader"))
            val results = files.search(token, "secret") { false }.getJSONArray("results")
            assertEquals(1, results.length()); assertEquals("second", results.getJSONObject(0).getString("resourceId"))
            val second = files.resource(token, "second").text
            assertEquals(second.indexOf("secret"), results.getJSONObject(0).getInt("offset"))
            assertTrue(runCatching { files.search(token, "secret") { true } }.exceptionOrNull() is ReadingScanCancelled)
            files.close(token); assertTrue(cache.listFiles().orEmpty().isEmpty())
            assertTrue(runCatching { files.resource(token, "first") }.isFailure)
        } finally { cache.deleteRecursively() }
    }
    @Test fun epubContentsResolveInternalAnchorsAndDropExternalTargets() {
        for (ncx in listOf(false, true)) {
            val out = ByteArrayOutputStream()
            val navName = if (ncx) "toc.ncx" else "nav.xhtml"
            val nav = if (ncx) "<ncx><navMap><navPoint><navLabel><text>Named chapter</text></navLabel><content src=\"chapter1.xhtml#heading\"/></navPoint></navMap></ncx>"
                else "<html xmlns:epub=\"http://www.idpf.org/2007/ops\"><body><nav epub:type=\"toc\"><a href=\"chapter1.xhtml#heading\">Named chapter</a><a href=\"https://example.com\">External</a></nav></body></html>"
            val media = if (ncx) "application/x-dtbncx+xml" else "application/xhtml+xml"
            val properties = if (ncx) "" else " properties=\"nav\""
            val entries = listOf(
                "META-INF/container.xml" to "<container><rootfiles><rootfile full-path=\"OPS/package.opf\"/></rootfiles></container>",
                "OPS/package.opf" to "<package><manifest><item href=\"$navName\" media-type=\"$media\"$properties/></manifest></package>",
                "OPS/$navName" to nav,
                "OPS/chapter1.xhtml" to "<html><body><h1 id=\"heading\">Heading</h1></body></html>")
            ZipOutputStream(out).use { zip -> entries.forEach { (name, text) -> zip.putNextEntry(ZipEntry(name)); zip.write(text.toByteArray()); zip.closeEntry() } }
            val bytes = out.toByteArray(); val cache = java.nio.file.Files.createTempDirectory("reader-toc-").toFile()
            val files = ReadingTextFiles(cache) { ByteArrayInputStream(bytes) }
            try {
                val token = files.open(title(), JSONObject().put("fingerprint", ReadingPublication.hash(bytes)))
                val toc = files.contents(token)
                assertEquals(1, toc.length()); assertEquals("first", toc.getJSONObject(0).getString("resourceId"))
                assertEquals("heading", toc.getJSONObject(0).getString("anchor")); assertEquals("Named chapter", toc.getJSONObject(0).getString("label"))
                files.close(token)
            } finally { cache.deleteRecursively() }
        }
    }
    @Test fun changedSourcesAndCancelledOpeningNeverReturnAUsableHandle() {
        val bytes = epub(); val cache = java.nio.file.Files.createTempDirectory("reader-verify-").toFile()
        val files = ReadingTextFiles(cache) { ByteArrayInputStream(bytes) }
        try {
            assertTrue(runCatching { files.open(title(), JSONObject().put("fingerprint", "a".repeat(64))) }.exceptionOrNull() is ReadingTextChanged)
            assertTrue(cache.listFiles().orEmpty().isEmpty())
            assertTrue(runCatching { files.open(title(), JSONObject().put("fingerprint", ReadingPublication.hash(bytes))) { true } }.exceptionOrNull() is ReadingScanCancelled)
            assertTrue(cache.listFiles().orEmpty().isEmpty())
        } finally { cache.deleteRecursively() }
    }
    @Test fun longPlainPublicationSearchIsBoundedAndCanBeReopenedAfterSessionRecreation() {
        val bytes = "A long paragraph with a needle and emoji 🚀.\n".repeat(25000).toByteArray()
        val title = title().put("format", "txt"); val evidence = JSONObject().put("fingerprint", ReadingPublication.hash(bytes)).put("encoding", "utf-8")
        val cache = java.nio.file.Files.createTempDirectory("reader-long-").toFile()
        try {
            val first = ReadingTextFiles(cache) { ByteArrayInputStream(bytes) }; val token = first.open(title, evidence)
            val text = first.resource(token, "first").text
            val search = first.search(token, "needle") { false }
            assertEquals(200, search.getJSONArray("results").length()); assertTrue(search.getBoolean("truncated"))
            first.close(token)
            val recreated = ReadingTextFiles(cache) { ByteArrayInputStream(bytes) }; val next = recreated.open(title, evidence)
            assertEquals(text, recreated.resource(next, "first").text); recreated.close(next)
        } finally { cache.deleteRecursively() }
    }
    @Test fun sharedDartNativeAnnotationFixturesAgree() {
        val f = fixture("reading-annotations-v1.json"); val cases = f.getJSONArray("cases")
        for (i in 0 until cases.length()) {
            val test = cases.getJSONObject(i); val input = JSONObject(f.getJSONObject("annotations").toString()); val path = test.getJSONArray("path")
            var target: Any = input
            for (j in 0 until path.length() - 1) target = when (val t = target) { is JSONObject -> t.get(path.getString(j)); is JSONArray -> t.get(path.getInt(j)); else -> error("path") }
            when (val t = target) { is JSONObject -> t.put(path.getString(path.length() - 1), test.get("value")); is JSONArray -> t.put(path.getInt(path.length() - 1), test.get("value")) }
            val result = runCatching { ReadingAnnotationsCodec.validate(input, f.getJSONObject("catalog")) }
            assertEquals(test.getString("name") + ": " + result.exceptionOrNull(), test.getBoolean("valid"), result.isSuccess)
        }
    }
    @Test fun annotationsSurviveBackupAndSourceRevisionChangesAndExactCollectionCleanup() {
        val f = fixture("reading-annotations-v1.json"); val catalog = f.getJSONObject("catalog"); val annotations = f.getJSONObject("annotations")
        val backup = BackupCodec.export(emptyList(), emptyList(), JSONArray(), mapOf(ReadingCatalogCodec.KEY to catalog, ReadingAnnotationsCodec.KEY to annotations))
        assertTrue(ReadingIndexCodec.same(annotations, backup.getJSONObject("state").getJSONObject(ReadingAnnotationsCodec.KEY)))
        catalog.getJSONArray("titles").getJSONObject(0).getJSONObject("source").put("revision", "changed")
        assertEquals(1, ReadingAnnotationsCodec.retain(annotations, catalog).getJSONArray("items").length())
        assertEquals(0, CollectionStatePolicy.withoutCollection(ReadingAnnotationsCodec.KEY, annotations, "books:[]")!!.getJSONArray("items").length())
        assertEquals(1, CollectionStatePolicy.withoutCollection(ReadingAnnotationsCodec.KEY, annotations, "books")!!.getJSONArray("items").length())
        val removed = ReadingCatalogCodec.withoutCollection(catalog, "books:[]")
        assertEquals(0, ReadingAnnotationsCodec.retain(annotations, removed).getJSONArray("items").length())
    }
    @Test fun activeReaderRemainsUsableAfterUnusedCacheCleanup() {
        val cache=java.nio.file.Files.createTempDirectory("reading-active-cache").toFile();val bytes=epub()
        val files=ReadingTextFiles(cache){ByteArrayInputStream(bytes)}
        try {
            val token=files.open(title(),JSONObject().put("fingerprint",ReadingPublication.hash(bytes)))
            val idle=File(cache,"session-unused").apply{mkdirs()};File(idle,"old").writeText("Unused")
            val before=files.cacheBytes();files.clearIdleCache()
            assertFalse(idle.exists());assertTrue(files.cacheBytes()>0);assertTrue(files.cacheBytes()<before)
            val resource=title().getJSONArray("readingOrder").getJSONObject(0).getString("id")
            assertTrue(files.resource(token,resource).text.contains("Hello reader"))
            files.close(token);assertEquals(0L,files.cacheBytes())
        } finally {files.closeAll();cache.deleteRecursively()}
    }

}
