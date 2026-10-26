package com.bugdeployer.multiplexr

import android.app.Activity
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

/** File access and embedded tags are shared by books and future music imports. */
class AudioHost(private val activity: Activity, private val channel: MethodChannel) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var picker: MethodChannel.Result? = null
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "external" -> {
                        val uri = Uri.parse(call.arguments as String)
                        require(uri.scheme == "content")
                        AudioEngine.stop(activity)
                        val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "audio/*")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        view.clipData = android.content.ClipData.newRawUri("Audio", uri)
                        try { activity.startActivity(Intent.createChooser(view, "Play with")); result.success(null) }
                        catch (_: android.content.ActivityNotFoundException) { result.error("player", "Install an external audio player first.", null) }
                    }
                    "pickFiles" -> {
                        check(picker == null) { "An audio picker is already open." }
                        picker = result
                        try {
                            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT)
                                .setType("*/*").putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/*", "application/ogg", "application/octet-stream"))
                                .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true).addCategory(Intent.CATEGORY_OPENABLE)
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION), DocumentRequest.AUDIO.code)
                        } catch (e: Exception) { picker = null; throw e }
                    }
                    "metadataDbConfigured" -> result.success(false)
                    "musicCover", "metadataDbSave", "searchMetadata", "metadataCover" -> result.error("unsupported_capability","Use an installed provider through the plugin gateway.",null)
                    "pickCover" -> {
                        check(picker == null) { "An audio picker is already open." }
                        picker = result
                        try {
                            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).setType("image/*")
                                .addCategory(Intent.CATEGORY_OPENABLE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), DocumentRequest.COVER.code)
                        } catch (e: Exception) { picker = null; throw e }
                    }
                    "pickChapters" -> {
                        check(picker == null) { "An audio picker is already open." }
                        picker = result
                        try {
                            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*")
                                .addCategory(Intent.CATEGORY_OPENABLE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), DocumentRequest.CHAPTERS.code)
                        } catch (e: Exception) { picker = null; throw e }
                    }
                    "releaseUnusedFiles" -> {
                        val uris = (call.arguments as List<*>).filterIsInstance<String>()
                        worker.execute {
                            try {
                                val used = mutableSetOf<String>()
                                android.database.sqlite.SQLiteDatabase.openDatabase(activity.getDatabasePath("library.db").path, null,
                                    android.database.sqlite.SQLiteDatabase.OPEN_READONLY).use { db ->
                                    db.query("library_state", arrayOf("payload"), "id=?", arrayOf("audio:library"), null, null, null).use { cursor ->
                                        if (cursor.moveToFirst()) {
                                            val books = JSONObject(cursor.getString(0)).getJSONArray("books")
                                            for (i in 0 until books.length()) {
                                                val files = books.getJSONObject(i).getJSONArray("files")
                                                for (j in 0 until files.length()) used.add(files.getJSONObject(j).getString("uri"))
                                            }
                                        }
                                    }
                                }
                                for (uri in uris) if (uri !in used) try {
                                    activity.contentResolver.releasePersistableUriPermission(Uri.parse(uri), Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                } catch (_: SecurityException) { /* Only exact audio document grants are released, never folder grants. */ }
                                main.post { result.success(null) }
                            } catch (_: Exception) { main.post { result.error("storage", "Could not release unused audio permissions.", null) } }
                        }
                    }
                    "open" -> { AudioEngine.open(activity, JSONObject(call.arguments as String)); result.success(null) }
                    "state" -> result.success(AudioEngine.snapshot().toString())
                    "playPause" -> { AudioEngine.toggle(); result.success(null) }
                    "pause" -> { AudioEngine.current()?.pause(); result.success(null) }
                    "seek" -> { AudioEngine.seek((call.arguments as Number).toLong()); result.success(null) }
                    "chapter" -> { AudioEngine.chapter((call.arguments as Number).toInt()); result.success(null) }
                    "nextTrack" -> { AudioEngine.nextMusic(); result.success(null) }
                    "previousTrack" -> { AudioEngine.nextMusic(previous = true); result.success(null) }
                    "musicRepeat" -> { AudioEngine.repeatMusic(call.arguments as String); result.success(null) }
                    "rate" -> { AudioEngine.rate(activity, (call.arguments as Number).toFloat()); result.success(null) }
                    "sleep" -> { AudioEngine.sleep((call.arguments as Number).toLong()); result.success(null) }
                    "bookmark" -> AudioEngine.bookmark(call.arguments as String) { failure ->
                        if (failure == null) result.success(null) else result.error("storage", failure, null)
                    }
                    "clearQueue" -> { AudioEngine.discard(activity); result.success(null) }
                    "stop" -> { AudioEngine.stop(activity); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("audio", e.message ?: "Audio operation failed.", null) }
        }
    }
    fun onResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != DocumentRequest.AUDIO.code && code != DocumentRequest.CHAPTERS.code && code != DocumentRequest.COVER.code) return false
        val pending = picker ?: return true
        picker = null
        if (resultCode != Activity.RESULT_OK || data == null) { pending.success(null); return true }
        if (code == DocumentRequest.COVER.code) {
            val uri = data.data
            worker.execute {
                try {
                    require(uri != null && uri.scheme == "content")
                    val bytes = activity.contentResolver.openInputStream(uri).use { input -> require(input != null); input.readBytesBounded(20_000_000) }
                    val cover = AudioArtwork.encode(bytes)
                    main.post { pending.success(cover) }
                } catch (e: Exception) { main.post { pending.error("audio", e.message ?: "Could not read cover.", null) } }
            }
            return true
        }
        if (code == DocumentRequest.CHAPTERS.code) {
            val uri = data.data
            worker.execute {
                try {
                    require(uri != null && uri.scheme == "content")
                    val bytes = java.io.ByteArrayOutputStream()
                    activity.contentResolver.openInputStream(uri).use { input ->
                        require(input != null)
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            require(bytes.size() + count <= 1000000) { "Chapter file is too large." }
                            bytes.write(buffer, 0, count)
                        }
                    }
                    val text = bytes.toString("UTF-8")
                    main.post { pending.success(text) }
                } catch (e: Exception) { main.post { pending.error("audio", e.message ?: "Could not read chapter file.", null) } }
            }
            return true
        }
        val uris = linkedSetOf<Uri>()
        data.data?.let { uris.add(it) }
        data.clipData?.let { clips -> for (i in 0 until clips.itemCount) uris.add(clips.getItemAt(i).uri) }
        if (uris.size > 1000) { pending.error("audio", "Select at most 1000 audio files per book.", null); return true }
        worker.execute {
            val files = JSONArray(); val errors = JSONArray()
            for (uri in uris) {
                try {
                    require(uri.scheme == "content") { "Choose a document from device storage." }
                    val resolver = activity.contentResolver
                    val filename = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                        if (it.moveToFirst()) it.getString(0) else null
                    } ?: "Audio"
                    val ext = filename.substringAfterLast('.', "").lowercase()
                    require(ext in setOf("mp3", "m4a", "m4b", "aac", "flac", "ogg", "opus", "wav", "oga")) { "Unsupported audio file: $filename" }
                    val tags = JSONObject().put("uri", uri.toString()).put("filename", filename)
                    val reader = MediaMetadataRetriever()
                    try {
                        reader.setDataSource(activity, uri)
                        require(reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes" &&
                            reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) != "yes") { "Not an audio-only file: $filename" }
                        fun text(key: Int) = reader.extractMetadata(key)?.trim() ?: ""
                        for ((name, key) in listOf("title" to MediaMetadataRetriever.METADATA_KEY_TITLE,
                            "album" to MediaMetadataRetriever.METADATA_KEY_ALBUM, "artist" to MediaMetadataRetriever.METADATA_KEY_ARTIST,
                            "author" to MediaMetadataRetriever.METADATA_KEY_AUTHOR, "genre" to MediaMetadataRetriever.METADATA_KEY_GENRE)) tags.put(name, text(key))
                        tags.put("durationMs", text(MediaMetadataRetriever.METADATA_KEY_DURATION).toLongOrNull()?.coerceAtLeast(0) ?: 0)
                        tags.put("track", text(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER).substringBefore('/').toIntOrNull()?.coerceAtLeast(0) ?: 0)
                        tags.put("disc", text(MediaMetadataRetriever.METADATA_KEY_DISC_NUMBER).substringBefore('/').toIntOrNull()?.coerceAtLeast(0) ?: 0)
                    } finally { reader.release() }
                    // Persistence is mandatory: a temporary grant cannot support later resume.
                    resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    files.put(tags)
                } catch (e: Exception) { errors.put(e.message ?: "Could not read an audio file.") }
            }
            main.post { pending.success(JSONObject().put("files", files).put("errors", errors).toString()) }
        }
        return true
    }
    fun close() {
        picker?.success(null); picker = null
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }
}
