package com.bugdeployer.multiplexr

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Durable content-addressed covers. Backups embed only referenced images. */
object MusicArtworkFiles {
    fun store(context: Context, image: String): String {
        if (!image.startsWith("data:image/")) return image
        require(image.length <= 2_000_000) { "Cover is too large." }
        val bytes = Base64.decode(image.substringAfter(','), Base64.DEFAULT)
        val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        val folder = File(context.filesDir, "music-artwork").apply { mkdirs() }
        val target = File(folder, "$hash.jpg")
        if (!target.exists()) {
            val temporary = File.createTempFile("cover-", ".tmp", folder)
            try { temporary.writeBytes(bytes); check(temporary.renameTo(target) || target.exists()) }
            finally { temporary.delete() }
        }
        return target.absolutePath
    }
    fun transform(context: Context, input: JSONObject, portable: Boolean = false): JSONObject {
        val folder = File(context.filesDir, "music-artwork").canonicalFile
        fun value(raw: Any, field: String = ""): Any = when(raw) {
            is JSONObject -> JSONObject().apply { for(key in raw.keys()) put(key, value(raw.get(key), if(field=="artwork") "cover" else key)) }
            is JSONArray -> JSONArray().apply { for(i in 0 until raw.length()) put(value(raw.get(i),field)) }
            is String -> if(field!="cover") raw else if(portable) {
                if(raw.startsWith(folder.absolutePath + "/")) {
                    val file=File(raw).canonicalFile
                    require(file.parentFile == folder)
                    if(file.isFile) "data:image/jpeg;base64," + Base64.encodeToString(file.readBytesBounded(),Base64.NO_WRAP) else ""
                } else raw
            } else store(context,raw)
            else -> raw
        }
        return value(input) as JSONObject
    }
    private fun File.readBytesBounded(): ByteArray { require(length() <= 2_000_000);return readBytes() }
}
