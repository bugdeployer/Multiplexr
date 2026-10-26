package com.bugdeployer.multiplexr

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Theme documents are bounded data, independent from library backups. */
class ThemeDocuments(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var output: String? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    fun close() {
        pending?.error("theme", "Theme picker closed. Please try again.", null)
        pending = null; output = null; worker.shutdown()
    }
    fun open(result: MethodChannel.Result) = launch(null, result)
    fun save(text: String, result: MethodChannel.Result) = launch(text, result)
    private fun launch(text: String?, result: MethodChannel.Result) {
        if (pending != null) { result.error("busy", "A theme picker is already open.", null); return }
        if (text != null) try { ThemeDocumentPolicy.validate(text) }
        catch (_: Exception) { result.error("theme", "Invalid theme document or package size.", null); return }
        pending = result; output = text
        try {
            val intent = Intent(if (text == null) Intent.ACTION_OPEN_DOCUMENT else Intent.ACTION_CREATE_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE).setType(if (text != null) "application/json" else "*/*")
            if (text != null) intent.putExtra(Intent.EXTRA_TITLE, "multiplexr-theme.json")
            activity.startActivityForResult(intent, DocumentRequest.THEME.code)
        } catch (_: Exception) { pending = null; output = null; result.error("theme", "Cannot open the theme file picker.", null) }
    }
    fun onResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != DocumentRequest.THEME.code) return false
        val result = pending ?: return true
        val text = output
        pending = null; output = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(if (text == null) null else false); return true }
        worker.execute {
            try {
                if (text != null) {
                    activity.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(text.toByteArray(Charsets.UTF_8)) }
                    main.post { result.success(true) }
                } else {
                    val bytes = activity.contentResolver.openInputStream(uri)!!.use { input ->
                        val buffer = java.io.ByteArrayOutputStream()
                        val chunk = ByteArray(4096)
                        while (true) {
                            val n = input.read(chunk); if (n < 0) break
                            require(buffer.size() + n <= ThemeDocumentPolicy.MAX_PACKAGE) { "Theme exceeds 4 MB." }
                            buffer.write(chunk, 0, n)
                        }
                        buffer.toByteArray()
                    }
                    val imported = String(bytes, Charsets.UTF_8)
                    ThemeDocumentPolicy.validate(imported)
                    main.post { result.success(imported) }
                }
            } catch (_: Exception) { main.post { result.error("theme", "Cannot read or save this theme file. V1 limit: 16 KB; V2 package limit: 4 MB.", null) } }
        }
        return true
    }
}
