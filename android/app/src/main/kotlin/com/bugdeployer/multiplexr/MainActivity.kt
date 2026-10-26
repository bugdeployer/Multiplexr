package com.bugdeployer.multiplexr

import android.Manifest
import android.app.*
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val prefs by lazy { getSharedPreferences("multiplexr_settings", MODE_PRIVATE) }
    private val devicePreferences by lazy { DevicePreferences(prefs) }
    private val manager by lazy { getSystemService(NotificationManager::class.java) }
    private lateinit var library: LibraryHost
    private var audio: AudioHost? = null
    private var plugins: com.bugdeployer.multiplexr.plugins.PluginHost? = null
    private val themeDocuments by lazy { ThemeDocuments(this) }
    private val subtitlePicker by lazy { SubtitlePicker(this) }
    private var playbackChannel: MethodChannel? = null
    private var readingKeys: MethodChannel? = null
    private var readingVolumeKeys = false
    private var stopped = false
    private var authResult: MethodChannel.Result? = null
    private var permissionResult: MethodChannel.Result? = null
    private var cancellation: CancellationSignal? = null
    private var authenticatedAt = 0L
    private val categories = mapOf("completed" to "Indexing completed", "errors" to "Source errors", "activity" to "Background activity")
    private fun channelId(category: String) = "multiplexr_$category"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        secureWindow(prefs.getBoolean("lockEnabled", false))
        if (Build.VERSION.SDK_INT >= 26) {
            for ((id, name) in categories) {
                manager.createNotificationChannel(NotificationChannel(channelId(id), name,
                    if (id == "activity") NotificationManager.IMPORTANCE_LOW else NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Multiplexr $name"
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                })
            }
            // Migrate the shell's single legacy test channel.
            manager.deleteNotificationChannel("library_updates")
        }
    }

    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        if (readingVolumeKeys && !stopped && event.keyCode in listOf(android.view.KeyEvent.KEYCODE_VOLUME_DOWN, android.view.KeyEvent.KEYCODE_VOLUME_UP)) {
            if (event.action == android.view.KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                readingKeys?.invokeMethod("turn", event.keyCode == android.view.KeyEvent.KEYCODE_VOLUME_DOWN)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        plugins = try { com.bugdeployer.multiplexr.plugins.PluginHost(this, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "multiplexr/plugins")) } catch(_: Exception) { null }
        flutterEngine.platformViewsController.registry.registerViewFactory("multiplexr/video", VideoViewFactory(flutterEngine.dartExecutor.binaryMessenger) { result -> subtitlePicker.pick(result) })
        library = LibraryHost(this, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "multiplexr/library"), pluginMutation = { args, operation -> val host=plugins ?: error("Plugin gateway unavailable"); host.withMutation(args,operation) }, pluginCommit = { identity, operation -> val host=plugins ?: error("Plugin gateway unavailable"); host.withMetadataCommit(identity,operation) })
        readingKeys = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "multiplexr/reading-keys").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "enabled") { readingVolumeKeys = call.arguments == true; result.success(null) } else result.notImplemented()
            }
        }
        audio = AudioHost(this, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "multiplexr/audio"))
        playbackChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "multiplexr/playback").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "enterPip") {
                    if (PlaybackEngine.collectionPrivate) { result.error("locked", "Floating playback is disabled for locked collections.", null); return@setMethodCallHandler }
                    if (Build.VERSION.SDK_INT < 26 || !packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
                        result.error("unavailable", "Floating video is unavailable on this device.", null)
                    } else try {
                        val builder = PictureInPictureParams.Builder().setAspectRatio(android.util.Rational(16, 9))
                        val bounds = call.arguments as? Map<*, *>
                        if (bounds != null) builder.setSourceRectHint(android.graphics.Rect(
                            (bounds["left"] as Number).toInt(), (bounds["top"] as Number).toInt(),
                            (bounds["right"] as Number).toInt(), (bounds["bottom"] as Number).toInt()))
                        PlaybackEngine.inPip = true
                        val entered = enterPictureInPictureMode(builder.build())
                        if (!entered) PlaybackEngine.inPip = false
                        result.success(entered)
                    } catch (_: Exception) {
                        PlaybackEngine.inPip = false
                        result.error("pip", "Could not open floating video. Check Android picture-in-picture permission for Multiplexr.", null)
                    }
                } else result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "multiplexr/device").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "load" -> result.success(status())
                    "buildInfo" -> {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION")
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                        result.success(mapOf("version" to (info.versionName ?: "Unavailable"),
                            "build" to code.toString(), "package" to packageName))
                    }
                    "readThemeFile" -> themeDocuments.open(result)
                    "writeThemeFile" -> themeDocuments.save(call.arguments as String, result)
                    "save" -> {
                        if (!devicePreferences.appearance(call.arguments as Map<*, *>)) result.error("storage", "Could not save appearance.", null) else result.success(null)
                    }
                    "collectionPrivacy" -> {
                        PlaybackEngine.collectionPrivate = call.arguments == true
                        if (PlaybackEngine.collectionPrivate) {
                            if (!AudioEngine.musicSession()) AudioEngine.privateCollection = true
                            AudioEngine.privacy(this)
                            if (AudioEngine.privateCollection) AudioEngine.current()?.pause()
                            PlaybackEngine.current()?.pause()
                            PlaybackEngine.setBackground(this, false)
                        }
                        secureWindow(prefs.getBoolean("lockEnabled", false))
                        result.success(null)
                    }
                    "authenticate" -> authenticate(result)
                    "saveSecurity" -> {
                        if (prefs.getBoolean("lockEnabled", false) && !freshAuthentication()) {
                            result.error("authentication_required", "Authenticate before changing security settings.", null)
                        } else {
                            if (!devicePreferences.security(call.arguments as Map<*, *>)) result.error("storage", "Could not save security settings.", null)
                            else {
                                authenticatedAt = 0
                                secureWindow(prefs.getBoolean("lockEnabled", false))
                                manager.cancelAll() // Never leave old detailed notifications after privacy changes.
                                result.success(null)
                            }
                        }
                    }
                    "setCategory" -> {
                        val values = call.arguments as Map<*, *>
                        val id = values["category"] as String
                        DevicePreferencePolicy.category(id)
                        val enabled = values["enabled"] as Boolean
                        if (!devicePreferences.category(id, enabled)) result.error("storage", "Could not save category.", null)
                        else { if (!enabled) manager.cancel(id.hashCode()); result.success(null) }
                    }
                    "setLock" -> {
                        val enabled = call.arguments as Boolean
                        if (!freshAuthentication()) {
                            result.error("authentication_required", "Authenticate before changing app lock.", null)
                        } else {
                            authenticatedAt = 0
                            if (devicePreferences.lock(enabled)) {
                                secureWindow(enabled)
                                result.success(null)
                            } else result.error("storage", "Could not save app lock.", null)
                        }
                    }
                    "requestNotifications" -> {
                        if (permissionResult != null) result.error("busy", "Permission request already open.", null)
                        else if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            permissionResult = result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
                        } else result.success(notificationsAllowed())
                    }
                    "setNotifications" -> {
                        val enabled = call.arguments as Boolean
                        if (enabled && !notificationsAllowed()) result.error("permission", "Allow notifications in Android settings first.", null)
                        else if (!devicePreferences.notifications(enabled)) result.error("storage", "Could not save notification preference.", null)
                        else {
                            if (!enabled) manager.cancelAll()
                            result.success(null)
                        }
                    }
                    "testNotification" -> {
                        val id = call.arguments as? String ?: "completed"
                        postNotification(id, "Test: ${categories[id] ?: id}", "Your ${categories[id]?.lowercase() ?: id} notification is working.", result)
                    }
                    "postNotification" -> {
                        val values = call.arguments as Map<*, *>
                        postNotification(values["category"] as String, values["title"] as String, values["body"] as String, result)
                    }
                    "notificationSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:$packageName"))
                        startActivity(intent)
                        result.success(null)
                    }
                    "securitySettings" -> { startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS)); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                if (call.method == "authenticate") {
                    authResult = null
                    cancellation?.cancel()
                    cancellation = null
                }
                result.error("device_error", e.localizedMessage ?: "Device operation failed.", null)
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (PlaybackEngine.collectionPrivate || Build.VERSION.SDK_INT < 26 || !prefs.getBoolean("autoPip", false) ||
            PlaybackEngine.current()?.isPlaying != true || PlaybackEngine.views == 0) return
        try {
            val bounds = android.graphics.Rect()
            val builder = PictureInPictureParams.Builder().setAspectRatio(android.util.Rational(16, 9))
            if (PlaybackEngine.activeView?.getGlobalVisibleRect(bounds) == true) builder.setSourceRectHint(bounds)
            PlaybackEngine.inPip = true
            playbackChannel?.invokeMethod("pipChanged", true)
            if (!enterPictureInPictureMode(builder.build())) {
                PlaybackEngine.inPip = false
                playbackChannel?.invokeMethod("pipChanged", false)
                PlaybackEngine.pauseUnlessAllowed()
            }
        } catch (_: Exception) {
            PlaybackEngine.inPip = false
            playbackChannel?.invokeMethod("pipChanged", false)
            PlaybackEngine.pauseUnlessAllowed()
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        PlaybackEngine.inPip = PlaybackLifetime.visiblePip(isInPictureInPictureMode, stopped)
        if (!isInPictureInPictureMode && stopped) PlaybackEngine.pauseUnlessAllowed()
        if (!isInPictureInPictureMode && stopped) playbackChannel?.invokeMethod("pipBackgrounded", true)
        playbackChannel?.invokeMethod("pipChanged", PlaybackEngine.inPip)
    }

    override fun onStop() {
        stopped = true
        super.onStop()
        PlaybackEngine.inPip = false // Stopped means the floating session is no longer visible.
        playbackChannel?.invokeMethod("pipBackgrounded", true)
        PlaybackEngine.pauseUnlessAllowed()
        if (AudioEngine.privateCollection) AudioEngine.current()?.pause()
    }
    override fun onStart() {
        super.onStart()
        stopped = false
        PlaybackEngine.inPip = Build.VERSION.SDK_INT >= 26 && isInPictureInPictureMode
        playbackChannel?.invokeMethod("pipBackgrounded", false)
        if (PlaybackEngine.inPip) playbackChannel?.invokeMethod("pipChanged", true)
    }

    private fun secureWindow(enabled: Boolean) {
        AudioEngine.privacy(this)
        if (PlaybackEngine.collectionPrivate || (enabled && prefs.getBoolean("protectScreen", true))) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    private fun notificationsAllowed(): Boolean {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        if (Build.VERSION.SDK_INT >= 24 && !manager.areNotificationsEnabled()) return false
        return true
    }

    private fun freshAuthentication() = authenticatedAt != 0L && android.os.SystemClock.elapsedRealtime() - authenticatedAt <= 15000

    private fun channelAllowed(id: String): Boolean = notificationsAllowed() &&
        (Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(channelId(id))?.importance != NotificationManager.IMPORTANCE_NONE)

    private fun postNotification(id: String, title: String, body: String, result: MethodChannel.Result) {
        DevicePreferencePolicy.category(id)
        if (!prefs.getBoolean("notifications", false) || !prefs.getBoolean("category_$id", true) || !channelAllowed(id)) {
            result.error("permission", "This notification category is disabled in Multiplexr or Android settings.", null)
            return
        }
        val pending = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId(id)) else Notification.Builder(this)
        val privateContent = prefs.getBoolean("hidePreviews", true)
        manager.notify(id.hashCode(), builder.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(if (privateContent) "Multiplexr" else title)
            .setContentText(if (privateContent) "Open Multiplexr to view this update." else body)
            .setVisibility(if (privateContent) Notification.VISIBILITY_SECRET else Notification.VISIBILITY_PRIVATE)
            .setContentIntent(pending).setAutoCancel(true).build())
        result.success(null)
    }

    private fun status(): Map<String, Any> {
        val keyguard = getSystemService(KeyguardManager::class.java)
        val biometric = if (Build.VERSION.SDK_INT >= 30) {
            getSystemService(BiometricManager::class.java).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) == BiometricManager.BIOMETRIC_SUCCESS
        } else if (Build.VERSION.SDK_INT >= 29) {
            getSystemService(BiometricManager::class.java).canAuthenticate() == BiometricManager.BIOMETRIC_SUCCESS
        } else false
        val values = mutableMapOf<String, Any>(
            "supported" to true, "dark" to prefs.getBoolean("dark", true),
            "darkBase" to prefs.getInt("darkBase", 1), "darkAccent" to prefs.getInt("darkAccent", 1),
            "lightBase" to prefs.getInt("lightBase", 0), "lightAccent" to prefs.getInt("lightAccent", 7),
            "lockEnabled" to prefs.getBoolean("lockEnabled", false),
            "notifications" to prefs.getBoolean("notifications", false),
            "notificationAllowed" to notificationsAllowed(), "secureDevice" to keyguard.isDeviceSecure,
            "biometric" to biometric,
            "followSystem" to prefs.getBoolean("followSystem", false),
            "compact" to prefs.getBoolean("compact", false),
            "pixel" to prefs.getBoolean("pixel", true),
            "themeState" to (prefs.getString("themeState", "") ?: ""),
            "hasPalettePreferences" to listOf("darkBase", "darkAccent", "lightBase", "lightAccent").any { prefs.contains(it) },
            "libraryView" to prefs.getInt("libraryView", 0),
            "spacesView" to prefs.getInt("spacesView", 0),
            "reduceMotion" to prefs.getBoolean("reduceMotion", false),
            "lockDelay" to prefs.getInt("lockDelay", 0),
            "useBiometrics" to prefs.getBoolean("useBiometrics", true),
            "hidePreviews" to prefs.getBoolean("hidePreviews", true),
            "protectScreen" to prefs.getBoolean("protectScreen", true)
        )
        for (id in categories.keys) {
            values["category_$id"] = prefs.getBoolean("category_$id", true)
            values["channel_$id"] = channelAllowed(id)
        }
        return values
    }

    private fun authenticate(result: MethodChannel.Result) {
        if (authResult != null) { result.error("busy", "Authentication already open.", null); return }
        val keyguard = getSystemService(KeyguardManager::class.java)
        if (!keyguard.isDeviceSecure) { result.error("no_screen_lock", "Set a device PIN, pattern, or password in Android settings first.", null); return }
        authResult = result
        if (Build.VERSION.SDK_INT >= 30) {
            cancellation = CancellationSignal()
            BiometricPrompt.Builder(this).setTitle("Unlock Multiplexr")
                .setSubtitle(if (prefs.getBoolean("useBiometrics", true)) "Use biometrics or your device screen lock" else "Use your device screen lock")
                .setAllowedAuthenticators(if (prefs.getBoolean("useBiometrics", true))
                    BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL
                    else BiometricManager.Authenticators.DEVICE_CREDENTIAL)
                .build().authenticate(cancellation!!, mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(value: BiometricPrompt.AuthenticationResult) { completeAuth(true) }
                    override fun onAuthenticationError(code: Int, message: CharSequence) { completeAuth(false) }
                })
        } else {
            // Android 9/10 and older: system credential challenge is the safe fallback.
            @Suppress("DEPRECATION")
            val intent = keyguard.createConfirmDeviceCredentialIntent("Unlock Multiplexr", "Confirm your device screen lock")
            if (intent == null) completeAuth(false) else startActivityForResult(intent, 42)
        }
    }

    private fun completeAuth(success: Boolean) {
        authenticatedAt = if (success) android.os.SystemClock.elapsedRealtime() else 0
        val result = authResult
        authResult = null
        cancellation = null
        result?.success(success)
    }

    @Deprecated("Legacy device credential fallback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (plugins?.onResult(requestCode, resultCode, data) == true) return
        if (themeDocuments.onResult(requestCode, resultCode, data)) return
        if (subtitlePicker.onResult(requestCode, resultCode, data)) return
        if (audio?.onResult(requestCode, resultCode, data) == true) return
        if (::library.isInitialized && library.onActivityResult(requestCode, resultCode, data)) return
        if (requestCode == 42) completeAuth(resultCode == RESULT_OK)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 41) {
            permissionResult?.success(notificationsAllowed())
            permissionResult = null
        }
    }

    override fun onDestroy() {
        readingVolumeKeys = false; readingKeys?.setMethodCallHandler(null); readingKeys = null
        plugins?.close(); plugins = null
        themeDocuments.close()
        subtitlePicker.close()
        audio?.close(); audio = null
        if (::library.isInitialized) library.close()
        cancellation?.cancel()
        completeAuth(false)
        permissionResult?.success(false)
        permissionResult = null
        super.onDestroy()
    }
}
