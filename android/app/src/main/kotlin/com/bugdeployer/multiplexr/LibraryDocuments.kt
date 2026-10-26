package com.bugdeployer.multiplexr

import android.app.Activity
import android.content.Intent
import android.os.Handler
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService

/** SAF export/import: no broad storage permission and bounded import size. */
class LibraryDocuments(private val activity: Activity, private val executor: ExecutorService, private val main: Handler, private val snapshot: () -> String) {
    private var pending: MethodChannel.Result? = null
    private var exporting = false
    fun export(result: MethodChannel.Result) = launch(result, true)
    fun read(result: MethodChannel.Result) = launch(result, false)
    private fun launch(result: MethodChannel.Result, export: Boolean) {
        if (pending != null) { result.error("busy", "A backup picker is already open.", null); return }
        pending = result; exporting = export
        try {
            val intent = Intent(if (export) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(if (export) "application/json" else "*/*")
            if (export) intent.putExtra(Intent.EXTRA_TITLE, "multiplexr-library-${System.currentTimeMillis()}.json")
            activity.startActivityForResult(intent, DocumentRequest.BACKUP.code)
        } catch (_: Exception) { pending = null; result.error("backup", "Cannot open the backup file picker.", null) }
    }
    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != DocumentRequest.BACKUP.code) return false
        val result = pending ?: return true
        pending = null
        val export = exporting
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(if (export) false else null); return true }
        executor.execute {
            try {
                if (export) {
                    val text = snapshot()
                    activity.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(text.toByteArray(Charsets.UTF_8)) }
                    main.post { result.success(true) }
                } else {
                    val bytes = activity.contentResolver.openInputStream(uri)!!.use { input ->
                        val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
                        while (true) { val count = input.read(buffer); if (count < 0) break; require(output.size() + count <= 64 * 1024 * 1024) { "Backup exceeds 64 MB." }; output.write(buffer, 0, count) }; output.toByteArray()
                    }
                    val validated = BackupCodec.validate(org.json.JSONObject(String(bytes, Charsets.UTF_8)))
                    val grants = activity.contentResolver.persistedUriPermissions.filter { it.isReadPermission }.map { it.uri.toString() }.toSet()
                    val collections = validated.getJSONArray("collections")
                    for (i in 0 until collections.length()) collections.put(i, RestoreReconciliation.collection(collections.getJSONObject(i), grants))
                    val text = validated.toString()
                    main.post { result.success(text) }
                }
            } catch (error: Exception) { main.post { result.error("backup", if (export) "Could not save the backup: ${error.message ?: error.javaClass.simpleName}" else "Cannot read this backup. Check its format, version and size.", null) } }
        }
        return true
    }
}
