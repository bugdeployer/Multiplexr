package com.bugdeployer.multiplexr

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Handler
import android.os.Looper
import androidx.media3.common.*
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.DefaultMediaNotificationProvider
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

/** One audio-only playlist. Book and music progress have separate wire schemas. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object AudioEngine {
    private var player: ExoPlayer? = null
    private var context: Context? = null
    private var spec: JSONObject? = null
    private val io = Executors.newSingleThreadExecutor()
    private val sleepTimer = AudioSleepTimer()
    private var error: String? = null
    @Volatile private var generation = 0L
    private var transitionRevision = 0L
    var attached = false
    var privateCollection = false
    private var stopping = false
    private var musicOccurrence = 0L
    private var countedMusicOccurrence = -1L
    private var privacyTicks = 0
    private var metadataRedacted = false
    fun sessionRevision()=transitionRevision
    fun current() = player
    private fun requirePlayer() = checkNotNull(player) { "Open an audio item first." }
    fun open(context: Context, input: JSONObject, preserveSleep: Boolean = false) {
        transitionRevision++
        check(!stopping) { "Audio is stopping. Try again." }
        check(PlaybackEngine.views == 0) { "Close the video player before starting audio." }
        val id = input.getJSONObject("id")
        privateCollection = context.getDatabasePath("library.db").let { file ->
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                db.query("collections", arrayOf("payload"), "id=?", arrayOf(id.getString("collectionId")), null, null, null).use { cursor ->
                    if (cursor.moveToFirst()) JSONObject(cursor.getString(0)).optBoolean("locked") else false
                }
            }
        }
        require(id.getString("kind") in setOf("audiobook", "music") &&
            id.getString("collectionId").isNotBlank() && id.getString("itemId").isNotBlank())
        val files = input.getJSONArray("files")
        if (id.getString("kind") == "music") {
            MusicPlaybackPolicy.validate(input)
            require(musicAllowed(context, input, input.optInt("index", 0))) { "Track is unavailable or its collection is not eligible." }
        }
        require(files.length() in 1..1000)
        val seen = mutableSetOf<String>()
        val items = (0 until files.length()).map { index ->
            val file = files.getJSONObject(index)
            val uri = file.getString("uri")
            val chapterId = file.optString("id", uri)
            require(uri.startsWith("content://") && chapterId.isNotBlank() && seen.add(chapterId))
            val startMs = file.optLong("startMs", 0)
            require(startMs >= 0 && (!file.has("endMs") || file.getLong("endMs") > startMs))
            val clip = MediaItem.ClippingConfiguration.Builder().setStartPositionMs(startMs)
            if (file.has("endMs")) clip.setEndPositionMs(file.getLong("endMs"))
            MediaItem.Builder().setMediaId(chapterId).setUri(uri).setClippingConfiguration(clip.build())
                .setMediaMetadata(entryMetadata(input, file, false)).build()
        }
        var start = input.optInt("index", 0)
        var startPosition = input.optLong("positionMs")
        require(start in items.indices && input.optLong("positionMs") >= 0)
        // Reopening the same session must not seek to an older persisted checkpoint.
        if (spec?.getJSONObject("id")?.toString() == id.toString() && player != null) {
            if (id.getString("kind") != "music" && spec?.getJSONArray("files")?.toString() == files.toString() && spec?.optString("title") == input.optString("title")) return
            val chapter = player!!.currentMediaItem?.mediaId
            val found = items.indexOfFirst { it.mediaId == chapter }
            if (found >= 0) { start = found; startPosition = player!!.currentPosition.coerceAtLeast(0) }
        }
        val videoService = PlaybackService.instance
        if (videoService != null) videoService.handoffToAudio()
        else {
            PlaybackEngine.current()?.pause()
            PlaybackEngine.setBackground(context, false)
        }
        persist()
        player?.pause()
        spec = null
        this.context = context.applicationContext
        val p = player ?: ExoPlayer.Builder(context.applicationContext).build().also {
            it.setHandleAudioBecomingNoisy(true)
            it.setWakeMode(C.WAKE_MODE_LOCAL)
            it.setSeekBackIncrementMs(15000)
            it.setSeekForwardIncrementMs(30000)
            it.addListener(object : Player.Listener {
                override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
                    val request = spec ?: return
                    if (request.getJSONObject("id").optString("kind") != "music") return
                    persistMusic(oldPosition.mediaItemIndex, oldPosition.positionMs.coerceAtLeast(0), reason == Player.DISCONTINUITY_REASON_AUTO_TRANSITION)
                    musicOccurrence++
                    if (reason == Player.DISCONTINUITY_REASON_SEEK && it.duration > 0 && newPosition.positionMs >= it.duration) countedMusicOccurrence = musicOccurrence
                }
                override fun onMediaItemTransition(item: MediaItem?, reason: Int) {
                    if (spec?.getJSONObject("id")?.optString("kind") == "music") {
                        val app = this@AudioEngine.context
                        val request = spec
                        if (app != null && request != null && !musicAllowed(app, request, it.currentMediaItemIndex)) {
                            it.pause(); error = "This track is unavailable or its collection is no longer eligible."
                        }
                        if (app != null && request != null) {
                            updateMusicPrivacy(app)
                            val prefs = app.getSharedPreferences("multiplexr_settings", Context.MODE_PRIVATE)
                            val redacted = privateCollection || !musicAllowed(app, request, it.currentMediaItemIndex) ||
                                (prefs.getBoolean("lockEnabled", false) && prefs.getBoolean("hidePreviews", true))
                            if (metadataRedacted != redacted) privacy(app)
                        }
                    }
                    if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO && sleepTimer.chapterEnded()) {
                        it.pause()
                    }
                    persist()
                }
                override fun onPlaybackStateChanged(state: Int) {
                    if (state == Player.STATE_ENDED) {
                        val stopAtBoundary = sleepTimer.chapterEnded() || sleepTimer.expired(android.os.SystemClock.elapsedRealtime())
                        if (stopAtBoundary) sleepTimer.clear()
                        val endedRevision = transitionRevision
                        persist(complete = { failure -> if (failure == null && !stopAtBoundary && transitionRevision == endedRevision) advanceAudiobook() })
                    } else persist()
                }
                override fun onIsPlayingChanged(isPlaying: Boolean) { persist() }
                override fun onRepeatModeChanged(repeatMode: Int) { if(musicSession()) { spec?.put("repeat",when(repeatMode){Player.REPEAT_MODE_ALL->"all";Player.REPEAT_MODE_ONE->"one";else->"off"});persist() } }
                override fun onPlayerError(failure: PlaybackException) {
                    error = "Could not play this audio file. Reselect it if storage access has changed."
                    persist()
                }
            })
            player = it
        }
        if (!preserveSleep) sleepTimer.clear(); error = null
        val kind = id.getString("kind")
        p.setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA)
            .setContentType(if (kind == "audiobook") C.AUDIO_CONTENT_TYPE_SPEECH else C.AUDIO_CONTENT_TYPE_MUSIC).build(), true)
        p.setMediaItems(items, start, startPosition)
        spec = input
        musicOccurrence++
        p.repeatMode = if (kind == "music") when (input.optString("repeat", "off")) {
            "all" -> Player.REPEAT_MODE_ALL; "one" -> Player.REPEAT_MODE_ONE; else -> Player.REPEAT_MODE_OFF
        } else Player.REPEAT_MODE_OFF
        p.shuffleModeEnabled = false
        privacy(context)
        p.setPlaybackSpeed(context.getSharedPreferences("multiplexr_audio", Context.MODE_PRIVATE).getFloat("rate:$kind", 1f))
        p.prepare()
        try {
            context.startService(Intent(context, AudioPlaybackService::class.java))
            if (input.optBoolean("autoplay", true)) p.play() else p.pause()
        } catch (e: Exception) { p.pause(); throw e }
    }
    private fun advanceAudiobook() {
        val input = spec ?: return
        val active = player ?: return
        val app = context ?: return
        if (stopping || active.playbackState != Player.STATE_ENDED || !active.playWhenReady || input.getJSONObject("id").optString("kind") != "audiobook") return
        val expected = transitionRevision
        io.execute {
            try {
                var next: JSONObject? = null
                var rate = 1f
                SQLiteDatabase.openDatabase(app.getDatabasePath("library.db").path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                    val ownerId = input.getJSONObject("id").getString("collectionId")
                    val owner = db.query("collections", arrayOf("payload"), "id=?", arrayOf(ownerId), null, null, null).use { c -> if (c.moveToFirst()) JSONObject(c.getString(0)) else null }
                    if (owner == null || !owner.optBoolean("autoplayNext", false) || owner.optString("player", "internal") != "internal") return@use
                    // Locked collections may continue chapters, but never automatically open another title.
                    if (owner.optBoolean("locked", false)) return@use
                    val books = db.query("library_state", arrayOf("payload"), "id=?", arrayOf("audio:library"), null, null, null).use { c -> if (c.moveToFirst()) JSONObject(c.getString(0)).getJSONArray("books") else JSONArray() }
                    val book = AudiobookAutoplay.next(books, input.getJSONObject("id")) ?: return@use
                    val progressKey = "progress:" + JSONArray(listOf("audiobook", ownerId, book.getJSONObject("id").getString("itemId"))).toString()
                    val progress = MediaStateKeys.aliases(progressKey).firstNotNullOfOrNull { alias -> db.query("library_state", arrayOf("payload"), "id=?", arrayOf(alias), null, null, null).use { c -> if (c.moveToFirst()) JSONObject(c.getString(0)) else null } }
                    next = AudiobookAutoplay.request(book, progress)
                    rate = owner.optDouble("audioRate", 1.0).toFloat()
                    val seriesId = ownerId + ":" + AudiobookAutoplay.series(book)
                    for (entity in listOf("series:" + seriesId, JSONArray(listOf("audiobook", ownerId, book.getJSONObject("id").getString("itemId"))).toString().replace("\\/", "/"))) {
                        val key = "media:settings:" + JSONArray(listOf(ownerId, entity)).toString().replace("\\/", "/")
                        val settings = MediaStateKeys.aliases(key).firstNotNullOfOrNull { alias -> db.query("library_state", arrayOf("payload"), "id=?", arrayOf(alias), null, null, null).use { c -> if (c.moveToFirst()) JSONObject(c.getString(0)) else null } }
                        val override = settings?.optDouble("rate", 0.0) ?: 0.0
                        if (override in .5..3.0) rate = override.toFloat()
                    }
                }
                val request = next ?: return@execute
                val speed = rate
                Handler(Looper.getMainLooper()).post {
                    if (transitionRevision != expected || stopping || player !== active || active.playbackState != Player.STATE_ENDED || !active.playWhenReady) return@post
                    if (sleepTimer.expired(android.os.SystemClock.elapsedRealtime())) { sleepTimer.clear(); active.pause(); return@post }
                    try { open(app, request, preserveSleep = true); player?.setPlaybackSpeed(speed.coerceIn(.5f, 3f)) }
                    catch (_: Exception) { error = "Could not open the next audiobook. Check its files and folder access."; player?.pause() }
                }
            } catch (_: Exception) {
                Handler(Looper.getMainLooper()).post { if (transitionRevision == expected) error = "Could not load the next audiobook." }
            }
        }
    }
    fun toggle() {
        val p = requirePlayer()
        if (p.isPlaying) p.pause() else {
            val request = spec
            val app = context
            if (request?.getJSONObject("id")?.optString("kind") == "music" && app != null) {
                check(musicAllowed(app, request, p.currentMediaItemIndex)) { "Track is no longer available or eligible." }
            }
            if (p.playerError != null) { error = null; p.prepare() }
            if (p.playbackState == Player.STATE_ENDED) p.seekTo(0, 0)
            p.play()
        }
    }
    fun privacy(context: Context) {
        val p = player ?: return
        val input = spec ?: return
        val prefs = context.getSharedPreferences("multiplexr_settings", Context.MODE_PRIVATE)
        val music = input.getJSONObject("id").optString("kind") == "music"
        if (music) updateMusicPrivacy(context)
        val hidden = privateCollection || (music && !musicAllowed(context, input, p.currentMediaItemIndex)) ||
            (prefs.getBoolean("lockEnabled", false) && prefs.getBoolean("hidePreviews", true))
        metadataRedacted = hidden
        for (i in 0 until p.mediaItemCount) {
            val item = p.getMediaItemAt(i)
            p.replaceMediaItem(i, item.buildUpon().setMediaMetadata(entryMetadata(input, input.getJSONArray("files").getJSONObject(i), hidden)).build())
        }
    }
    private fun entryMetadata(input: JSONObject, file: JSONObject, hidden: Boolean): MediaMetadata {
        val builder = MediaMetadata.Builder().setTitle(if (hidden) "Multiplexr audio" else file.getString("title"))
            .setAlbumTitle(if (hidden) "" else file.optString("album", input.getString("title")))
            .setArtist(if (hidden) "" else file.optString("creator", input.optString("creator")))
        if (!hidden && file.optString("artwork").isNotEmpty()) runCatching {
            val art = file.getString("artwork")
            if (art.startsWith("data:image/") && art.length < 1_000_000) builder.setArtworkData(android.util.Base64.decode(art.substringAfter(','), android.util.Base64.DEFAULT), MediaMetadata.PICTURE_TYPE_FRONT_COVER)
            else if (context != null && art.startsWith(java.io.File(context!!.filesDir,"music-artwork").absolutePath + "/")) {
                val image=java.io.File(art).canonicalFile
                if(image.parentFile==java.io.File(context!!.filesDir,"music-artwork").canonicalFile && image.length()<=2_000_000) builder.setArtworkData(image.readBytes(),MediaMetadata.PICTURE_TYPE_FRONT_COVER)
            }
            else if (art.startsWith("https://") || art.startsWith("content://")) builder.setArtworkUri(android.net.Uri.parse(art))
        }
        return builder.build()
    }
    private fun musicAllowed(app: Context, input: JSONObject, index: Int): Boolean = runCatching {
        val owner = MusicPlaybackPolicy.owner(input, index)
        SQLiteDatabase.openDatabase(app.getDatabasePath("library.db").path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            val collection = db.query("collections", arrayOf("payload"), "id=?", arrayOf(owner.getString("collectionId")), null, null, null).use { c -> if (c.moveToFirst()) JSONObject(c.getString(0)) else null }
            val tracks = LibraryStateStore.raw(db, "music:library")?.getJSONArray("tracks") ?: JSONArray()
            val track = (0 until tracks.length()).map { tracks.getJSONObject(it) }.firstOrNull {
                val id = it.getJSONObject("id"); id.optString("collectionId") == owner.optString("collectionId") && id.optString("itemId") == owner.optString("itemId")
            }
            MusicPlaybackPolicy.allowed(input, index, collection, track)
        }
    }.getOrDefault(false)
    private fun updateMusicPrivacy(app: Context) {
        val input = spec ?: return
        val p = player ?: return
        if (input.getJSONObject("id").optString("kind") != "music" || p.currentMediaItemIndex < 0) return
        val owner = MusicPlaybackPolicy.owner(input, p.currentMediaItemIndex)
        privateCollection = runCatching {
            SQLiteDatabase.openDatabase(app.getDatabasePath("library.db").path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                db.query("collections", arrayOf("payload"), "id=?", arrayOf(owner.getString("collectionId")), null, null, null).use { c ->
                    !c.moveToFirst() || JSONObject(c.getString(0)).optBoolean("locked")
                }
            }
        }.getOrDefault(true)
    }
    fun musicSession() = spec?.getJSONObject("id")?.optString("kind") == "music"
    fun nextMusic(previous: Boolean = false) {
        check(musicSession())
        val p = requirePlayer()
        if (previous) p.seekToPreviousMediaItem() else p.seekToNextMediaItem()
    }
    fun repeatMusic(mode: String) {
        check(musicSession()); require(mode in setOf("off", "all", "one"))
        requirePlayer().repeatMode = when (mode) { "all" -> Player.REPEAT_MODE_ALL; "one" -> Player.REPEAT_MODE_ONE; else -> Player.REPEAT_MODE_OFF }
        spec?.put("repeat", mode); persist()
    }
    fun seek(position: Long) {
        val p = requirePlayer()
        p.seekTo(position.coerceIn(0, if (p.duration > 0) p.duration else Long.MAX_VALUE)); persist()
    }
    fun chapter(index: Int) {
        val p = requirePlayer(); require(index in 0 until p.mediaItemCount)
        if (musicSession()) check(musicAllowed(context!!, spec!!, index)) { "Track is no longer available or eligible." }
        error = null; p.seekTo(index, 0); if (p.playerError != null) p.prepare(); p.play(); persist()
    }
    fun rate(context: Context, rate: Float) {
        require(rate.isFinite() && rate in .5f..3f)
        val kind = spec!!.getJSONObject("id").getString("kind")
        check(context.getSharedPreferences("multiplexr_audio", Context.MODE_PRIVATE).edit().putFloat("rate:$kind", rate).commit())
        requirePlayer().setPlaybackSpeed(rate)
    }
    /** -1 means end of chapter, zero cancels, positive values are minutes. */
    fun sleep(minutes: Long) {
        requirePlayer()
        sleepTimer.set(minutes, System.currentTimeMillis(), android.os.SystemClock.elapsedRealtime())
        persist()
    }
    fun tick() {
        if (++privacyTicks % 10 == 0 && musicSession()) {
            val app = context; val input = spec; val p = player
            if (app != null && input != null && p != null && !musicAllowed(app, input, p.currentMediaItemIndex)) {
                p.pause(); error = "Track is no longer available or eligible."
                privacy(app)
            }
        }
        if (sleepTimer.expired(android.os.SystemClock.elapsedRealtime())) {
            sleepTimer.clear(); player?.pause(); persist()
        }
    }
    fun snapshot(): JSONObject = JSONObject().also { out ->
        val p = player; val input = spec
        if (p != null && input != null) {
            val music = input.getJSONObject("id").optString("kind") == "music"
            val currentId = if (music && p.currentMediaItemIndex >= 0) MusicPlaybackPolicy.owner(input, p.currentMediaItemIndex) else input.getJSONObject("id")
            out.put("id", currentId).put("index", p.currentMediaItemIndex)
                .put("positionMs", p.currentPosition.coerceAtLeast(0)).put("durationMs", p.duration.coerceAtLeast(0))
                .put("playing", p.isPlaying).put("buffering", p.playbackState == Player.STATE_BUFFERING)
                .put("finished", p.playbackState == Player.STATE_ENDED).put("rate", p.playbackParameters.speed)
                .put("deadline", sleepTimer.deadlineUtcMs).put("endOfChapter", sleepTimer.endOfChapter).put("error", error)
            if (music) out.put("repeat", input.optString("repeat", "off"))
        }
    }
    fun bookmark(label: String, complete: (String?) -> Unit) {
        require(spec?.getJSONObject("id")?.getString("kind") == "audiobook")
        require(label.length <= 200)
        persist(label, complete)
    }
    fun persist(bookmark: String? = null, complete: ((String?) -> Unit)? = null) {
        val input = spec ?: return
        val p = player ?: return
        if (musicSession()) {
            persistMusic(p.currentMediaItemIndex, p.currentPosition.coerceAtLeast(0), p.playbackState == Player.STATE_ENDED)
            complete?.invoke(null)
            return
        }
        val index = p.currentMediaItemIndex
        if (index !in 0 until p.mediaItemCount) return
        val id = input.getJSONObject("id")
        val kind = id.getString("kind")
        val key = MediaStateKeys.canonical("progress:" + JSONArray(listOf(kind, id.getString("collectionId"), id.getString("itemId"))).toString())
        val saved = JSONObject().put("id", id).put("positionMs", p.currentPosition.coerceAtLeast(0))
        val chapterId = p.getMediaItemAt(index).mediaId
        if (kind == "audiobook") {
            saved.put("chapterId", chapterId).put("finished", p.playbackState == Player.STATE_ENDED)
            if (sleepTimer.deadlineUtcMs > 0) saved.put("sleep", JSONObject().put("mode", "deadline").put("deadlineUtcMs", sleepTimer.deadlineUtcMs))
            else if (sleepTimer.endOfChapter) saved.put("sleep", JSONObject().put("mode", "endOfChapter"))
        }
        val database = context?.getDatabasePath("library.db") ?: return
        val expectedGeneration = generation
        io.execute {
            var failure: String? = null
            try {
                SQLiteDatabase.openDatabase(database.path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
                    db.beginTransaction()
                    try {
                        if (generation != expectedGeneration) return@use
                        if (kind == "audiobook") {
                            val exists = db.query("library_state", arrayOf("payload"), "id=?", arrayOf("audio:library"), null, null, null).use { cursor ->
                                if (!cursor.moveToFirst()) false else {
                                    val books = JSONObject(cursor.getString(0)).getJSONArray("books")
                                    (0 until books.length()).any { books.getJSONObject(it).getJSONObject("id").let { b -> b.getString("itemId") == id.getString("itemId") && b.getString("collectionId") == id.getString("collectionId") } }
                                }
                            }
                            if (!exists) return@use
                        }
                        val old = MediaStateKeys.aliases(key).firstNotNullOfOrNull { candidate -> db.query("library_state", arrayOf("payload"), "id=?", arrayOf(candidate), null, null, null).use { cursor ->
                            if (cursor.moveToFirst()) JSONObject(cursor.getString(0)) else null
                        } } ?: JSONObject()
                        if (kind == "audiobook") {
                            val marks = old.optJSONArray("bookmarks") ?: JSONArray()
                            if (bookmark != null) {
                                check(marks.length() < 5000) { "This book has reached the bookmark limit." }
                                marks.put(JSONObject().put("chapterId", chapterId)
                                    .put("positionMs", saved.getLong("positionMs")).put("label", bookmark))
                            }
                            saved.put("bookmarks", marks)
                        } else saved.put("playCount", old.optInt("playCount"))
                        LibraryStateStore.put(db, key, saved)
                        db.setTransactionSuccessful()
                    } finally { db.endTransaction() }
                }
            } catch (e: Exception) { failure = e.message ?: "Could not save audio progress to device storage." }
            val failed = failure
            Handler(Looper.getMainLooper()).post {
                if (failed != null) error = failed
                complete?.invoke(failed)
            }
        }
    }
    private fun persistMusic(index: Int, position: Long, completed: Boolean) {
        val input = spec ?: return
        if (index !in 0 until input.getJSONArray("files").length()) return
        val id = MusicPlaybackPolicy.owner(input, index)
        val key = MediaStateKeys.canonical("progress:" + JSONArray(listOf("music", id.getString("collectionId"), id.getString("itemId"))).toString())
        val increment = completed && countedMusicOccurrence != musicOccurrence
        if (increment) countedMusicOccurrence = musicOccurrence
        val database = context?.getDatabasePath("library.db") ?: return
        val expectedGeneration = generation
        val playedAt = if(player?.isPlaying == true) System.currentTimeMillis() else 0L
        val session = MusicSessionCodec.snapshot(input, player?.currentMediaItemIndex?.coerceAtLeast(0) ?: index,
            if (player?.playbackState == Player.STATE_ENDED) 0 else player?.currentPosition?.coerceAtLeast(0) ?: position)
        io.execute {
            try {
                SQLiteDatabase.openDatabase(database.path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
                    LibraryStateStore.transaction(db) {
                        if (generation != expectedGeneration) return@transaction
                        val tracks = LibraryStateStore.raw(db, "music:library")?.getJSONArray("tracks") ?: return@transaction
                        if (!(0 until tracks.length()).any { tracks.getJSONObject(it).getJSONObject("id").let { t -> t.optString("collectionId") == id.optString("collectionId") && t.optString("itemId") == id.optString("itemId") } }) return@transaction
                        val old = LibraryStateStore.read(db, key)
                        LibraryStateStore.put(db, key, JSONObject().put("id", id).put("positionMs", if (completed) 0 else position)
                            .put("playCount", (old?.optLong("playCount") ?: 0L) + if (increment) 1 else 0).put("lastPlayedAt",if(playedAt>0)playedAt else old?.optLong("lastPlayedAt") ?: 0L))
                        val collections = db.query("collections", arrayOf("id"), null, null, null, null, null).use { c ->
                            buildSet { while (c.moveToNext()) add(c.getString(0)) }
                        }
                        var retained: JSONObject? = session
                        val entries = session.getJSONArray("entries")
                        for (owner in (0 until entries.length()).map { entries.getJSONObject(it).getJSONObject("owner").getString("collectionId") }.toSet() - collections) {
                            retained = retained?.let { MusicSessionCodec.withoutCollection(it, owner) }
                        }
                        if (retained != null) LibraryStateStore.put(db, "music:session", retained) else LibraryStateStore.delete(db, "music:session")
                    }
                }
            } catch (_: Exception) { Handler(Looper.getMainLooper()).post { error = "Could not save Music playback progress." } }
        }
    }
    fun stop(context: Context) {
        transitionRevision++
        persist()
        stopping = attached
        val service = AudioPlaybackService.instance
        if (service != null) service.finishPlayback()
        else {
            player?.pause()
            context.stopService(Intent(context, AudioPlaybackService::class.java))
            if (!attached) release()
        }
    }
    fun discard(context: Context) {
        generation++; spec = null; stop(context)
    }
    fun release() {
        transitionRevision++
        val previous = player
        spec = null; player = null
        previous?.release()
        sleepTimer.clear(); attached = false; stopping = false
    }
}

class AudioPlaybackService : MediaSessionService() {
    companion object { var instance: AudioPlaybackService? = null; private set }
    private var session: MediaSession? = null
    private var closing = false
    private val handler = Handler(Looper.getMainLooper())
    private var ticks = 0
    private val update = object : Runnable {
        override fun run() {
            AudioEngine.tick()
            if (++ticks % 10 == 0) AudioEngine.persist()
            handler.postDelayed(this, 500)
        }
    }
    override fun onCreate() {
        super.onCreate()
        instance = this
        setMediaNotificationProvider(DefaultMediaNotificationProvider.Builder(this).setNotificationId(1002).build())
        val player = AudioEngine.current() ?: run {
            // Media3 1.9 can deliver a queued foreground-start intent after a
            // session was stopped. Acknowledge it before stopping the empty service.
            val manager = getSystemService(android.app.NotificationManager::class.java)
            val channel = "multiplexr_audio_shutdown"
            if (android.os.Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
                android.app.NotificationChannel(channel, "Audio playback", android.app.NotificationManager.IMPORTANCE_LOW))
            val builder = if (android.os.Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(this, channel)
                else android.app.Notification.Builder(this)
            val notification = builder.setSmallIcon(android.R.drawable.ic_media_pause)
                .setContentTitle("Multiplexr").setContentText("Stopping playback").build()
            if (android.os.Build.VERSION.SDK_INT >= 29) startForeground(1002, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            else startForeground(1002, notification)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        AudioEngine.attached = true
        val activity = PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        session = MediaSession.Builder(this, player).setSessionActivity(activity)
            .setCallback(object : MediaSession.Callback {
                override fun onConnect(session: MediaSession, controller: MediaSession.ControllerInfo): MediaSession.ConnectionResult {
                    // Music traversal is owned by the typed queue adapter. Do not
                    // advertise a second shuffle implementation to controllers.
                    return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                        .setAvailablePlayerCommands(MediaSession.ConnectionResult.DEFAULT_PLAYER_COMMANDS.buildUpon()
                            .remove(Player.COMMAND_SET_SHUFFLE_MODE).build()).build()
                }
            }).build()
        addSession(session!!)
        handler.post(update)
    }
    fun finishPlayback() {
        if (closing) return
        closing = true
        handler.removeCallbacks(update)
        // Disable Media3's foreground keep-alive before changing playWhenReady.
        // Pausing then calling Context.stopService can race a new foreground start.
        pauseAllPlayersAndStopSelf()
    }
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = if (closing) null else session
    override fun onTaskRemoved(rootIntent: Intent?) {
        AudioEngine.persist()
        if (AudioEngine.privateCollection || AudioEngine.current()?.playWhenReady != true || AudioEngine.current()?.playbackState == Player.STATE_ENDED) {
            finishPlayback()
        }
    }
    override fun onDestroy() {
        handler.removeCallbacks(update)
        AudioEngine.persist()
        session?.release(); session = null
        AudioEngine.release()
        instance = null
        super.onDestroy()
    }
}
