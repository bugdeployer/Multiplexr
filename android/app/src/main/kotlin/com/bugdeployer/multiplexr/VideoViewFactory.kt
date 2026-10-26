package com.bugdeployer.multiplexr

import android.content.Context
import android.graphics.Color
import android.view.LayoutInflater
import android.view.View
import androidx.media3.common.*
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class VideoViewFactory(private val messenger: BinaryMessenger, private val pickSubtitle: (MethodChannel.Result) -> Unit) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = VideoView(context, viewId, args as Map<*, *>, messenger, pickSubtitle)
}
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
private class VideoView(private val context: Context, id: Int, args: Map<*, *>, messenger: BinaryMessenger, private val pickSubtitle: (MethodChannel.Result) -> Unit) : PlatformView {
    private val player = PlaybackEngine.player(context)
    private val preferences = context.getSharedPreferences("multiplexr_player", Context.MODE_PRIVATE)
    private val assetKey = java.security.MessageDigest.getInstance("SHA-256").digest(
        "${args["collectionId"]}:${args["assetId"]}".toByteArray()).joinToString("") { "%02x".format(it) }
    private var externalUri = preferences.getString("subtitleUri_$assetKey", null)
    private var externalName = preferences.getString("subtitleName_$assetKey", null)
    private var externalMime = preferences.getString("subtitleMime_$assetKey", null)
    private var selectExternal = externalUri != null && !preferences.getBoolean("subtitleOff", false)
    private var fit = preferences.getString("fit", "fit") ?: "fit"
    private val view = LayoutInflater.from(context).inflate(R.layout.video_surface, null) as PlayerView
    private val channel = MethodChannel(messenger, "multiplexr/player/$id")
    private var released = false
    private var failure: String? = null
    private val listener = object : Player.Listener {
        override fun onTracksChanged(tracks: Tracks) {
            if (!selectExternal) return
            tracks.groups.forEach { group ->
                if (group.type == C.TRACK_TYPE_TEXT) for (index in 0 until group.length) {
                    if (group.getTrackFormat(index).id == "multiplexr-external" && group.isTrackSupported(index)) {
                        selectExternal = false
                        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                            .clearOverridesOfType(C.TRACK_TYPE_TEXT).setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, index)).build()
                        return
                    }
                }
            }
        }
        override fun onPlayerError(error: PlaybackException) { failure = PlaybackFailures.message(error.errorCode) }
    }
    private var subtitleScale = preferences.getFloat("subtitleScale", 1f).coerceIn(.6f, 2f)
    private var subtitleBackground = preferences.getBoolean("subtitleBackground", false)
    private var controlsVisible = true
    private fun styleSubtitles() {
        view.subtitleView?.apply {
            setApplyEmbeddedStyles(false)
            setApplyEmbeddedFontSizes(false)
            setFractionalTextSize(.0533f * subtitleScale)
            setBottomPaddingFraction(if (controlsVisible) .24f else .08f)
            setStyle(CaptionStyleCompat(Color.WHITE, if (subtitleBackground) 0x99000000.toInt() else Color.TRANSPARENT,
                Color.TRANSPARENT, CaptionStyleCompat.EDGE_TYPE_OUTLINE, Color.BLACK, null))
        }
    }
    private fun save(edit: android.content.SharedPreferences.Editor.() -> Unit) {
        check(preferences.edit().apply(edit).commit()) { "Could not save playback preferences." }
    }
    private fun applyFit() {
        view.resizeMode = when (fit) {
            "fill" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            "stretch" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
    }
    private fun applyPreferences() {
        player.setPlaybackSpeed(preferences.getFloat("rate", 1f).coerceIn(.25f, 3f))
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .clearOverrides()
            .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, preferences.getBoolean("subtitleOff", false))
            .setPreferredAudioLanguage(preferences.getString("audioLanguage", null))
            .setPreferredTextLanguage(preferences.getString("subtitleLanguage", null))
            .build()
        applyFit()
        styleSubtitles()
    }
    private fun mediaWithSubtitle(item: MediaItem): MediaItem {
        val uri = externalUri ?: return item.buildUpon().setSubtitleConfigurations(emptyList()).build()
        return item.buildUpon().setSubtitleConfigurations(listOf(
            MediaItem.SubtitleConfiguration.Builder(android.net.Uri.parse(uri))
                .setId("multiplexr-external").setMimeType(externalMime ?: MimeTypes.APPLICATION_SUBRIP)
                .setLabel(externalName ?: "External subtitles")
                .setSelectionFlags(C.SELECTION_FLAG_DEFAULT).build()
        )).build()
    }
    private fun reloadSubtitle() {
        val item = player.currentMediaItem ?: return
        val position = player.currentPosition.coerceAtLeast(0)
        val playing = player.playWhenReady
        failure = null
        player.setMediaItem(mediaWithSubtitle(item), position)
        player.prepare()
        player.playWhenReady = playing
    }
    init {
        AudioEngine.stop(context)
        PlaybackEngine.views++
        PlaybackEngine.activeView = view
        val reuseSession = PlaybackLifetime.reuse(PlaybackEngine.background, PlaybackEngine.collectionId,
            PlaybackEngine.assetId, args["collectionId"] as? String ?: "", args["assetId"] as? String ?: "",
            player.currentMediaItem?.localConfiguration?.uri?.toString(), args["uri"] as String)
        PlaybackEngine.assetId = args["assetId"] as? String ?: ""
        PlaybackEngine.collectionId = args["collectionId"] as? String ?: ""
        view.setBackgroundColor(Color.BLACK)
        player.setAudioAttributes(AudioAttributes.DEFAULT, true)
        view.player = player
        view.useController = false
        view.keepScreenOn = true
        applyPreferences()
        player.addListener(listener)
        val settings = context.getSharedPreferences("multiplexr_settings", Context.MODE_PRIVATE)
        val privateTitle = PlaybackEngine.collectionPrivate || (settings.getBoolean("lockEnabled", false) && settings.getBoolean("hidePreviews", true))
        if (!reuseSession) {
            player.setMediaItem(mediaWithSubtitle(MediaItem.Builder().setUri(args["uri"] as String)
                .setMediaMetadata(MediaMetadata.Builder().setTitle(if (privateTitle) "Multiplexr playback" else args["title"] as? String ?: "Multiplexr").build()).build()))
            player.seekTo((args["positionMs"] as? Number)?.toLong() ?: 0)
            player.prepare()
            player.playWhenReady = true
        }
        if (!PlaybackEngine.collectionPrivate && preferences.getBoolean("backgroundPlayback", false) && !PlaybackEngine.background) {
            PlaybackEngine.setBackground(context, true)
        }
        channel.setMethodCallHandler { call, result ->
            if (released) { result.error("disposed", "Player has closed.", null); return@setMethodCallHandler }
            try {
                when (call.method) {
                    "state" -> { result.success(snapshot()); return@setMethodCallHandler }
                    "playPause" -> if (player.isPlaying) player.pause() else {
                        if (!PlaybackEngine.collectionPrivate && preferences.getBoolean("backgroundPlayback", false) && !PlaybackEngine.background) PlaybackEngine.setBackground(context, true)
                        if (player.playbackState == Player.STATE_ENDED) player.seekTo(0)
                        player.play()
                    }
                    "pause" -> player.pause()
                    "seek" -> player.seekTo((call.arguments as Number).toLong().coerceAtLeast(0))
                    "rate" -> { val rate = (call.arguments as Number).toFloat().coerceIn(.25f, 3f); save { putFloat("rate", rate) }; player.setPlaybackSpeed(rate) }
                    "volume" -> player.volume = (call.arguments as Number).toFloat().coerceIn(0f, 1f)
                    "repeat" -> player.repeatMode = if (call.arguments == true) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                    "fit" -> {
                        val value = call.arguments as String
                        require(value in listOf("fit", "fill", "stretch"))
                        save { putString("fit", value) }; fit = value; applyFit()
                    }
                    "subtitleStyle" -> {
                        val settings = call.arguments as Map<*, *>
                        subtitleScale = (settings["scale"] as Number).toFloat().coerceIn(.6f, 2f)
                        subtitleBackground = settings["background"] == true
                        save { putFloat("subtitleScale", subtitleScale); putBoolean("subtitleBackground", subtitleBackground) }
                        styleSubtitles()
                    }
                    "controlsVisible" -> { controlsVisible = call.arguments == true; styleSubtitles() }
                    "retry" -> { failure = null; player.prepare(); player.play() }
                    "autoPip" -> {
                        val enabled = call.arguments == true
                        require(!enabled || !PlaybackEngine.collectionPrivate) { "Floating playback is disabled for locked collections." }
                        require(!enabled || (android.os.Build.VERSION.SDK_INT >= 26 && context.packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE))) { "Floating video is unavailable on this device." }
                        check(context.getSharedPreferences("multiplexr_settings", Context.MODE_PRIVATE).edit().putBoolean("autoPip", enabled).commit()) { "Could not save floating window preference." }
                    }
                    "background" -> {
                        val enabled = call.arguments == true
                        PlaybackEngine.setBackground(context, enabled)
                        save { putBoolean("backgroundPlayback", enabled) }
                    }
                    "addSubtitle" -> {
                        player.pause()
                        pickSubtitle(object : MethodChannel.Result {
                            override fun success(value: Any?) {
                                if (released) {
                                    (value as? Map<*, *>)?.get("uri")?.let { java.io.File(java.net.URI(it as String)).delete() }
                                    result.success(null); return
                                }
                                if (value !is Map<*, *>) { result.success(null); return }
                                try {
                                    val uri = value["uri"] as String
                                    val name = value["name"] as String
                                    val mime = value["mime"] as String
                                    val old = externalUri
                                    save { putString("subtitleUri_$assetKey", uri); putString("subtitleName_$assetKey", name); putString("subtitleMime_$assetKey", mime); putBoolean("subtitleOff", false) }
                                    externalUri = uri; externalName = name; externalMime = mime; selectExternal = true
                                    player.trackSelectionParameters = player.trackSelectionParameters.buildUpon().clearOverridesOfType(C.TRACK_TYPE_TEXT).setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false).build()
                                    reloadSubtitle()
                                    old?.let { if (it != uri) java.io.File(java.net.URI(it)).delete() }
                                    result.success(null)
                                } catch (_: Exception) { result.error("subtitle", "Could not attach subtitles. Choose the file again.", null) }
                            }
                            override fun error(code: String, message: String?, details: Any?) { result.error(code, message, details) }
                            override fun notImplemented() { result.notImplemented() }
                        })
                        return@setMethodCallHandler
                    }
                    "removeSubtitle" -> {
                        val old = externalUri
                        save { remove("subtitleUri_$assetKey"); remove("subtitleName_$assetKey"); remove("subtitleMime_$assetKey") }
                        externalUri = null; externalName = null; externalMime = null; selectExternal = false
                        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon().clearOverridesOfType(C.TRACK_TYPE_TEXT).build()
                        reloadSubtitle()
                        old?.let { java.io.File(java.net.URI(it)).delete() }
                    }
                    "resetPreferences" -> {
                        save { for (key in listOf("rate", "fit", "subtitleScale", "subtitleBackground", "subtitleOff", "audioLanguage", "subtitleLanguage")) remove(key) }
                        fit = "fit"; subtitleScale = 1f; subtitleBackground = false
                        applyPreferences()
                    }
                    "audio" -> select(C.TRACK_TYPE_AUDIO, call.arguments as String)
                    "subtitle" -> select(C.TRACK_TYPE_TEXT, call.arguments as String)
                    "dispose" -> dispose()
                    else -> { result.notImplemented(); return@setMethodCallHandler }
                }
                result.success(null)
            } catch (error: Exception) { result.error("player", error.message ?: "This playback option is unavailable for this file.", null) }
        }
    }
    private fun select(type: Int, id: String) {
        if (type == C.TRACK_TYPE_TEXT) selectExternal = false
        val builder = player.trackSelectionParameters.buildUpon().clearOverridesOfType(type).setTrackTypeDisabled(type, id == "no")
        if (id != "auto" && id != "no") {
            val parts = id.split(':').map { it.toInt() }
            val group = player.currentTracks.groups[parts[0]]
            require(group.type == type && group.isTrackSupported(parts[1]))
            builder.setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, parts[1]))
        }
        val language = if (id != "auto" && id != "no") {
            val parts = id.split(':').map { it.toInt() }
            player.currentTracks.groups[parts[0]].getTrackFormat(parts[1]).language
        } else null
        save {
            if (type == C.TRACK_TYPE_TEXT) {
                putBoolean("subtitleOff", id == "no")
                if (language != null) putString("subtitleLanguage", language)
                else if (id == "auto") remove("subtitleLanguage")
            } else {
                if (language != null) putString("audioLanguage", language)
                else if (id == "auto") remove("audioLanguage")
            }
        }
        if (type == C.TRACK_TYPE_AUDIO) builder.setPreferredAudioLanguage(language)
        else builder.setPreferredTextLanguage(language)
        player.trackSelectionParameters = builder.build()
    }
    private fun tracks(type: Int): List<Map<String, Any?>> = buildList {
        add(mapOf("id" to "auto", "title" to "Automatic"))
        add(mapOf("id" to "no", "title" to "Off"))
        player.currentTracks.groups.forEachIndexed { index, group ->
            if (group.type == type) for (track in 0 until group.length) {
                if (group.isTrackSupported(track)) {
                    val format = group.getTrackFormat(track)
                    add(mapOf("id" to "$index:$track", "title" to format.label, "language" to format.language))
                }
            }
        }
    }
    private fun selected(type: Int): String {
        if (type in player.trackSelectionParameters.disabledTrackTypes) return "no"
        player.currentTracks.groups.forEachIndexed { index, group ->
            if (group.type == type) for (track in 0 until group.length) { if (group.isTrackSelected(track)) return "$index:$track" }
        }
        return "auto"
    }
    private fun snapshot(): Map<String, Any?> = mapOf(
        "positionMs" to player.currentPosition.coerceAtLeast(0), "durationMs" to player.duration.coerceAtLeast(0),
        "playing" to player.isPlaying, "completed" to (player.playbackState == Player.STATE_ENDED),
        "buffering" to (player.playbackState == Player.STATE_BUFFERING), "rate" to player.playbackParameters.speed.toDouble(),
        "volume" to player.volume.toDouble(), "repeat" to (player.repeatMode == Player.REPEAT_MODE_ONE),
        "fit" to fit, "subtitleScale" to subtitleScale.toDouble(), "subtitleBackground" to subtitleBackground,
        "externalSubtitle" to externalName,
        "background" to PlaybackEngine.background,
        "privateCollection" to PlaybackEngine.collectionPrivate,
        "autoPip" to (!PlaybackEngine.collectionPrivate && context.getSharedPreferences("multiplexr_settings", Context.MODE_PRIVATE).getBoolean("autoPip", false)),
        "audio" to tracks(C.TRACK_TYPE_AUDIO), "subtitles" to tracks(C.TRACK_TYPE_TEXT),
        "selectedAudio" to selected(C.TRACK_TYPE_AUDIO), "selectedSubtitle" to selected(C.TRACK_TYPE_TEXT), "error" to failure,
    )
    override fun getView(): View = view
    override fun dispose() {
        if (released) return
        released = true
        view.keepScreenOn = false
        view.player = null
        player.removeListener(listener)
        if (PlaybackEngine.activeView === view) PlaybackEngine.activeView = null
        PlaybackEngine.views--
        PlaybackEngine.releaseIfIdle()
        channel.setMethodCallHandler(null)
    }
}
