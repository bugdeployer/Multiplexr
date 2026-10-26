package com.bugdeployer.multiplexr

import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject

data class ReadingDocument(val key: String, val uri: String, val name: String, val directory: Boolean)
interface ReadingSourceTree {
    fun root(uri: String): ReadingDocument
    fun children(document: ReadingDocument): List<ReadingDocument>
    fun open(document: ReadingDocument): InputStream
    fun cover(bytes: ByteArray): String
}

/** Pure discovery policy; the Android adapter alone owns SAF and image decoding. */
class ReadingSourceDiscovery(private val tree: ReadingSourceTree, private val temporary: File, private val formats: Set<String>? = null) {
    fun discover(collection: JSONObject, requestId: String, encoding: String = "utf-8", encodings: Map<String, String> = emptyMap(), cancelled: () -> Boolean,
        progress: (Int, String) -> Unit): JSONObject {
        val subtype = collection.getString("subtype"); require(subtype in setOf("ebook", "comics"))
        val allowed = if(subtype=="ebook")setOf("epub","txt","pdf")else setOf("cbz","images")
        val selected = formats ?: allowed
        require(selected.isNotEmpty() && selected.all{it in allowed}) { "Unsupported reading formats." }
        val roots = collection.getJSONArray("roots"); require(roots.length() in 1..100)
        val sources = JSONArray(); val warnings = JSONArray(); val health = JSONArray(); val seen = mutableSetOf<String>()
        var visitedCount = 0; var responseCharacters = 0L
        fun warn(message: String) { if (warnings.length() < 500) warnings.put(message.take(4096)) }
        for (r in 0 until roots.length()) {
            ReadingPublication.check(cancelled)
            val rootUri = roots.getJSONObject(r).getString("uri")
            val queue = java.util.ArrayDeque<Triple<ReadingDocument, String, Int>>()
            var rootFailed = false
            try { queue.add(Triple(tree.root(rootUri).copy(name = roots.getJSONObject(r).getString("name")), "", 0)) }
            catch (e: Exception) { if (e is ReadingScanCancelled) throw e; rootFailed = true; warn("Cannot access root; select its folder again.") }
            val visited = mutableSetOf<String>()
            while (queue.isNotEmpty()) {
                ReadingPublication.check(cancelled)
                val (folder, path, depth) = queue.removeFirst(); require(depth <= 32) { "Folder nesting exceeds limit." }
                if (!visited.add(folder.key)) continue
                require(++visitedCount <= 100000) { "Too many reading folders." }
                progress(sources.length(), path.ifEmpty { roots.getJSONObject(r).getString("name") })
                val children = try { tree.children(folder).sortedWith { a, b -> ReadingPublication.natural(a.name, b.name) } }
                catch (e: Exception) { if (e is ReadingScanCancelled) throw e; rootFailed = true; warn("$path: cannot read folder; existing entries retained."); continue }
                val directories = children.filter { it.directory }
                val images = children.filter { !it.directory && it.name.substringAfterLast('.').lowercase() in setOf("jpg", "jpeg", "png", "webp") }
                val supported = children.filter { !it.directory && it.name.substringAfterLast('.').lowercase() in selected && it.name.substringAfterLast('.').lowercase() != "images" }
                val ambiguous = subtype == "comics" && "images" in selected && images.isNotEmpty() && (directories.isNotEmpty() || supported.isNotEmpty()) || depth > 2 && supported.isNotEmpty()
                if (ambiguous) warn("$path: ambiguous nested/mixed publication layout; review grouping before adding it.")
                for (directory in directories) queue.add(Triple(directory, listOf(path, directory.name).filter(String::isNotEmpty).joinToString("/"), depth + 1))
                val candidates = supported.map { it to false } + if (subtype == "comics" && "images" in selected && images.isNotEmpty()) listOf(folder to true) else emptyList()
                for ((document, imageFolder) in candidates) {
                    ReadingPublication.check(cancelled)
                    if (!seen.add(document.key)) continue
                    require(seen.size <= 200000) { "Reading library exceeds discovery limit." }
                    val relative = if (imageFolder) path.ifEmpty { document.name } else listOf(path, document.name).filter(String::isNotEmpty).joinToString("/")
                    try {
                        val format = if (imageFolder) "images" else document.name.substringAfterLast('.').lowercase()
                        val parsed = if (format == "pdf") tree.open(document).use { ReadingPdfFiles.inspect(it, document.name, temporary, cancelled) }
                            else if (!imageFolder) tree.open(document).use { ReadingPublication.inspect(it, format, document.name, temporary, encodings[document.key] ?: encoding, cancelled = cancelled) }
                            else inspectImages(images, document.name, children.firstOrNull { !it.directory && it.name.equals("ComicInfo.xml", ignoreCase = true) }, cancelled)
                        val embedded = JSONObject(parsed.metadata.toString()); val embeddedSeries = embedded.optString("scanSeries"); embedded.remove("scanSeries")
                        var cover = ""
                        if (parsed.cover != null) try { cover = tree.cover(parsed.cover) }
                        catch (e: Exception) { if (e is ReadingScanCancelled) throw e; warn("$relative: cover could not be decoded.") }
                        val folderSeries = if (imageFolder) path.substringBeforeLast('/', "") else path
                        val series = embeddedSeries.ifEmpty { folderSeries }
                        val row = JSONObject().put("sourceKey", document.key).put("uri", document.uri).put("name", document.name)
                            .put("rootUri", rootUri).put("relativePath", relative).put("format", format).put("fingerprint", parsed.fingerprint)
                            .put("metadata", embedded).put("readingOrder", parsed.resources).put("cover", cover).put("encoding", parsed.encoding)
                            .put("series", series).put("ambiguous", ambiguous || series.count { it == '/' } > 0)
                        responseCharacters += row.toString().length
                        check(responseCharacters <= 6000000) { "Reading scan response exceeds limit; scan a smaller collection." }
                        sources.put(row)
                    } catch (e: Exception) {
                        if (e is ReadingScanCancelled) throw e
                        rootFailed = true // A failed publication makes missing-source decisions unsafe for this root.
                        warn("$relative: ${e.message ?: "could not index publication"}; existing entry retained.")
                    }
                }
            }
            health.put(JSONObject().put("uri", rootUri).put("complete", !rootFailed))
        }
        ReadingPublication.check(cancelled)
        return JSONObject().put("version", 1).put("requestId", requestId).put("collectionId", collection.getString("id"))
            .put("sources", sources).put("roots", health).put("warnings", warnings)
    }
    private fun inspectImages(images: List<ReadingDocument>, name: String, comicInfo: ReadingDocument?, cancelled: () -> Boolean): ReadingPublication.Result {
        require(images.size in 1..10000)
        val metadata = ReadingPublication.metadata(name)
        val selectedCover = comicInfo?.let { document -> tree.open(document).use { ReadingPublication.comicInfo(metadata, it, images.size, cancelled) } } ?: 0
        val digest = MessageDigest.getInstance("SHA-256"); val order = JSONArray(); var cover: ByteArray? = null; var total = 0L
        for ((index, image) in images.withIndex()) {
            ReadingPublication.safePath(image.name)
            digest.update(image.name.toByteArray(Charsets.UTF_8)); digest.update(0)
            val buffer = java.io.ByteArrayOutputStream(); val header = java.io.ByteArrayOutputStream(); var size = 0L
            tree.open(image).use { stream ->
                val bytes = ByteArray(16384)
                while (true) {
                    ReadingPublication.check(cancelled); val n = stream.read(bytes); if (n < 0) break
                    size += n; total += n; require(size <= 32L * 1024 * 1024 && total <= 512L * 1024 * 1024) { "Image publication exceeds limits." }
                    digest.update(bytes, 0, n)
                    if (header.size() < 262144) header.write(bytes, 0, minOf(n, 262144 - header.size()))
                    if (index == selectedCover) { require(size <= 8L * 1024 * 1024) { "Cover exceeds limit." }; buffer.write(bytes, 0, n) }
                }
            }
            require(size > 0); digest.update(0)
            ReadingImage.validate(header.toByteArray())
            if (index == selectedCover) cover = buffer.toByteArray()
            order.put(JSONObject().put("id", image.name).put("href", ReadingPublication.href(image.name)).put("label", image.name.take(4096)))
        }
        return ReadingPublication.Result(metadata, order, digest.digest().joinToString("") { "%02x".format(it) }, cover, "")
    }
}
