package com.bugdeployer.multiplexr

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import java.io.ByteArrayOutputStream

fun java.io.InputStream.readBytesBounded(limit: Int): ByteArray {
    val output = ByteArrayOutputStream()
    val buffer = ByteArray(8192)
    while (true) {
        val count = read(buffer)
        if (count < 0) break
        require(output.size() <= limit - count) { "File is too large." }
        output.write(buffer, 0, count)
    }
    return output.toByteArray()
}

/** Small portable thumbnails keep curated covers usable after backup restore. */
object AudioArtwork {
    fun encode(bytes: ByteArray): String {
        require(bytes.size <= 20_000_000) { "Cover image is too large." }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Invalid cover image." }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 1024) sample *= 2
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: throw IllegalArgumentException("Could not decode cover image.")
        try {
            val ratio = minOf(1.0, 512.0 / maxOf(bitmap.width, bitmap.height))
            val scaled = Bitmap.createScaledBitmap(bitmap, maxOf(1, (bitmap.width * ratio).toInt()), maxOf(1, (bitmap.height * ratio).toInt()), true)
            try {
                val output = ByteArrayOutputStream()
                require(scaled.compress(Bitmap.CompressFormat.JPEG, 78, output))
                return "data:image/jpeg;base64," + Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
            } finally { if (scaled !== bitmap) scaled.recycle() }
        } finally { bitmap.recycle() }
    }
}
