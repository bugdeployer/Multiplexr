package com.bugdeployer.multiplexr

import android.content.Context
import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.DocumentsContract
import org.json.JSONArray
import org.json.JSONObject

/** Audio indexing stays out of the legacy video asset table. A folder forms one book. */
class AudioScanner(private val context: Context) {
    companion object {
        fun catalog(db: SQLiteDatabase): JSONObject = db.query("library_state", arrayOf("payload"), "id=?", arrayOf("audio:library"), null, null, null).use {
            if (it.moveToFirst()) JSONObject(it.getString(0)) else JSONObject().put("version", 1).put("books", JSONArray())
        }
        fun save(db: SQLiteDatabase, value: JSONObject) {
            AudioCatalogCodec.validate(value)
            LibraryStateStore.transaction(db) {
                LibraryStateStore.put(db, "audio:library", value)
                LibraryStateStore.raw(db, "queue:audiobook")?.let { queue ->
                    LibraryStateStore.put(db, "queue:audiobook", DurableMediaStateCodec.retainBooks(queue, value))
                }
            }
        }
        fun removeCollection(db: SQLiteDatabase, id: String) {
            val catalog = catalog(db); val all = catalog.getJSONArray("books"); val keep = JSONArray()
            for (i in 0 until all.length()) {
                val book = all.getJSONObject(i); val owner = book.getJSONObject("id")
                if (owner.getString("collectionId") != id) keep.put(book)
                else LibraryStateStore.delete(db, "progress:" + JSONArray(listOf("audiobook", id, owner.getString("itemId"))).toString())
            }
            val series = catalog.optJSONObject("seriesMetadata")
            if (series != null) for (key in series.keys().asSequence().toList()) {
                if (series.optJSONObject(key)?.optString("collectionId") == id) series.remove(key)
            }
            save(db, catalog.put("books", keep))
        }
    }
    fun scan(db: SQLiteDatabase, collection: JSONObject, cancelled: () -> Boolean): List<String> {
        val id = collection.getString("id")
        val roots = collection.getJSONArray("roots")
        require(roots.length() > 0) { "Add a root folder before scanning." }
        val extensions = collection.getJSONArray("extensions").let { a -> (0 until a.length()).map { a.getString(it).lowercase() }.toSet() }
        val groups = linkedMapOf<String, MutableList<JSONObject>>()
        val folderDepths = mutableMapOf<String, Int>()
        val foldersWithChildren = mutableSetOf<String>()
        val folderNames = mutableMapOf<String, String>()
        val seriesNames = mutableMapOf<String, String>()
        val seriesIds = mutableMapOf<String, String>()
        val sourceFolders = mutableMapOf<String, String>()
        val sourceRoots = mutableMapOf<String, String>()
        val embedded = mutableMapOf<String, EmbeddedAudiobookMetadata.Result>()
        val covers = mutableMapOf<String, String>()
        val sidecars = mutableMapOf<String, String>()
        val warnings = mutableListOf<String>()
        val resolver = context.contentResolver
        val seen = mutableSetOf<String>()
        for (r in 0 until roots.length()) {
            val root = roots.getJSONObject(r); val tree = Uri.parse(root.getString("uri"))
            val queue = java.util.ArrayDeque<Pair<String, String>>()
            queue.add(DocumentsContract.getTreeDocumentId(tree) to root.getString("name"))
            val relativeFolders = mutableMapOf(DocumentsContract.getTreeDocumentId(tree) to emptyList<String>())
            val parents = mutableMapOf<String, String>()
            val visited = mutableSetOf<String>()
            while (queue.isNotEmpty()) {
                check(!cancelled()) { "Scan cancelled. Existing books were kept." }
                val (parent, folderName) = queue.removeFirst()
                if (!visited.add(parent)) continue
                require(visited.size <= 100000) { "Too many folders." }
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
                val cursor = try {
                    resolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)
                        ?: throw IllegalStateException("Folder provider returned no contents.")
                } catch (e: Exception) {
                    val health = collection.optJSONObject("rootHealth") ?: JSONObject()
                    health.put(root.getString("uri"), "Unavailable — reselect this root folder")
                    collection.put("rootHealth", health)
                    db.update("collections", ContentValues().apply { put("payload", collection.toString()) }, "id=?", arrayOf(id))
                    throw IllegalStateException("Could not read $folderName. Reselect its root folder. Existing audiobooks were kept.", e)
                }
                cursor.use { c -> while (c.moveToNext()) {
                    check(!cancelled()) { "Scan cancelled. Existing books were kept." }
                    val document = c.getString(0); val filename = c.getString(1) ?: "Audio"
                    if (c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) { foldersWithChildren.add("${tree.authority}:$parent"); relativeFolders[document] = relativeFolders[parent].orEmpty() + filename; parents[document] = parent; queue.add(document to filename); continue }
                    val groupKey = "${tree.authority}:$parent"
                    val extension = filename.substringAfterLast('.', "").lowercase()
                    if (extension in setOf("jpg", "jpeg", "png", "webp") && filename.substringBeforeLast('.').lowercase() in setOf("cover", "folder", "front")) {
                        try { resolver.openInputStream(DocumentsContract.buildDocumentUriUsingTree(tree, document))?.use { covers[groupKey] = AudioArtwork.encode(it.readBytesBounded(20_000_000)) } } catch (_: Exception) { warnings.add("$filename: could not read cover image.") }
                        continue
                    }
                    if (extension == "cue") {
                        try { resolver.openInputStream(DocumentsContract.buildDocumentUriUsingTree(tree, document))?.use { sidecars[groupKey] = it.readBytesBounded(1_000_000).toString(Charsets.UTF_8) } } catch (_: Exception) { warnings.add("$filename: could not read chapter sidecar.") }
                        continue
                    }
                    if (extension !in extensions) continue
                    val key = "${tree.authority}:$document"
                    if (!seen.add(key)) continue
                    require(seen.size <= 200000) { "Audio library exceeds scan limit." }
                    val uri = DocumentsContract.buildDocumentUriUsingTree(tree, document)
                    val reader = MediaMetadataRetriever()
                    try {
                        reader.setDataSource(context, uri)
                        require(reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes" && reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) != "yes")
                        fun text(k: Int) = reader.extractMetadata(k)?.trim() ?: ""
                        val file = JSONObject().put("id", key).put("uri", uri.toString()).put("filename", filename)
                            .put("title", text(MediaMetadataRetriever.METADATA_KEY_TITLE)).put("album", text(MediaMetadataRetriever.METADATA_KEY_ALBUM))
                            .put("author", text(MediaMetadataRetriever.METADATA_KEY_AUTHOR)).put("artist", text(MediaMetadataRetriever.METADATA_KEY_ARTIST))
                            .put("genre", text(MediaMetadataRetriever.METADATA_KEY_GENRE))
                            .put("durationMs", text(MediaMetadataRetriever.METADATA_KEY_DURATION).toLongOrNull()?.coerceAtLeast(0) ?: 0)
                            .put("track", text(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER).substringBefore('/').toIntOrNull()?.coerceAtLeast(0) ?: 0)
                            .put("disc", text(MediaMetadataRetriever.METADATA_KEY_DISC_NUMBER).substringBefore('/').toIntOrNull()?.coerceAtLeast(0) ?: 0)
                        val rootLevel = parent == DocumentsContract.getTreeDocumentId(tree)
                        val group = if (extension == "m4b" && rootLevel) {
                            if (file.optString("album").isNotBlank()) "$groupKey:album:${Uri.encode(file.getString("album").lowercase())}" else "${tree.authority}:file:$document"
                        } else groupKey
                        if (extension in setOf("m4b", "m4a", "mp4", "mp3")) {
                            try {
                                resolver.openFileDescriptor(uri, "r")?.use { descriptor -> java.io.FileInputStream(descriptor.fileDescriptor).use { input ->
                                    val channel = input.channel
                                    embedded[key] = EmbeddedAudiobookMetadata.read(channel.size()) { position, length ->
                                        require(position >= 0 && length >= 0 && position <= channel.size() - length)
                                        val buffer = java.nio.ByteBuffer.allocate(length)
                                        while (buffer.hasRemaining()) check(channel.read(buffer, position + buffer.position()) > 0)
                                        buffer.array()
                                    }
                                } }
                            } catch (_: Exception) { warnings.add("$filename: embedded chapters could not be read; the full audio file is available.") }
                        }
                        val picture = reader.embeddedPicture
                        if (picture != null && covers[group] == null) try { covers[group] = AudioArtwork.encode(picture) } catch (_: Exception) { warnings.add("$filename: embedded cover could not be read.") }
                        if (group != groupKey && covers[groupKey] != null) covers[group] = covers[groupKey]!!
                        val path = relativeFolders[parent].orEmpty()
                        folderDepths[group] = path.size
                        if (path.size >= 2) {
                            seriesNames[group] = path[path.size - 2]
                            seriesIds[group] = "folder-series:${tree.authority}:${parents[parent]}"
                        }
                        sourceFolders[group] = groupKey
                        sourceRoots[group] = "${tree.authority}:${DocumentsContract.getTreeDocumentId(tree)}"
                        folderNames[group] = if (extension == "m4b" && rootLevel) filename.substringBeforeLast('.') else folderName
                        groups.getOrPut(group) { mutableListOf() }.add(file)
                    } catch (_: Exception) { warnings.add("$filename: could not read audio metadata; existing entries were kept.") }
                    finally { reader.release() }
                } }
            }
        }
        check(!cancelled()) { "Scan cancelled. Existing books were kept." }
        db.beginTransaction()
        try {
            val value = catalog(db); val all = value.getJSONArray("books")
            val existing = (0 until all.length()).map { all.getJSONObject(it) }
            val keep = existing.toMutableList()
            fun canonical(file: JSONObject): String = try { val uri = Uri.parse(file.getString("uri")); "${uri.authority}:${DocumentsContract.getDocumentId(uri)}" } catch (_: Exception) { file.optString("id", file.getString("uri")) }
            val owned = existing.filter { it.getJSONObject("id").getString("collectionId") == id }
            val ownerByFile = mutableMapOf<String, JSONObject>()
            for (book in owned) {
                val sources = book.getJSONArray("files")
                for (i in 0 until sources.length()) ownerByFile[canonical(sources.getJSONObject(i))] = book
            }
            fun markers(files: List<JSONObject>): JSONArray {
                val output = JSONArray()
                for (file in files) {
                    val key = file.getString("id"); val duration = file.optLong("durationMs")
                    val chapters = embedded[key]?.chapters.orEmpty().filter { it.startMs >= 0 && (duration == 0L || it.startMs < duration) }
                    if (chapters.isEmpty()) {
                        val marker = JSONObject().put("id", key).put("fileId", key).put("title", file.optString("title").ifBlank { file.getString("filename").substringBeforeLast('.') }).put("startMs", 0)
                        if (duration > 0) marker.put("endMs", duration)
                        output.put(marker)
                    } else {
                        if (chapters.first().startMs > 0) output.put(JSONObject().put("id", "$key:chapter:0").put("fileId", key).put("title", "Introduction").put("startMs", 0).put("endMs", chapters.first().startMs))
                        for ((index, chapter) in chapters.withIndex()) {
                            val marker = JSONObject().put("id", "$key:chapter:${chapter.startMs}").put("fileId", key).put("title", chapter.title).put("startMs", chapter.startMs)
                            val end = chapters.getOrNull(index + 1)?.startMs ?: duration
                            if (end > chapter.startMs) marker.put("endMs", end)
                            output.put(marker)
                        }
                    }
                }
                return output
            }
            for ((folder, found) in groups) {
                val files = found.sortedWith { a, b ->
                    val disc = a.optInt("disc").coerceAtLeast(1).compareTo(b.optInt("disc").coerceAtLeast(1))
                    if (disc != 0) disc else {
                        val track = a.optInt("track").let { if (it == 0) Int.MAX_VALUE else it }.compareTo(b.optInt("track").let { if (it == 0) Int.MAX_VALUE else it })
                        if (track != 0) track else naturalCompare(a.getString("filename"), b.getString("filename"))
                    }
                }
                // Reconnect known sources by document identity, even after root reselection.
                for (file in files) {
                    val book = ownerByFile[canonical(file)] ?: continue
                    val oldFiles = book.getJSONArray("files")
                    for (i in 0 until oldFiles.length()) if (canonical(oldFiles.getJSONObject(i)) == canonical(file)) {
                        oldFiles.getJSONObject(i).put("uri", file.getString("uri"))
                    }
                }
                val fresh = files.filter { canonical(it) !in ownerByFile }
                val image = covers[sourceFolders[folder]] ?: covers[folder]
                if (image != null) for (knownBook in files.mapNotNull { ownerByFile[canonical(it)] }.distinct()) {
                    val meta = knownBook.getJSONObject("metadata")
                    if (meta.optString("cover").isBlank() && meta.optString("coverSource") != "manual") meta.put("cover", image).put("coverSource", "embedded/local")
                }
                val ambiguity = AudiobookFolderPolicy.issue(folderDepths[folder] ?: 0, files.map { it.getString("filename") }, files.map { it.optString("album") }, sourceFolders[folder] in foldersWithChildren)
                if (ambiguity != null) {
                    warnings.add("${folderNames[folder]}: $ambiguity Existing entries were kept; new files were not assigned.")
                    continue
                }
                if (fresh.isEmpty()) continue
                val baseId = "folder:$folder"
                val folderOwner = owned.firstOrNull { it.getJSONObject("id").getString("itemId") == baseId }
                val knownOwners = files.mapNotNull { ownerByFile[canonical(it)] }
                    .associateBy { it.getJSONObject("id").getString("itemId") }
                val decision = AudioScanReconciliation.decide(knownOwners.keys,
                    folderOwner?.getJSONObject("id")?.getString("itemId"), fresh.size)
                if (decision == AudioScanReconciliation.Decision.Review) {
                    warnings.add("${folderNames[folder]}: files belong to multiple existing audiobooks. Existing membership was kept; new files need review.")
                    continue
                }
                val old = if (decision is AudioScanReconciliation.Decision.Append)
                    knownOwners[decision.owner] ?: folderOwner else null
                if (old != null) {
                    val sourceList = old.getJSONArray("files"); val chapterList = old.optJSONArray("chapters") ?: markers((0 until sourceList.length()).map { sourceList.getJSONObject(it) })
                    old.put("chapters", chapterList)
                    AudioScanReconciliation.append(old, fresh, markers(fresh))
                    warnings.add("${folderNames[folder]}: new chapters appended; existing chapter order and progress were kept.")
                    for (file in fresh) ownerByFile[canonical(file)] = old
                    continue
                }
                val first = fresh.first()
                val title = first.optString("album").ifBlank { folderNames[folder] ?: collection.getString("name") }
                val details = embedded[first.getString("id")]
                val metadata = JSONObject().put("title", title).put("author", first.optString("author").ifBlank { first.optString("artist") })
                    .put("series", seriesNames[folder] ?: details?.series?.takeIf { it.isNotBlank() } ?: title).put("seriesId", seriesIds[folder] ?: details?.series?.takeIf { it.isNotBlank() }?.let { "embedded-series:${sourceRoots[folder]}:${it.lowercase()}" } ?: "standalone:$baseId").put("seriesOrder", details?.order ?: 0.0)
                    .put("cover", image ?: "").put("coverSource", "embedded/local")
                val book = JSONObject().put("id", JSONObject().put("kind", "audiobook").put("collectionId", id).put("itemId", baseId))
                    .put("metadata", metadata).put("files", JSONArray(fresh)).put("chapters", markers(fresh))
                (sidecars[folder] ?: sidecars[sourceFolders[folder]])?.let { text ->
                    try { book.put("chapters", AudioCueChapters.parse(text, fresh)) }
                    catch (_: Exception) { warnings.add("${folderNames[folder]}: chapter sidecar could not be read; existing file/embedded chapters are used.") }
                }
                keep.add(book)
                for (file in fresh) ownerByFile[canonical(file)] = book
            }
            save(db, value.put("books", JSONArray(keep)))
            collection.put("lastScanAt", System.currentTimeMillis()).put("rootHealth", JSONObject().apply { for (i in 0 until roots.length()) put(roots.getJSONObject(i).getString("uri"), "Available") })
            db.update("collections", ContentValues().apply { put("payload", collection.toString()) }, "id=?", arrayOf(id))
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        return warnings.distinct()
    }
    private fun naturalCompare(a: String, b: String): Int {
        val tokens = Regex("[0-9]+|[^0-9]+")
        val left = tokens.findAll(a.lowercase()).map { it.value }.toList()
        val right = tokens.findAll(b.lowercase()).map { it.value }.toList()
        for (i in 0 until minOf(left.size, right.size)) {
            val x = left[i].toLongOrNull(); val y = right[i].toLongOrNull()
            val compare = if (x != null && y != null) x.compareTo(y) else left[i].compareTo(right[i])
            if (compare != 0) return compare
        }
        return left.size.compareTo(right.size)
    }
}
