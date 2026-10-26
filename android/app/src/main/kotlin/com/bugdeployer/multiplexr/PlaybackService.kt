package com.bugdeployer.multiplexr

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/** One playback engine shared by the visible surface and the media session. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object PlaybackEngine {
    private var instance: ExoPlayer? = null
    var collectionPrivate = false
    var background = false
    var serviceAttached = false
    var inPip = false
    var activeView: android.view.View? = null
    var views = 0
    @Volatile var libraryGeneration = 0L
    var assetId = ""
    var collectionId = ""
    fun current(): ExoPlayer? = instance
    fun player(context: Context): ExoPlayer = instance ?: ExoPlayer.Builder(context.applicationContext).build().also {
        it.setAudioAttributes(AudioAttributes.DEFAULT, true)
        it.setHandleAudioBecomingNoisy(true)
        it.setWakeMode(C.WAKE_MODE_LOCAL)
        instance = it
    }
    fun setBackground(context: Context, enabled: Boolean) {
        require(!enabled || !collectionPrivate) { "Background playback is disabled for locked collections." }
        if (enabled) context.startService(Intent(context, PlaybackService::class.java))
        else context.stopService(Intent(context, PlaybackService::class.java))
        background = enabled
    }
    fun pauseUnlessAllowed() { if (PlaybackLifetime.pauseOnDeparture(background, collectionPrivate, inPip)) instance?.pause() }
    fun releaseIfIdle() {
        if (PlaybackLifetime.release(views, background, serviceAttached)) { instance?.release(); instance = null }
    }
}

class PlaybackService : MediaSessionService() {
    companion object { var instance: PlaybackService? = null; private set }
    private var session: MediaSession? = null
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private val io = java.util.concurrent.Executors.newSingleThreadExecutor()
    private val save = object : Runnable {
        override fun run() { persist(); handler.postDelayed(this, 5000) }
    }
    private fun persist() {
        val generation = PlaybackEngine.libraryGeneration
        val id = PlaybackEngine.assetId; val collection = PlaybackEngine.collectionId
        if (id.isEmpty() || collection.isEmpty()) return
        val player = PlaybackEngine.current() ?: return
        val position = player.currentPosition.coerceAtLeast(0)
        val duration = player.duration.coerceAtLeast(0)
        io.execute {
            try {
                android.database.sqlite.SQLiteDatabase.openDatabase(getDatabasePath("library.db").path, null,
                    android.database.sqlite.SQLiteDatabase.OPEN_READWRITE).use { db ->
                    db.beginTransaction()
                    try {
                        if (generation != PlaybackEngine.libraryGeneration) return@use
                        db.query("assets", arrayOf("payload"), "collection_id=? AND id=?", arrayOf(collection, id), null, null, null).use { cursor ->
                            if (cursor.moveToFirst()) {
                                val payload = org.json.JSONObject(cursor.getString(0))
                                WatchProgress.apply(payload, position, duration)
                                db.update("assets", android.content.ContentValues().apply { put("payload", payload.toString()) },
                                    "collection_id=? AND id=?", arrayOf(collection, id))
                            }
                        }
                        db.setTransactionSuccessful()
                    } finally { db.endTransaction() }
                }
            } catch (_: Exception) { /* A removed collection must not stop audio playback. */ }
        }
    }
    override fun onCreate() {
        super.onCreate()
        instance = this
        PlaybackEngine.serviceAttached = true
        val activity = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        session = MediaSession.Builder(this, PlaybackEngine.player(this)).setSessionActivity(activity).build()
        addSession(session!!)
        handler.post(save)
    }
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session
    fun handoffToAudio() {
        persist()
        PlaybackEngine.background = false
        pauseAllPlayersAndStopSelf()
    }
    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = PlaybackEngine.current()
        persist()
        if (PlaybackLifetime.keepAfterTaskRemoval(PlaybackEngine.background,
                PlaybackEngine.collectionPrivate, player?.playWhenReady == true,
                (player?.mediaItemCount ?: 0) > 0, player?.playbackState == androidx.media3.common.Player.STATE_ENDED)) {
            // The media service, not the dismissed Activity, owns this session.
            return
        }
        pauseAllPlayersAndStopSelf()
    }
    override fun onDestroy() {
        handler.removeCallbacks(save)
        persist()
        io.shutdown()
        session?.release(); session = null
        PlaybackEngine.background = false
        PlaybackEngine.serviceAttached = false
        instance = null
        if (PlaybackEngine.views == 0) PlaybackEngine.pauseUnlessAllowed()
        PlaybackEngine.releaseIfIdle()
        super.onDestroy()
    }
}
