package com.bugdeployer.multiplexr

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import android.os.Handler
import android.os.Looper
import java.io.File
import java.util.concurrent.Executors
import io.flutter.plugin.common.MethodChannel

/** Copies a user-selected subtitle into private storage; no broad file permission. */
class SubtitlePicker(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    fun pick(result: MethodChannel.Result) {
        if (pending != null) { result.error("busy", "A subtitle picker is already open.", null); return }
        pending = result
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
            }, DocumentRequest.SUBTITLE.code)
        } catch (_: Exception) { pending = null; result.error("subtitle", "Could not open the subtitle picker.", null) }
    }
    fun onResult(code: Int, status: Int, data: Intent?): Boolean {
        if (code != DocumentRequest.SUBTITLE.code) return false
        val result = pending ?: return true
        val uri = data?.data
        if (status != Activity.RESULT_OK || uri == null) { pending = null; result.success(null); return true }
        io.execute {
            var output: File? = null
            try {
                val name = activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0) else ""
                } ?: ""
                val mime = SubtitleFiles.mime(name)
                val folder = File(activity.filesDir, "subtitles").apply { mkdirs() }
                output = File.createTempFile("caption-", ".${name.substringAfterLast('.')}", folder)
                activity.contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input)
                    output.outputStream().use { target ->
                        val buffer = ByteArray(8192); var total = 0
                        while (true) {
                            val count = input.read(buffer); if (count < 0) break
                            total += count
                            require(total <= 5 * 1024 * 1024) { "Subtitle files must be smaller than 5 MB." }
                            target.write(buffer, 0, count)
                        }
                        require(total > 0) { "This subtitle file is empty." }
                    }
                }
                val path = output.toURI().toString()
                Handler(Looper.getMainLooper()).post {
                    if (pending !== result) { output.delete(); return@post }
                    pending = null
                    result.success(mapOf("uri" to path, "name" to name, "mime" to mime))
                }
            } catch (error: Exception) {
                output?.delete()
                Handler(Looper.getMainLooper()).post {
                    if (pending !== result) return@post
                    pending = null
                    result.error("subtitle", error.message ?: "Could not read this subtitle file.", null)
                }
            }
        }
        return true
    }
    fun close() { pending?.success(null); pending = null; io.shutdown() }
}

object SubtitleFiles {
    fun mime(name: String): String = when (name.substringAfterLast('.', "").lowercase()) {
        "srt" -> "application/x-subrip"
        "vtt" -> "text/vtt"
        "ass", "ssa" -> "text/x-ssa"
        else -> throw IllegalArgumentException("Choose an SRT, VTT, ASS or SSA subtitle file.")
    }
}
