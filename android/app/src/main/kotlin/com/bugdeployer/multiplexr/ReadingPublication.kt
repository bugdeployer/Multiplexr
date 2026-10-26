package com.bugdeployer.multiplexr

import java.io.*
import java.net.URI
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.zip.ZipFile
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element
import org.json.JSONArray
import org.json.JSONObject

class ReadingScanCancelled : Exception("Reading scan cancelled; existing publications were kept.")

/** No extraction, network access or renderer. All file/archive reads are bounded. */
object ReadingPublication {
    fun clearAbandoned(temporaryDirectory: File) {
        temporaryDirectory.mkdirs()
        val folder = temporaryDirectory.canonicalFile
        for (file in folder.listFiles().orEmpty()) if (file.name.startsWith("reading-") && file.name.endsWith(".zip") &&
            file.canonicalFile.parentFile == folder && file.isFile) check(file.delete()) { "Cannot clean abandoned reading spool." }
    }
    data class Limits(val archiveBytes: Long = 256L * 1024 * 1024, val expandedBytes: Long = 512L * 1024 * 1024,
        val entryBytes: Long = 32L * 1024 * 1024, val entries: Int = 10000, val ratio: Long = 200,
        val xmlBytes: Int = 2 * 1024 * 1024, val textBytes: Int = 16 * 1024 * 1024, val coverBytes: Int = 8 * 1024 * 1024)
    data class Result(val metadata: JSONObject, val resources: JSONArray, val fingerprint: String, val cover: ByteArray?, val encoding: String)
    fun check(cancelled: () -> Boolean) { if (cancelled()) throw ReadingScanCancelled() }
    fun natural(a: String, b: String): Int {
        val chunks = Regex("[0-9]+|[^0-9]+")
        val left = chunks.findAll(a.lowercase()).map { it.value }.toList()
        val right = chunks.findAll(b.lowercase()).map { it.value }.toList()
        for (i in 0 until minOf(left.size, right.size)) {
            val x = left[i]; val y = right[i]
            val order = if (x.first().isDigit() && y.first().isDigit()) {
                val nx = x.trimStart('0').ifEmpty { "0" }; val ny = y.trimStart('0').ifEmpty { "0" }
                nx.length.compareTo(ny.length).takeIf { it != 0 } ?: nx.compareTo(ny)
            } else x.compareTo(y)
            if (order != 0) return order
        }
        return left.size.compareTo(right.size).takeIf { it != 0 } ?: a.compareTo(b)
    }
    fun metadata(title: String) = JSONObject().put("title", title.take(4096)).put("authors", JSONArray())
        .put("description", "").put("language", "").put("identifier", "")
    fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    fun href(path: String): String = URI(null, null, path, null).toASCIIString()
    fun safePath(path: String): String {
        require(path.isNotEmpty() && path.length <= 4096 && !path.startsWith('/') && !path.contains('\\') && !path.contains(':') &&
            path.none { it.code < 32 } && path.split('/').none { it == ".." || it == "." }) { "Unsafe archive path." }
        // Encoded traversal must not become a second spelling of an entry.
        require(!Regex("%(2e|2f|5c|00)", RegexOption.IGNORE_CASE).containsMatchIn(path)) { "Encoded archive traversal." }
        return path
    }
    private fun read(input: InputStream, limit: Long, cancelled: () -> Boolean, consume: (ByteArray, Int) -> Unit): Long {
        var total = 0L; val buffer = ByteArray(16384)
        while (true) {
            check(cancelled); val count = input.read(buffer); if (count < 0) return total
            total += count; require(total <= limit) { "Publication exceeds supported size." }; consume(buffer, count)
        }
    }
    private fun bytes(input: InputStream, limit: Int, cancelled: () -> Boolean): ByteArray {
        val output = ByteArrayOutputStream(); read(input, limit.toLong(), cancelled) { b, n -> output.write(b, 0, n) }; return output.toByteArray()
    }
    internal fun xml(bytes: ByteArray): Element {
        // Check before parsing as well as disabling parser entity support (Android providers vary).
        val spelling = String(bytes, Charsets.UTF_8)
        require(!Regex("<!\\s*(DOCTYPE|ENTITY)", RegexOption.IGNORE_CASE).containsMatchIn(spelling) && !bytes.contains(0)) { "Unsafe publication XML." }
        val factory = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true; isExpandEntityReferences = false
            // The byte-level DTD/entity and NUL rejection above also protects
            // Android XML providers that do not implement these optional flags.
            runCatching { setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) }
            runCatching { setFeature("http://xml.org/sax/features/external-general-entities", false) }
            runCatching { setFeature("http://xml.org/sax/features/external-parameter-entities", false) }
        }
        val builder = factory.newDocumentBuilder()
        builder.setEntityResolver { _, _ -> throw IllegalArgumentException("External entities are disabled.") }
        return builder.parse(ByteArrayInputStream(bytes)).documentElement
    }
    internal fun elements(root: Element, name: String): List<Element> = root.getElementsByTagNameNS("*", name).let { a -> (0 until a.length).map { a.item(it) as Element } }
    private fun text(root: Element, name: String) = elements(root, name).firstOrNull()?.textContent?.trim().orEmpty().take(4096)

    fun comicInfo(metadata: JSONObject, input: InputStream, pageCount: Int, cancelled: () -> Boolean): Int? {
        val info = xml(bytes(input, 2 * 1024 * 1024, cancelled))
        val title = text(info, "Title"); if (title.isNotEmpty()) metadata.put("title", title)
        val writer = text(info, "Writer"); if (writer.isNotEmpty()) metadata.put("authors", JSONArray(writer.split(',').map(String::trim).filter(String::isNotEmpty).take(100)))
        metadata.put("description", text(info, "Summary")).put("language", text(info, "LanguageISO"))
        val series = text(info, "Series"); if (series.isNotEmpty()) metadata.put("scanSeries", series)
        var cover: Int? = null
        for (page in elements(info, "Page")) if (page.getAttribute("Type") == "FrontCover") {
            val index = page.getAttribute("Image").toIntOrNull(); require(index != null && index in 0 until pageCount)
            require(cover == null) { "Ambiguous comic front cover." }; cover = index
        }
        return cover
    }

    fun inspect(input: InputStream, format: String, filename: String, temporaryDirectory: File,
        encoding: String = "utf-8", limits: Limits = Limits(), cancelled: () -> Boolean = { false }): Result {
        require(format in setOf("epub", "txt", "cbz"))
        val guessed = filename.substringBeforeLast('.').ifBlank { "Untitled" }
        if (format == "txt") {
            require(encoding in setOf("utf-8", "utf-16le", "utf-16be", "windows-1252")) { "Choose a supported text encoding." }
            val raw = bytes(input, limits.textBytes, cancelled)
            require(raw.isNotEmpty()) { "Text publication is empty." }
            val decoder = charset(encoding).newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
            val decoded = decoder.decode(java.nio.ByteBuffer.wrap(raw)).toString().removePrefix("\uFEFF")
            require(!decoded.contains('\u0000')) { "Choose the correct text encoding." }
            return Result(metadata(guessed), JSONArray().put(JSONObject().put("id", "text").put("href", "publication.txt").put("label", guessed.take(4096))), hash(raw), null, encoding)
        }
        temporaryDirectory.mkdirs()
        val temporary = File.createTempFile("reading-", ".zip", temporaryDirectory)
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            temporary.outputStream().use { output -> read(input, limits.archiveBytes, cancelled) { b, n -> output.write(b, 0, n); digest.update(b, 0, n) } }
            val fingerprint = digest.digest().joinToString("") { "%02x".format(it) }
            return ZipFile(temporary).use { archive ->
                val entries = linkedMapOf<String, java.util.zip.ZipEntry>(); var expanded = 0L
                val all = archive.entries(); var count = 0
                while (all.hasMoreElements()) {
                    check(cancelled); val entry = all.nextElement(); require(++count <= limits.entries) { "Too many archive entries." }
                    val name = safePath(entry.name)
                    require(entries.put(name, entry) == null) { "Duplicate archive entry." }
                    require(entry.size in 0..limits.entryBytes && entry.compressedSize >= 0) { "Invalid archive size." }
                    require(entry.size <= maxOf(1L, entry.compressedSize) * limits.ratio) { "Archive compression ratio exceeds limit." }
                    val crc = java.util.zip.CRC32()
                    val image = entry.name.substringAfterLast('.').lowercase() in setOf("jpg", "jpeg", "png", "webp") && !entry.isDirectory
                    val prefix = ByteArrayOutputStream()
                    val actual = archive.getInputStream(entry).use { stream -> read(stream, limits.entryBytes, cancelled) { b, n ->
                        crc.update(b, 0, n)
                        if (image && prefix.size() < 262144) prefix.write(b, 0, minOf(n, 262144 - prefix.size()))
                    } }
                    if (image) ReadingImage.validate(prefix.toByteArray())
                    require(actual == entry.size && crc.value == entry.crc) { "Corrupt archive entry." }
                    expanded += actual; require(expanded <= limits.expandedBytes) { "Archive expansion exceeds limit." }
                }
                require(entries.isNotEmpty()) { "Empty publication archive." }
                fun entryBytes(name: String, limit: Int): ByteArray {
                    val entry = entries[name] ?: error("Publication references a missing resource: $name")
                    require(!entry.isDirectory)
                    return archive.getInputStream(entry).use { bytes(it, limit, cancelled) }
                }
                val metadata = metadata(guessed); val resources = JSONArray(); var coverPath: String? = null
                if (format == "epub") {
                    require(String(entryBytes("mimetype", 128), Charsets.US_ASCII).trim() == "application/epub+zip") { "Not an EPUB publication." }
                    require(!entries.containsKey("META-INF/encryption.xml")) { "Encrypted EPUB resources are not supported." }
                    val container = xml(entryBytes("META-INF/container.xml", limits.xmlBytes))
                    val packages = elements(container, "rootfile"); require(packages.size == 1) { "Ambiguous EPUB package." }
                    val packagePath = safePath(packages.single().getAttribute("full-path"))
                    val packageXml = xml(entryBytes(packagePath, limits.xmlBytes))
                    val embeddedTitle = text(packageXml, "title"); if (embeddedTitle.isNotEmpty()) metadata.put("title", embeddedTitle)
                    metadata.put("authors", JSONArray(elements(packageXml, "creator").map { it.textContent.trim().take(4096) }.filter { it.isNotEmpty() }.take(100)))
                    for (key in listOf("description", "language", "identifier")) metadata.put(key, text(packageXml, key))
                    val meta = elements(packageXml, "meta")
                    val calibre = meta.firstOrNull { it.getAttribute("name") == "calibre:series" }?.getAttribute("content").orEmpty()
                    val epubSeries = meta.firstOrNull { item -> item.getAttribute("property") == "belongs-to-collection" &&
                        meta.any { it.getAttribute("refines") == "#${item.getAttribute("id")}" && it.getAttribute("property") == "collection-type" && it.textContent.trim() == "series" } }?.textContent.orEmpty()
                    if ((calibre.ifEmpty { epubSeries }).isNotBlank()) metadata.put("scanSeries", calibre.ifEmpty { epubSeries }.trim().take(4096))
                    val manifest = linkedMapOf<String, Pair<String, String>>()
                    for (item in elements(packageXml, "item")) {
                        val id = item.getAttribute("id"); require(id.isNotBlank() && id !in manifest)
                        val resource = URI(href(packagePath)).resolve(item.getAttribute("href"))
                        require(!resource.isAbsolute && resource.rawAuthority == null && resource.query == null && resource.fragment == null)
                        val path = safePath(resource.path); require(path in entries) { "Missing EPUB manifest resource." }
                        manifest[id] = path to item.getAttribute("media-type")
                        if (item.getAttribute("properties").split(' ').contains("cover-image")) coverPath = path
                    }
                    val oldCover = elements(packageXml, "meta").firstOrNull { it.getAttribute("name") == "cover" }?.getAttribute("content")
                    if (coverPath == null && oldCover != null) coverPath = manifest[oldCover]?.first
                    val seen = mutableSetOf<String>()
                    for (ref in elements(packageXml, "itemref")) {
                        val id = ref.getAttribute("idref"); val resource = manifest[id] ?: error("Missing EPUB spine reference.")
                        require(seen.add(id) && resource.second in setOf("application/xhtml+xml", "text/html")) { "Unsupported or duplicate EPUB spine item." }
                        resources.put(JSONObject().put("id", resource.first).put("href", href(resource.first)).put("label", resource.first.substringAfterLast('/').take(4096)))
                    }
                } else {
                    val pages = entries.values.filter { !it.isDirectory && it.name.substringAfterLast('.').lowercase() in setOf("jpg", "jpeg", "png", "webp") }
                        .sortedWith { a, b -> natural(a.name, b.name) }
                    for (page in pages) resources.put(JSONObject().put("id", page.name).put("href", href(page.name)).put("label", page.name.substringAfterLast('/').take(4096)))
                    coverPath = pages.firstOrNull()?.name
                    entries["ComicInfo.xml"]?.let {
                        val selected = comicInfo(metadata, ByteArrayInputStream(entryBytes("ComicInfo.xml", limits.xmlBytes)), pages.size, cancelled)
                        if (selected != null) coverPath = pages[selected].name
                    }
                }
                require(resources.length() > 0) { "Publication has no readable resources." }
                Result(metadata, resources, fingerprint, coverPath?.let { entryBytes(it, limits.coverBytes) }, "")
            }
        } finally { temporary.delete() }
    }
}
