package com.bugdeployer.multiplexr

import android.content.Context
import android.graphics.BitmapFactory
import android.util.Base64
import java.io.File
import org.json.JSONObject

/** Portrait proportions are preserved. Only bounded thumbnails enter durable artwork. */
object ReadingArtworkFiles {
    fun store(context: Context, bytes: ByteArray): String {
        require(bytes.size <= 8 * 1024 * 1024)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth in 1..40000 && bounds.outHeight in 1..40000 && bounds.outWidth.toLong() * bounds.outHeight <= 100000000)
        val encoded = AudioArtwork.encode(bytes)
        return storeData(context, encoded)
    }
    private fun storeData(context: Context, encoded: String): String {
        require(encoded.startsWith("data:image/jpeg;base64,") && encoded.length <= 2000000)
        val bytes = Base64.decode(encoded.substringAfter(','), Base64.DEFAULT)
        val hash = ReadingPublication.hash(bytes)
        val folder = File(context.filesDir, "reading-artwork").apply { mkdirs() }
        val target = File(folder, "$hash.jpg")
        if (!target.exists()) {
            require(folder.listFiles().orEmpty().filter { it.extension == "jpg" }.sumOf { it.length() } + bytes.size <= 256L * 1024 * 1024) {
                "Reading artwork storage limit reached; existing covers were retained."
            }
            val tmp = File.createTempFile("cover-", ".tmp", folder)
            try { tmp.writeBytes(bytes); check(tmp.renameTo(target) || target.exists()) } finally { tmp.delete() }
        }
        return "reading-cover:$hash"
    }
    fun read(context: Context, reference: String): ByteArray {
        ReadingManagementCodec.cover(reference)
        if (reference.startsWith("data:image/jpeg;base64,")) return Base64.decode(reference.substringAfter(','), Base64.DEFAULT)
        require(Regex("reading-cover:[a-f0-9]{64}").matches(reference))
        val file = File(context.filesDir, "reading-artwork/${reference.removePrefix("reading-cover:")}.jpg")
        require(file.isFile && file.length() <= 2000000) { "Reading artwork is missing." }; return file.readBytes()
    }
    fun transformManagement(context: Context, input: JSONObject, portable: Boolean): JSONObject {
        val next = JSONObject(input.toString()); val entities = next.getJSONArray("entities")
        for (i in 0 until entities.length()) {
            val entity = entities.getJSONObject(i); val cover = entity.getString("cover")
            if (portable && cover.startsWith("reading-cover:")) entity.put("cover", "data:image/jpeg;base64," + Base64.encodeToString(read(context, cover), Base64.NO_WRAP))
            else if (!portable && cover.startsWith("data:")) entity.put("cover", store(context, Base64.decode(cover.substringAfter(','), Base64.DEFAULT)))
        }
        return next
    }
    fun transform(context: Context, input: JSONObject, portable: Boolean): JSONObject {
        val next = JSONObject(input.toString()); val rows = next.getJSONArray("entries")
        for (i in 0 until rows.length()) {
            val row = rows.getJSONObject(i); val cover = row.getString("cover")
            if (portable && cover.startsWith("reading-cover:")) {
                val hash = cover.removePrefix("reading-cover:"); require(Regex("[a-f0-9]{64}").matches(hash))
                val file = File(context.filesDir, "reading-artwork/$hash.jpg")
                require(file.isFile && file.length() <= 2000000) { "A reading cover is missing. Restore or rescan it before export." }
                row.put("cover", "data:image/jpeg;base64," + Base64.encodeToString(file.readBytes(), Base64.NO_WRAP))
            } else if (!portable && cover.startsWith("data:")) {
                val bytes = Base64.decode(cover.substringAfter(','), Base64.DEFAULT)
                row.put("cover", store(context, bytes))
            }
        }
        return next
    }
}
