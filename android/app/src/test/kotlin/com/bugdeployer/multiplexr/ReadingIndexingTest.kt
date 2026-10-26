package com.bugdeployer.multiplexr

import java.io.*
import java.util.Base64
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ReadingIndexingTest {
    private val png = Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=")
    private fun zip(vararg entries: Pair<String, ByteArray>): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip -> for ((name, bytes) in entries) { zip.putNextEntry(ZipEntry(name)); zip.write(bytes); zip.closeEntry() } }
        return out.toByteArray()
    }
    private fun epub(opf: String = """<package xmlns="http://www.idpf.org/2007/opf"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Embedded title</dc:title><dc:creator>Author</dc:creator><dc:language>en</dc:language><dc:identifier>isbn:123</dc:identifier><meta name="calibre:series" content="Saga"/></metadata><manifest><item id="two" href="chapter2.xhtml" media-type="application/xhtml+xml"/><item id="one" href="chapter1.xhtml" media-type="application/xhtml+xml"/><item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/></manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>""") = zip(
        "mimetype" to "application/epub+zip".toByteArray(),
        "META-INF/container.xml" to """<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>""".toByteArray(),
        "OPS/book.opf" to opf.toByteArray(), "OPS/chapter1.xhtml" to "<html><p>One</p></html>".toByteArray(),
        "OPS/chapter2.xhtml" to "<html><p>Two</p></html>".toByteArray(), "OPS/cover.png" to png)
    private fun inspect(bytes: ByteArray, format: String, limits: ReadingPublication.Limits = ReadingPublication.Limits(), encoding: String = "utf-8", cancelled: () -> Boolean = { false }): ReadingPublication.Result {
        val directory = java.nio.file.Files.createTempDirectory("reading-test-").toFile()
        try {
            return ReadingPublication.inspect(ByteArrayInputStream(bytes), format, "Fallback.$format", directory, encoding, limits, cancelled)
        } finally { assertTrue(directory.listFiles().orEmpty().isEmpty()); directory.delete() }
    }
    @Test fun epubUsesEmbeddedMetadataAndSpineRatherThanArchiveEntryOrder() {
        val bytes = epub(); val result = inspect(bytes, "epub")
        assertEquals("Embedded title", result.metadata.getString("title"))
        assertEquals("Author", result.metadata.getJSONArray("authors").getString(0))
        assertEquals("Saga", result.metadata.getString("scanSeries"))
        assertEquals("OPS/chapter1.xhtml", result.resources.getJSONObject(0).getString("id"))
        assertEquals("OPS/chapter2.xhtml", result.resources.getJSONObject(1).getString("id"))
        assertArrayEquals(png, result.cover)
        assertEquals(ReadingPublication.hash(bytes), result.fingerprint)
    }
    @Test fun cbzUsesNaturalPageOrderAndComicInfoCoverAndMetadata() {
        val bytes = zip("10.png" to png, "2.png" to png, "1.png" to png,
            "ComicInfo.xml" to """<ComicInfo><Title>Issue</Title><Series>Series</Series><Writer>A, B</Writer><Summary>Summary</Summary><LanguageISO>ja</LanguageISO><Pages><Page Image="1" Type="FrontCover"/></Pages></ComicInfo>""".toByteArray())
        val result = inspect(bytes, "cbz")
        assertEquals(listOf("1.png", "2.png", "10.png"), (0 until result.resources.length()).map { result.resources.getJSONObject(it).getString("id") })
        assertEquals("Issue", result.metadata.getString("title")); assertEquals("Series", result.metadata.getString("scanSeries"))
        assertEquals(2, result.metadata.getJSONArray("authors").length()); assertArrayEquals(png, result.cover)
    }
    @Test fun textEncodingIsExplicitAndMalformedOrOversizeTextFails() {
        val utf16 = "\uFEFFReadable text".toByteArray(Charsets.UTF_16LE)
        assertEquals("utf-16le", inspect(utf16, "txt", encoding = "utf-16le").encoding)
        assertEquals(1, inspect("Hello".toByteArray(), "txt").resources.length())
        for (bytes in listOf(byteArrayOf(-1, -1), ByteArray(0))) assertTrue(runCatching { inspect(bytes, "txt") }.isFailure)
        assertTrue(runCatching { inspect(utf16, "txt") }.isFailure)
        assertTrue(runCatching { inspect("abcd".toByteArray(), "txt", limits = ReadingPublication.Limits(textBytes = 3)) }.isFailure)
    }
    @Test fun archivesRejectTraversalInvalidXmlRemoteResourcesAndCorruption() {
        for (name in listOf("../outside.png", "/outside.png", "C:/outside.png", "a\\outside.png", "a/%2e%2e/outside.png")) {
            assertTrue(name, runCatching { inspect(zip(name to png), "cbz") }.isFailure)
        }
        assertTrue(runCatching { inspect("not a ZIP".toByteArray(), "cbz") }.isFailure)
        assertTrue(runCatching { inspect(epub().copyOf(40), "epub") }.isFailure)
        assertTrue(runCatching { inspect(epub("""<!DOCTYPE package [<!ENTITY x SYSTEM="file:///secret">]><package>&x;</package>"""), "epub") }.isFailure)
        assertTrue(runCatching { inspect(epub("""<package><manifest><item id="a" href="https://example.com/a"/></manifest></package>"""), "epub") }.isFailure)
        assertTrue(runCatching { inspect(zip("1.png" to "invalid image".toByteArray()), "cbz") }.isFailure)
        assertTrue(runCatching { inspect(zip("ComicInfo.xml" to "<broken".toByteArray(), "1.png" to png), "cbz") }.isFailure)
    }
    @Test fun archiveCountCompressedExpandedEntryXmlAndRatioLimitsAreEnforced() {
        val bytes = epub()
        for (limits in listOf(ReadingPublication.Limits(archiveBytes = 20), ReadingPublication.Limits(expandedBytes = 20),
            ReadingPublication.Limits(entryBytes = 20), ReadingPublication.Limits(entries = 1), ReadingPublication.Limits(xmlBytes = 10))) {
            assertTrue(runCatching { inspect(bytes, "epub", limits) }.isFailure)
        }
        assertTrue(runCatching { inspect(zip("padding" to ByteArray(100000), "1.png" to png), "cbz", ReadingPublication.Limits(ratio = 2)) }.isFailure)
        assertTrue(runCatching { inspect(zip("META-INF/encryption.xml" to "<encryption/>".toByteArray(), "1.png" to png), "epub") }.isFailure)
    }
    @Test fun cancellationDuringSpoolingAndDecompressionRemovesTemporaryArchive() {
        assertTrue(runCatching { inspect(epub(), "epub", cancelled = { true }) }.exceptionOrNull() is ReadingScanCancelled)
        var checks = 0
        assertTrue(runCatching { inspect(epub(), "epub", cancelled = { ++checks > 4 }) }.exceptionOrNull() is ReadingScanCancelled)
        val folder = java.nio.file.Files.createTempDirectory("reading-abandoned-").toFile()
        try {
            File(folder, "reading-abandoned.zip").writeText("interrupted")
            File(folder, "keep.txt").writeText("unrelated")
            ReadingPublication.clearAbandoned(folder)
            assertFalse(File(folder, "reading-abandoned.zip").exists())
            assertTrue(File(folder, "keep.txt").exists())
        } finally { File(folder, "keep.txt").delete(); folder.delete() }
    }
    @Test fun naturalOrderRetainsDecimalChaptersSpecialsAndEditionNames() {
        val names = listOf("Chapter 10", "Chapter 2", "Chapter 1.5", "Chapter 1", "Special", "Chapter 1 edition B")
        val sorted = names.sortedWith(ReadingPublication::natural)
        assertEquals(listOf("Chapter 1", "Chapter 1 edition B", "Chapter 1.5", "Chapter 2", "Chapter 10", "Special"), sorted)
        assertEquals(names.size, sorted.toSet().size)
    }
    private inner class Tree : ReadingSourceTree {
        val children = mutableMapOf<String, List<ReadingDocument>>()
        val data = mutableMapOf<String, ByteArray>()
        val missing = mutableSetOf<String>()
        override fun root(uri: String): ReadingDocument { if (uri in missing) error("Missing grant"); return ReadingDocument(uri, uri, uri.substringAfterLast('/'), true) }
        override fun children(document: ReadingDocument): List<ReadingDocument> = children[document.key] ?: emptyList()
        override fun open(document: ReadingDocument): InputStream = ByteArrayInputStream(data[document.key] ?: error("Unreadable"))
        override fun cover(bytes: ByteArray) = "reading-cover:" + ReadingPublication.hash(bytes)
        fun file(key: String, name: String, bytes: ByteArray) = ReadingDocument(key, "content://local/$key", name, false).also { data[key] = bytes }
    }
    private fun collection(subtype: String, vararg roots: String) = JSONObject().put("id", "c").put("subtype", subtype)
        .put("roots", JSONArray(roots.map { JSONObject().put("uri", it).put("name", it.substringAfterLast('/')) }))
    private fun discover(tree: Tree, collection: JSONObject, cancelled: () -> Boolean = { false }): JSONObject {
        val tmp = java.nio.file.Files.createTempDirectory("reading-discovery-").toFile()
        try { return ReadingSourceDiscovery(tree, tmp).discover(collection, "request", cancelled = cancelled, progress = { _, _ -> }) }
        finally { assertTrue(tmp.listFiles().orEmpty().isEmpty()); tmp.delete() }
    }
    @Test fun discoveryMultipleRootsDeduplicatesProviderIdentityAndIgnoresUnsupportedFormats() {
        val tree = Tree(); val shared = tree.file("one", "Book.epub", epub())
        tree.children["content://root/a"] = listOf(shared, tree.file("mobi", "Book.mobi", png))
        tree.children["content://root/b"] = listOf(shared, tree.file("two", "Book.epub", epub()))
        val result = discover(tree, collection("ebook", "content://root/a", "content://root/b"))
        assertEquals(2, result.getJSONArray("sources").length())
        assertEquals(2, result.getJSONArray("roots").length())
        assertTrue(result.getJSONArray("roots").getJSONObject(0).getBoolean("complete"))
    }
    @Test fun imagesBecomeOneTitleWithNaturalInternalPagesAndAmbiguousLayoutsAreReported() {
        val tree = Tree(); val root = "content://root/a"
        val chapter = ReadingDocument("chapter", "content://local/chapter", "Chapter 1", true)
        tree.children[root] = listOf(chapter)
        tree.children[chapter.key] = listOf(tree.file("page10", "10.png", png), tree.file("page2", "2.png", png),
            tree.file("info", "ComicInfo.xml", "<ComicInfo><Title>Sidecar title</Title><Series>Sidecar series</Series></ComicInfo>".toByteArray()))
        var result = discover(tree, collection("comics", root)); var sources = result.getJSONArray("sources")
        assertEquals(1, sources.length()); assertEquals("images", sources.getJSONObject(0).getString("format"))
        assertEquals("2.png", sources.getJSONObject(0).getJSONArray("readingOrder").getJSONObject(0).getString("id"))
        assertEquals("Sidecar title", sources.getJSONObject(0).getJSONObject("metadata").getString("title"))
        tree.children[chapter.key] = tree.children[chapter.key]!! + ReadingDocument("nested", "content://local/nested", "Nested", true)
        result = discover(tree, collection("comics", root)); sources = result.getJSONArray("sources")
        assertTrue(sources.getJSONObject(0).getBoolean("ambiguous")); assertTrue(result.getJSONArray("warnings").length() > 0)
    }
    @Test fun failedRootsAndCorruptPublicationsAreIncompleteAndCancellationIsNeverSwallowed() {
        val tree = Tree(); val root = "content://root/a"
        tree.children[root] = listOf(tree.file("broken", "Broken.epub", byteArrayOf(1, 2)))
        tree.missing.add("content://root/b")
        val result = discover(tree, collection("ebook", root, "content://root/b"))
        assertEquals(0, result.getJSONArray("sources").length())
        assertFalse(result.getJSONArray("roots").getJSONObject(0).getBoolean("complete"))
        assertFalse(result.getJSONArray("roots").getJSONObject(1).getBoolean("complete"))
        assertTrue(runCatching { discover(tree, collection("ebook", root), cancelled = { true }) }.exceptionOrNull() is ReadingScanCancelled)
    }
    @Test fun perSourceTextEncodingsCanIndexMixedEncodingCollections() {
        val tree = Tree(); val root = "content://root/a"
        tree.children[root] = listOf(tree.file("utf8", "One.txt", "Hello".toByteArray()), tree.file("utf16", "Two.txt", "\uFEFFWorld".toByteArray(Charsets.UTF_16LE)))
        val tmp = java.nio.file.Files.createTempDirectory("reading-encoding-").toFile()
        try {
            val result = ReadingSourceDiscovery(tree, tmp).discover(collection("ebook", root), "request", encodings = mapOf("utf16" to "utf-16le"), cancelled = { false }, progress = { _, _ -> })
            assertEquals(2, result.getJSONArray("sources").length())
            assertTrue(result.getJSONArray("roots").getJSONObject(0).getBoolean("complete"))
            assertEquals("utf-16le", result.getJSONArray("sources").getJSONObject(1).getString("encoding"))
        } finally { tmp.delete() }
    }
    @Test fun imageHeadersRejectOversizedDecodeDimensionsAndUnknownFormats() {
        ReadingImage.validate(png)
        val huge = png.copyOf(); for (i in 16..19) huge[i] = 127
        assertTrue(runCatching { ReadingImage.validate(huge) }.isFailure)
        assertTrue(runCatching { ReadingImage.validate(ByteArray(40)) }.isFailure)
    }
    @Test fun selectedTextTypesSkipUnselectedCorruptPublications() {
        val tree=Tree();val root="content://root/a"
        tree.children[root]=listOf(tree.file("txt","One.txt","Readable".toByteArray()),tree.file("bad","Bad.epub",byteArrayOf(1,2)))
        val tmp=java.nio.file.Files.createTempDirectory("reading-filter-").toFile()
        try {
            val result=ReadingSourceDiscovery(tree,tmp,setOf("txt")).discover(collection("ebook",root),"request",cancelled={false},progress={_,_->})
            assertEquals(1,result.getJSONArray("sources").length());assertEquals("txt",result.getJSONArray("sources").getJSONObject(0).getString("format"))
            assertTrue(result.getJSONArray("roots").getJSONObject(0).getBoolean("complete"))
            assertTrue(runCatching{ReadingSourceDiscovery(tree,tmp,setOf("cbz")).discover(collection("ebook",root),"request",cancelled={false},progress={_,_->})}.isFailure)
        } finally {tmp.deleteRecursively()}
    }
    @Test fun imageChaptersCanBeExcludedWithoutChangingSourceFiles() {
        val tree=Tree();val root="content://root/a"
        tree.children[root]=listOf(tree.file("page","1.png",png),tree.file("archive","Issue.cbz",zip("1.png" to png)))
        val tmp=java.nio.file.Files.createTempDirectory("comic-filter-").toFile()
        try {
            val result=ReadingSourceDiscovery(tree,tmp,setOf("cbz")).discover(collection("comics",root),"request",cancelled={false},progress={_,_->})
            assertEquals(1,result.getJSONArray("sources").length());assertEquals("cbz",result.getJSONArray("sources").getJSONObject(0).getString("format"))
            assertTrue(result.getJSONArray("roots").getJSONObject(0).getBoolean("complete"));assertEquals(2,tree.children[root]!!.size)
        } finally {tmp.deleteRecursively()}
    }

}
