package com.bugdeployer.multiplexr

import java.io.*
import java.util.zip.*
import java.security.MessageDigest
import org.json.*
import org.junit.Assert.*
import org.junit.Test

class ReadingComicTest {
    private fun fixture(name: String): JSONObject = generateSequence(File(".").canonicalFile) { it.parentFile }
        .map { File(it, "test/fixtures/$name") }.first { it.isFile }.let { JSONObject(it.readText()) }
    private fun title(format: String = "cbz"): JSONObject = fixture("reading-v1.json").getJSONObject("base").getJSONArray("titles").getJSONObject(2)
        .put("format", format).put("readingOrder", JSONArray().put(JSONObject().put("id", "second").put("href", "page10.png").put("label", "10"))
            .put(JSONObject().put("id", "first").put("href", "page2.png").put("label", "2")))
    private fun png(width: Int = 8, height: Int = 12): ByteArray {
        val output = ByteArrayOutputStream(); output.write(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
        fun chunk(kind: String, data: ByteArray) {
            val stream = DataOutputStream(output); stream.writeInt(data.size); val name = kind.toByteArray(Charsets.US_ASCII)
            stream.write(name); stream.write(data); val crc = CRC32(); crc.update(name); crc.update(data); stream.writeInt(crc.value.toInt())
        }
        val header = ByteArrayOutputStream(); DataOutputStream(header).apply { writeInt(width); writeInt(height); write(byteArrayOf(8, 6, 0, 0, 0)) }
        chunk("IHDR", header.toByteArray())
        val compressed = ByteArrayOutputStream(); DeflaterOutputStream(compressed).use { z -> repeat(height) { z.write(0); repeat(width) { z.write(byteArrayOf(0, 0, 0, -1)) } } }
        chunk("IDAT", compressed.toByteArray()); chunk("IEND", ByteArray(0)); return output.toByteArray()
    }
    private fun archive(entries: List<Pair<String, ByteArray>>): ByteArray {
        val out = ByteArrayOutputStream(); ZipOutputStream(out).use { z -> entries.forEach { (name, bytes) -> z.putNextEntry(ZipEntry(name)); z.write(bytes); z.closeEntry() } }; return out.toByteArray()
    }
    private class Tree(val data: MutableMap<String, ByteArray>) : ReadingSourceTree {
        override fun root(uri: String) = ReadingDocument("root", uri, "Comic", true)
        override fun children(document: ReadingDocument) = data.keys.filter { it != "archive" }.map { ReadingDocument(it, it, it, false) }.reversed()
        override fun open(document: ReadingDocument): InputStream = ByteArrayInputStream(data[if (document.uri.startsWith("content:")) "archive" else document.uri] ?: error("Missing page"))
        override fun cover(bytes: ByteArray) = "unused"
    }
    private fun evidence(bytes: ByteArray) = JSONObject().put("fingerprint", ReadingPublication.hash(bytes))
    private fun folderEvidence(tree: Tree): JSONObject {
        val digest = MessageDigest.getInstance("SHA-256")
        tree.data.keys.sortedWith { a, b -> ReadingPublication.natural(a, b) }.forEach { name -> digest.update(name.toByteArray()); digest.update(0); digest.update(tree.data[name]); digest.update(0) }
        return JSONObject().put("fingerprint", digest.digest().joinToString("") { "%02x".format(it) })
    }
    @Test fun archiveUsesIndexedPageOrderAndExtractsOnlyRequestedPagesThenCleansUp() {
        val bytes = archive(listOf("page2.png" to png(), "page10.png" to png(12, 8)))
        val cache = java.nio.file.Files.createTempDirectory("comic-").toFile(); val files = ReadingComicFiles(cache, Tree(mutableMapOf("archive" to bytes)))
        try {
            val opened = files.open(title(), evidence(bytes)); val token = opened.getString("token")
            assertEquals("second", opened.getJSONArray("pages").getJSONObject(0).getString("id"))
            assertEquals(12, files.page(token, "second").width)
            assertEquals(1, cache.walkTopDown().count { it.isFile })
            assertArrayEquals(png(), files.file(token, "first").readBytes())
            assertEquals(2, cache.walkTopDown().count { it.isFile })
            assertTrue(runCatching { files.file(token, "unindexed") }.isFailure)
            assertTrue(runCatching { files.open(title(), evidence(bytes)) }.isFailure)
            files.closeAll(); assertTrue(cache.listFiles()!!.isEmpty())
            assertTrue(runCatching { files.file(token, "first") }.isFailure)
        } finally { cache.deleteRecursively() }
    }
    @Test fun directoryFingerprintUsesNaturalSourceOrderWhileManualReadingOrderSurvives() {
        val tree = Tree(mutableMapOf("page10.png" to png(12, 8), "page2.png" to png()))
        val evidence = folderEvidence(tree); val cache = java.nio.file.Files.createTempDirectory("comic-folder-").toFile()
        val files = ReadingComicFiles(cache, tree)
        try {
            val opened = files.open(title("images"), evidence); val token = opened.getString("token")
            assertEquals("second", opened.getJSONArray("pages").getJSONObject(0).getString("id"))
            tree.data["page2.png"] = png(20, 20)
            assertArrayEquals(png(), files.file(token, "first").readBytes()) // Immutable verified snapshot.
            files.close(token)
            assertTrue(runCatching { files.open(title("images"), evidence) }.exceptionOrNull() is ReadingTextChanged)
            assertTrue(cache.listFiles()!!.isEmpty())
        } finally { cache.deleteRecursively() }
    }
    @Test fun cancelledChangedOrUnsafeSourcesDoNotLeakHandlesOrCacheFiles() {
        val bytes = archive(listOf("page2.png" to png(), "page10.png" to png()))
        val cache = java.nio.file.Files.createTempDirectory("comic-failed-").toFile(); val files = ReadingComicFiles(cache, Tree(mutableMapOf("archive" to bytes)))
        try {
            assertTrue(runCatching { files.open(title(), evidence(ByteArray(0))) }.exceptionOrNull() is ReadingTextChanged)
            assertTrue(runCatching { files.open(title(), evidence(bytes)) { true } }.exceptionOrNull() is ReadingScanCancelled)
            val bad = title(); bad.getJSONArray("readingOrder").getJSONObject(0).put("href", "../page10.png")
            assertTrue(runCatching { files.open(bad, evidence(bytes)) }.isFailure)
            assertTrue(cache.listFiles()!!.isEmpty())
        } finally { cache.deleteRecursively() }
    }
    @Test fun corruptArchiveCrcFailsAtPageExtractionWithoutKeepingPartialFiles() {
        val bytes = archive(listOf("page2.png" to png(), "page10.png" to png()))
        val central = (0 until bytes.size - 4).first { bytes[it] == 80.toByte() && bytes[it + 1] == 75.toByte() && bytes[it + 2] == 1.toByte() && bytes[it + 3] == 2.toByte() }
        for (i in 16..19) bytes[central + i] = 0
        val cache = java.nio.file.Files.createTempDirectory("comic-crc-").toFile(); val files = ReadingComicFiles(cache, Tree(mutableMapOf("archive" to bytes)))
        try {
            val token = files.open(title(), evidence(bytes)).getString("token")
            assertTrue(runCatching { files.file(token, "first") }.isFailure)
            assertEquals(1, cache.walkTopDown().count { it.isFile })
            files.close(token)
        } finally { cache.deleteRecursively() }
    }
    @Test fun malformedImageBoundsAndMissingPagesAreRejectedAtOpen() {
        val oversized = png(); for (i in 16..19) oversized[i] = 127
        for (entries in listOf(listOf("page2.png" to oversized, "page10.png" to png()), listOf("page2.png" to png()))) {
            val bytes = archive(entries); val cache = java.nio.file.Files.createTempDirectory("comic-bounds-").toFile()
            val files = ReadingComicFiles(cache, Tree(mutableMapOf("archive" to bytes)))
            try { assertTrue(runCatching { files.open(title(), evidence(bytes)) }.isFailure); assertTrue(cache.listFiles()!!.isEmpty()) }
            finally { cache.deleteRecursively() }
        }
    }
    @Test fun decodedRegionsAreBoundedForLongStripsAndHugePages() {
        for ((width, height) in listOf(1000 to 40000, 10000 to 10000, 40000 to 1000, 32 to 40000)) {
            for (target in listOf(64, 512, 1536)) {
                val n = ComicDecodePolicy.sample(width, height, target)
                val w = (width + n - 1) / n; val h = (height + n - 1) / n
                assertTrue(w <= target); assertTrue(w.toLong() * h <= ComicDecodePolicy.MAX_PIXELS)
            }
        }
        assertTrue(runCatching { ComicDecodePolicy.sample(40001, 1, 512) }.isFailure)
    }
    @Test fun conservativeBorderCropPreservesBlankPagesAndInteriorArt() {
        val pixels = IntArray(100 * 100) { -1 }
        for (y in 10..89) for (x in 10..89) pixels[y * 100 + x] = 0xff202020.toInt()
        assertArrayEquals(intArrayOf(10, 10, 90, 90), ComicDecodePolicy.crop(100, 100, pixels))
        assertArrayEquals(intArrayOf(0, 0, 100, 100), ComicDecodePolicy.crop(100, 100, IntArray(10000) { -1 }))
    }
    @Test fun sharedComicPreferencesHaveIdenticalNativeValidation() {
        val fixture = fixture("reading-comic-v1.json"); val cases = fixture.getJSONArray("cases")
        for (i in 0 until cases.length()) {
            val case = cases.getJSONObject(i); val catalog = JSONObject(fixture.getJSONObject("catalog").toString())
            catalog.getJSONArray("settings").getJSONObject(0).put("values", case.getJSONObject("values"))
            assertEquals(case.getString("name"), case.getBoolean("valid"), runCatching { ReadingCatalogCodec.validate(catalog) }.isSuccess)
        }
    }
}
