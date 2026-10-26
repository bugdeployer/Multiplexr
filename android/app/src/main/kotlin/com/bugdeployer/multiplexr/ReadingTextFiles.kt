package com.bugdeployer.multiplexr

import java.io.*
import java.security.MessageDigest
import java.util.zip.ZipFile
import org.json.JSONArray
import org.json.JSONObject

class ReadingTextChanged : IllegalStateException("The source changed. Scan it again before resuming.")

/** Verified, offline publication handles. At most two sessions, two cached resources. */
class ReadingTextFiles(private val cache: File, private val openSource: (String) -> InputStream) {
    private data class Handle(val folder: File, val title: JSONObject, val archive: ZipFile?, val plain: ReadingTextContent.Content?,
        val resources: LinkedHashMap<String, ReadingTextContent.Content> = linkedMapOf())
    private val handles = linkedMapOf<String, Handle>()
    init { cache.mkdirs(); cache.listFiles().orEmpty().filter { it.name.startsWith("session-") && it.canonicalFile.parentFile == cache.canonicalFile }.forEach { it.deleteRecursively() } }
    fun open(title: JSONObject, evidence: JSONObject, cancelled: () -> Boolean = { false }): String {
        require(title.getString("subtype") == "ebook" && title.getString("format") in setOf("epub", "txt") && handles.size < 2)
        val folder = File(cache, "session-${java.util.UUID.randomUUID()}").apply { check(mkdirs()) }
        try {
            val file = File(folder, "publication"); val digest = MessageDigest.getInstance("SHA-256")
            val limit = if (title.getString("format") == "txt") 16L * 1024 * 1024 else 256L * 1024 * 1024
            var total = 0L
            openSource(title.getJSONObject("source").getString("uri")).use { input -> file.outputStream().use { output ->
                val bytes = ByteArray(16384)
                while (true) { ReadingPublication.check(cancelled); val n = input.read(bytes); if (n < 0) break; total += n; require(total <= limit); output.write(bytes, 0, n); digest.update(bytes, 0, n) }
            } }
            val fingerprint = digest.digest().joinToString("") { "%02x".format(it) }
            if (fingerprint != evidence.getString("fingerprint")) throw ReadingTextChanged()
            val archive = if (title.getString("format") == "epub") ZipFile(file) else null
            val plain = if (archive == null) ReadingTextContent.plain(file.readBytes(), evidence.getString("encoding").ifEmpty { "utf-8" }) else null
            val token = java.util.UUID.randomUUID().toString()
            handles[token] = Handle(folder, JSONObject(title.toString()), archive, plain)
            return token
        } catch (e: Exception) { folder.deleteRecursively(); throw e }
    }
    fun resource(token: String, resourceId: String): ReadingTextContent.Content {
        val h = handles[token] ?: error("Reading session expired; reopen the title.")
        h.resources[resourceId]?.let { return it }
        val order = h.title.getJSONArray("readingOrder")
        val resource = (0 until order.length()).map { order.getJSONObject(it) }.single { it.getString("id") == resourceId }
        val result = h.plain ?: run {
            val path = java.net.URI(resource.getString("href")); require(!path.isAbsolute && path.rawAuthority == null)
            val entry = h.archive!!.getEntry(ReadingPublication.safePath(path.path)) ?: error("Missing publication resource.")
            require(entry.size in 0..32L * 1024 * 1024 && entry.size <= maxOf(1, entry.compressedSize) * 200)
            val bytes = h.archive.getInputStream(entry).use { it.readBytesBounded(32 * 1024 * 1024) }
            val crc = java.util.zip.CRC32().apply { update(bytes) }
            require(bytes.size.toLong() == entry.size && crc.value == entry.crc)
            ReadingTextContent.xhtml(bytes)
        }
        if (h.resources.size >= 2) h.resources.remove(h.resources.keys.first())
        h.resources[resourceId] = result
        return result
    }
    fun linkedResource(token: String, resourceId: String, href: String): ReadingTextContent.Content {
        val h = handles[token] ?: error("Reading session expired.")
        require(resource(token, resourceId).elements.any { it.optString("kind") == "link" && it.optString("href") == href })
        val order = h.title.getJSONArray("readingOrder")
        val source = (0 until order.length()).map { order.getJSONObject(it) }.single { it.getString("id") == resourceId }
        val uri = java.net.URI(source.getString("href")).resolve(href)
        require(!uri.isAbsolute && uri.rawAuthority == null && uri.query == null)
        val path = ReadingPublication.safePath(uri.path)
        require(path.substringAfterLast('.').lowercase() in setOf("xhtml", "html", "htm"))
        val zip = h.archive ?: error("No publication archive.")
        val entry = zip.getEntry(path) ?: error("Missing linked resource.")
        require(entry.size in 1..2L * 1024 * 1024 && entry.size <= maxOf(1, entry.compressedSize) * 200)
        val bytes = zip.getInputStream(entry).use { it.readBytesBounded(2 * 1024 * 1024) }
        require(bytes.size.toLong() == entry.size && java.util.zip.CRC32().apply { update(bytes) }.value == entry.crc)
        return ReadingTextContent.xhtml(bytes)
    }
    fun image(token: String, resourceId: String, href: String): ByteArray {
        val h = handles[token] ?: error("Reading session expired.")
        require(resource(token, resourceId).elements.any { it.optString("kind") == "image" && it.optString("href") == href })
        val order = h.title.getJSONArray("readingOrder")
        val resource = (0 until order.length()).map { order.getJSONObject(it) }.single { it.getString("id") == resourceId }
        val uri = java.net.URI(resource.getString("href")).resolve(href)
        require(!uri.isAbsolute && uri.rawAuthority == null && uri.query == null && uri.fragment == null)
        val path = ReadingPublication.safePath(uri.path)
        require(path.substringAfterLast('.').lowercase() in setOf("png", "jpg", "jpeg", "webp")) { "Unsupported illustration format." }
        val zip = h.archive ?: error("No publication archive.")
        val entry = zip.getEntry(path) ?: error("Missing illustration.")
        require(entry.size in 1..8L * 1024 * 1024 && entry.size <= maxOf(1, entry.compressedSize) * 200)
        return zip.getInputStream(entry).use { it.readBytesBounded(8 * 1024 * 1024) }.also { ReadingImage.validate(it) }
    }
    fun search(token: String, query: String, cancelled: () -> Boolean): JSONObject {
        require(query.trim().length in 2..200)
        val h = handles[token] ?: error("Reading session expired")
        val order = h.title.getJSONArray("readingOrder"); val results = JSONArray(); var truncated = false
        outer@ for (i in 0 until order.length()) {
            ReadingPublication.check(cancelled)
            val id = order.getJSONObject(i).getString("id"); val text = resource(token, id).text
            var offset = 0
            while (offset < text.length) {
                ReadingPublication.check(cancelled)
                val found = text.indexOf(query, offset, ignoreCase = true); if (found < 0) break
                if (results.length() >= 200) { truncated = true; break@outer }
                results.put(JSONObject().put("resourceId", id).put("offset", found).put("quote", text.substring(found, minOf(text.length, found + query.length)))
                    .put("context", text.substring(maxOf(0, found - 40), minOf(text.length, found + query.length + 80))))
                offset = found + query.length
            }
        }
        return JSONObject().put("results", results).put("truncated", truncated)
    }
    fun contents(token: String): JSONArray {
        val h = handles[token] ?: error("Reading session expired")
        val order = h.title.getJSONArray("readingOrder")
        val resources = (0 until order.length()).map { order.getJSONObject(it) }
        fun fallback() = JSONArray(resources.map { JSONObject().put("resourceId", it.getString("id")).put("label", it.getString("label")).put("anchor", "") })
        val zip = h.archive ?: return fallback()
        fun document(path: String): org.w3c.dom.Element {
            val e = zip.getEntry(ReadingPublication.safePath(path)) ?: error("Missing contents resource")
            require(e.size in 0..2L * 1024 * 1024)
            val raw = zip.getInputStream(e).use { it.readBytesBounded(2 * 1024 * 1024) }
            return ReadingPublication.xml(ReadingTextContent.sanitizedXml(raw).toByteArray(Charsets.UTF_8))
        }
        // R1 synthetic fixtures and older packages may have only spine labels.
        if (zip.getEntry("META-INF/container.xml") == null) return fallback()
        val container = document("META-INF/container.xml")
        val packagePath = ReadingPublication.elements(container, "rootfile").firstOrNull()?.getAttribute("full-path") ?: return fallback()
        val manifest = ReadingPublication.elements(document(packagePath), "item")
        val item = manifest.firstOrNull { it.getAttribute("properties").split(' ').contains("nav") }
            ?: manifest.firstOrNull { it.getAttribute("media-type") == "application/x-dtbncx+xml" } ?: return fallback()
        val navUri = java.net.URI(ReadingPublication.href(packagePath)).resolve(item.getAttribute("href"))
        require(!navUri.isAbsolute && navUri.rawAuthority == null)
        val nav = document(navUri.path)
        val result = JSONArray()
        fun add(href: String, label: String) {
            val target = navUri.resolve(href)
            if (target.isAbsolute || target.rawAuthority != null || target.query != null) return
            val path = target.path
            val resource = resources.firstOrNull { java.net.URI(it.getString("href")).path == path } ?: return
            if (result.length() >= 10000 || label.isBlank()) return
            result.put(JSONObject().put("resourceId", resource.getString("id")).put("label", label.trim().take(4096)).put("anchor", target.fragment ?: ""))
        }
        if (item.getAttribute("media-type") == "application/x-dtbncx+xml") {
            for (point in ReadingPublication.elements(nav, "navPoint")) {
                val content = ReadingPublication.elements(point, "content").firstOrNull()
                val text = ReadingPublication.elements(point, "text").firstOrNull()?.textContent.orEmpty()
                if (content != null) add(content.getAttribute("src"), text)
            }
        } else {
            val toc = ReadingPublication.elements(nav, "nav").firstOrNull { it.getAttribute("epub:type").split(' ').contains("toc") } ?: nav
            for (link in ReadingPublication.elements(toc, "a")) add(link.getAttribute("href"), link.textContent)
        }
        return if (result.length() == 0) fallback() else result
    }
    fun cacheBytes(): Long = cache.listFiles().orEmpty().filter { it.canonicalFile.parentFile == cache.canonicalFile }.sumOf { folder -> folder.walkTopDown().filter { it.isFile && it.canonicalPath.startsWith(cache.canonicalPath + File.separator) }.sumOf { it.length() } }
    fun clearIdleCache() {
        val active = handles.values.map { it.folder.canonicalFile }.toSet()
        for (folder in cache.listFiles().orEmpty()) if (folder.name.startsWith("session-") && folder.canonicalFile.parentFile == cache.canonicalFile && folder.canonicalFile !in active) check(folder.deleteRecursively())
    }
    fun closeAll() { handles.keys.toList().forEach { runCatching { close(it) } } }
    fun close(token: String) { handles.remove(token)?.let { h -> try { h.archive?.close() } finally { check(h.folder.deleteRecursively()) } } }
}
