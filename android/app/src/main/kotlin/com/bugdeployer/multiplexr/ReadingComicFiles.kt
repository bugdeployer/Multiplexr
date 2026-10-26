package com.bugdeployer.multiplexr

import java.io.*
import java.security.MessageDigest
import java.util.zip.ZipFile
import org.json.JSONArray
import org.json.JSONObject

/** Verified immutable disk snapshot. Original source files are never changed. */
class ReadingComicFiles(private val cache: File, private val tree: ReadingSourceTree) {
    data class Page(val id: String, val href: String, val width: Int, val height: Int) {
        fun json() = JSONObject().put("id", id).put("width", width).put("height", height)
    }
    private data class Handle(val folder: File, val archive: ZipFile?, val pages: List<Page>,
        val local: MutableMap<String, File>, val extracted: LinkedHashMap<String, File> = linkedMapOf())
    private val handles = mutableMapOf<String, Handle>()
    init { cache.mkdirs(); cache.listFiles().orEmpty().filter { it.name.startsWith("session-") && it.canonicalFile.parentFile == cache.canonicalFile }.forEach { it.deleteRecursively() } }
    private fun digest() = MessageDigest.getInstance("SHA-256")
    private fun hex(d: MessageDigest) = d.digest().joinToString("") { "%02x".format(it) }
    private fun copy(input: InputStream, file: File, maximum: Long, hash: MessageDigest?, cancelled: () -> Boolean): Long {
        var size = 0L
        input.use { stream -> file.outputStream().use { output ->
            val buffer = ByteArray(16384)
            while (true) { ReadingPublication.check(cancelled); val n = stream.read(buffer); if (n < 0) break
                size += n; require(size <= maximum) { "Comic source exceeds capacity." }; output.write(buffer, 0, n); hash?.update(buffer, 0, n)
            }
        } }
        require(size > 0); return size
    }
    private fun dimensions(input: InputStream): Pair<Int, Int> = input.use {
        val header = ByteArray(262144); var count = 0
        while (count < header.size) { val n = it.read(header, count, header.size - count); if (n < 0) break; count += n }
        ReadingImage.dimensions(header.copyOf(count))
    }
    fun open(title: JSONObject, evidence: JSONObject, cancelled: () -> Boolean = { false }): JSONObject {
        require(handles.isEmpty() && title.getString("subtype") == "comics") { "A comic reader is already open." }
        val folder = File(cache, "session-${java.util.UUID.randomUUID()}").apply { check(mkdirs()) }
        var archive: ZipFile? = null
        try {
            val format = title.getString("format"); require(format in setOf("cbz", "images"))
            val order = title.getJSONArray("readingOrder"); require(order.length() in 1..10000)
            val local = mutableMapOf<String, File>(); val hash = digest()
            val source = title.getJSONObject("source")
            if (format == "cbz") {
                val file = File(folder, "publication.cbz")
                copy(tree.open(ReadingDocument("source", source.getString("uri"), "Comic", false)), file, 256L * 1024 * 1024, hash, cancelled)
                if (hex(hash) != evidence.getString("fingerprint")) throw ReadingTextChanged()
                archive = ZipFile(file)
                val names = mutableSetOf<String>(); var expanded = 0L
                val entries = archive.entries()
                while (entries.hasMoreElements()) {
                    ReadingPublication.check(cancelled)
                    val entry = entries.nextElement(); ReadingPublication.safePath(entry.name)
                    require(names.add(entry.name) && names.size <= 10000) { "Invalid comic archive entries." }
                    require(entry.size in 0..32L * 1024 * 1024 && entry.compressedSize >= 0 && entry.size <= maxOf(1L, entry.compressedSize) * 200) { "Comic archive entry exceeds capacity." }
                    expanded += entry.size; require(expanded <= 512L * 1024 * 1024) { "Comic archive expansion exceeds capacity." }
                }
            } else {
                val doc = ReadingDocument("source", source.getString("uri"), "Comic", true)
                val images = tree.children(doc).filter { !it.directory && it.name.substringAfterLast('.').lowercase() in setOf("jpg", "jpeg", "png", "webp") }
                    .sortedWith { a, b -> ReadingPublication.natural(a.name, b.name) }
                require(images.size == order.length() && images.map { it.name }.toSet().size == images.size) { "Page set changed; scan the source again." }
                var total = 0L
                for ((i, image) in images.withIndex()) {
                    ReadingPublication.safePath(image.name); hash.update(image.name.toByteArray(Charsets.UTF_8)); hash.update(0)
                    val file = File(folder, "page-$i")
                    total += copy(tree.open(image), file, 32L * 1024 * 1024, hash, cancelled)
                    require(total <= 512L * 1024 * 1024); hash.update(0); local[image.name] = file
                }
                if (hex(hash) != evidence.getString("fingerprint")) throw ReadingTextChanged()
            }
            val pages = (0 until order.length()).map { i ->
                ReadingPublication.check(cancelled)
                val r = order.getJSONObject(i); val uri = java.net.URI(r.getString("href"))
                require(!uri.isAbsolute && uri.rawAuthority == null && uri.query == null && uri.fragment == null)
                val path = ReadingPublication.safePath(uri.path)
                val size = if (archive != null) {
                    val entry = archive.getEntry(path) ?: error("Comic page is missing.")
                    require(entry.size in 1..32L * 1024 * 1024 && entry.size <= maxOf(1L, entry.compressedSize) * 200)
                    dimensions(archive.getInputStream(entry))
                } else dimensions((local[path] ?: error("Comic page is missing.")).inputStream())
                Page(r.getString("id"), path, size.first, size.second)
            }
            ReadingPublication.check(cancelled)
            val token = java.util.UUID.randomUUID().toString()
            handles[token] = Handle(folder, archive, pages, local)
            return JSONObject().put("token", token).put("pages", JSONArray(pages.map { it.json() }))
        } catch (e: Exception) { archive?.close(); folder.deleteRecursively(); throw e }
    }
    fun page(token: String, id: String): Page = handles[token]?.pages?.single { it.id == id } ?: error("Comic session expired.")
    fun file(token: String, id: String): File {
        val h = handles[token] ?: error("Comic session expired."); val page = page(token, id)
        h.local[page.href]?.let { return it }; h.extracted[id]?.let { return it }
        val zip = h.archive ?: error("Comic page missing."); val entry = zip.getEntry(page.href) ?: error("Comic page missing.")
        val file = File(h.folder, "decoded-source-${java.util.UUID.randomUUID()}")
        try {
            copy(zip.getInputStream(entry), file, 32L * 1024 * 1024, null) { false }
            val crc = java.util.zip.CRC32(); file.inputStream().use { input -> val b = ByteArray(16384); while (true) { val n = input.read(b); if (n < 0) break; crc.update(b, 0, n) } }
            require(file.length() == entry.size && crc.value == entry.crc) { "Comic page is corrupt." }
            if (h.extracted.size >= 2) { val first = h.extracted.keys.first(); check(h.extracted.remove(first)!!.delete()) }
            h.extracted[id] = file; return file
        } catch (e: Exception) { file.delete(); throw e }
    }
    fun cacheBytes(): Long = cache.listFiles().orEmpty().filter { it.canonicalFile.parentFile == cache.canonicalFile }.sumOf { folder -> folder.walkTopDown().filter { it.isFile && it.canonicalPath.startsWith(cache.canonicalPath + File.separator) }.sumOf { it.length() } }
    fun clearIdleCache() {
        val active = handles.values.map { it.folder.canonicalFile }.toSet()
        for (folder in cache.listFiles().orEmpty()) if (folder.name.startsWith("session-") && folder.canonicalFile.parentFile == cache.canonicalFile && folder.canonicalFile !in active) check(folder.deleteRecursively())
    }
    fun closeAll() { handles.keys.toList().forEach { runCatching { close(it) } } }
    fun close(token: String) { handles.remove(token)?.let { try { it.archive?.close() } finally { check(it.folder.deleteRecursively()) } } }
}

/** Pure decode/crop policy shared by Android rendering and JVM tests. */
object ComicDecodePolicy {
    const val MAX_PIXELS = 524288
    fun sample(width: Int, height: Int, targetWidth: Int): Int {
        require(width in 1..40000 && height in 1..40000 && targetWidth in 64..1536)
        var n = 1
        while ((width + n - 1) / n > targetWidth || (width.toLong() + n - 1) / n * ((height.toLong() + n - 1) / n) > MAX_PIXELS) n *= 2
        return n
    }
    /** Conservative uniform-edge crop; never removes more than one quarter per edge. */
    fun crop(width: Int, height: Int, pixels: IntArray): IntArray {
        require(width > 0 && height > 0 && pixels.size == width * height)
        val edge = pixels[0]
        fun same(p: Int) = listOf(0, 8, 16).all { kotlin.math.abs(((p shr it) and 255) - ((edge shr it) and 255)) <= 16 }
        fun row(y: Int) = (0 until width).all { same(pixels[y * width + it]) }
        fun col(x: Int) = (0 until height).all { same(pixels[it * width + x]) }
        var l = 0; var t = 0; var r = width; var b = height
        while (t < height / 4 && row(t)) t++
        while (b > height * 3 / 4 && row(b - 1)) b--
        while (l < width / 4 && col(l)) l++
        while (r > width * 3 / 4 && col(r - 1)) r--
        // Uniform/blank pages have no detected content, so preserve them.
        if (pixels.all(::same)) return intArrayOf(0, 0, width, height)
        return intArrayOf(l, t, r, b)
    }
}
