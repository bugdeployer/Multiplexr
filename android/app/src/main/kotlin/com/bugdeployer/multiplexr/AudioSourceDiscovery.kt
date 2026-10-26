package com.bugdeployer.multiplexr

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.DocumentsContract
import org.json.JSONArray
import org.json.JSONObject

/** Source discovery only. Tag/folder album decisions belong to the Music adapter. */
class AudioSourceDiscovery(private val context: Context) {
    fun discover(collection: JSONObject, cancelled: () -> Boolean, progress: (Int, String) -> Unit = { _, _ -> }): JSONObject {
        require(collection.optString("type") == "audio" && collection.optString("subtype") == "music")
        val roots = collection.getJSONArray("roots")
        require(roots.length() > 0) { "Add a root folder before scanning." }
        val extensions = collection.getJSONArray("extensions").let { a -> (0 until a.length()).map { a.getString(it).lowercase() }.toSet() }
        val sources = JSONArray(); val warnings = JSONArray(); val seen = mutableSetOf<String>()
        val resolver = context.contentResolver
        for (r in 0 until roots.length()) {
            val root = roots.getJSONObject(r); val tree = Uri.parse(root.getString("uri"))
            val rootDocument = DocumentsContract.getTreeDocumentId(tree)
            val rootId = "${tree.authority}:$rootDocument"
            val folders = java.util.ArrayDeque<Pair<String, String>>()
            folders.add(rootDocument to root.getString("name"))
            val visited = mutableSetOf<String>()
            while (folders.isNotEmpty()) {
                check(!cancelled()) { "Scan cancelled. Existing tracks were kept." }
                val (folder, folderName) = folders.removeFirst()
                if (!visited.add(folder)) continue
                progress(sources.length(), folderName)
                require(visited.size <= 100000) { "Too many folders." }
                val folderSources = mutableListOf<JSONObject>(); var folderCover = ""
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, folder)
                // A failed root aborts discovery; never reconcile a partial scan.
                val cursor = resolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)
                    ?: error("Cannot read $folderName. Reselect its root folder; existing tracks were kept.")
                cursor.use { c -> while (c.moveToNext()) {
                    check(!cancelled()) { "Scan cancelled. Existing tracks were kept." }
                    val document = c.getString(0); val name = c.getString(1) ?: "Audio"
                    if (c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        folders.add(document to name); continue
                    }
                    val uri = DocumentsContract.buildDocumentUriUsingTree(tree, document)
                    val extension = name.substringAfterLast('.', "").lowercase()
                    if (extension in setOf("jpg", "jpeg", "png", "webp") && name.substringBeforeLast('.').lowercase() in setOf("cover", "folder", "front")) {
                        try { resolver.openInputStream(uri)?.use { folderCover = MusicArtworkFiles.store(context, AudioArtwork.encode(it.readBytesBounded(20_000_000))) } }
                        catch (_: Exception) { warnings.put("$name: could not read cover image.") }
                        continue
                    }
                    if (extension !in extensions) continue
                    val id = "${tree.authority}:$document"
                    if (!seen.add(id)) continue
                    require(seen.size <= 200000) { "Music library exceeds scan limit." }
                    val reader = MediaMetadataRetriever()
                    try {
                        reader.setDataSource(context, uri)
                        require(reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes" && reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) != "yes")
                        fun text(k: Int) = reader.extractMetadata(k)?.trim().orEmpty()
                        fun number(k: Int) = text(k).substringBefore('/').toLongOrNull()?.coerceAtLeast(0) ?: 0L
                        val file = JSONObject().put("id", id).put("uri", uri.toString()).put("filename", name)
                            .put("title", text(MediaMetadataRetriever.METADATA_KEY_TITLE)).put("album", text(MediaMetadataRetriever.METADATA_KEY_ALBUM))
                            .put("artist", text(MediaMetadataRetriever.METADATA_KEY_ARTIST)).put("genre", text(MediaMetadataRetriever.METADATA_KEY_GENRE))
                            .put("durationMs", number(MediaMetadataRetriever.METADATA_KEY_DURATION))
                            .put("disc", number(MediaMetadataRetriever.METADATA_KEY_DISC_NUMBER)).put("track", number(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER))
                        var cover = ""
                        reader.embeddedPicture?.let { try { cover = MusicArtworkFiles.store(context, AudioArtwork.encode(it)) } catch (_: Exception) { warnings.put("$name: could not read embedded cover.") } }
                        folderSources.add(JSONObject().put("id", id).put("rootId", rootId).put("folderId", "${tree.authority}:$folder")
                            .put("folderName", folderName).put("albumArtist", text(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST))
                            .put("year", text(MediaMetadataRetriever.METADATA_KEY_YEAR).take(4).toIntOrNull()).put("cover", cover).put("file", file))
                    } catch (_: Exception) { warnings.put("$name: unreadable or unsupported audio; existing entries were kept.") }
                    finally { reader.release() }
                } }
                for (source in folderSources) {
                    if (source.optString("cover").isEmpty()) source.put("cover", folderCover)
                    sources.put(source)
                }
            }
        }
        return JSONObject().put("sources", sources).put("warnings", warnings)
    }
}
