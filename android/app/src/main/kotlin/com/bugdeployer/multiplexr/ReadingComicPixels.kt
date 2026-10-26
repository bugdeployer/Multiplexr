package com.bugdeployer.multiplexr

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import java.io.ByteArrayOutputStream
import org.json.JSONObject

/** Region decoding has no whole-resolution fallback. Each bitmap is bounded and recycled. */
object ReadingComicPixels {
    @Suppress("DEPRECATION")
    fun tile(files: ReadingComicFiles, token: String, id: String, left: Int, top: Int, width: Int, height: Int, target: Int): ByteArray {
        val page = files.page(token, id)
        require(left >= 0 && top >= 0 && width > 0 && height > 0 && left.toLong() + width <= page.width && top.toLong() + height <= page.height)
        val sample = ComicDecodePolicy.sample(width, height, target)
        val decoder = BitmapRegionDecoder.newInstance(files.file(token, id).path, false) ?: error("Image region decoding is unavailable.")
        try {
            val bitmap = decoder.decodeRegion(Rect(left, top, left + width, top + height), BitmapFactory.Options().apply { inSampleSize = sample; inPreferredConfig = Bitmap.Config.ARGB_8888 }) ?: error("Cannot decode comic page.")
            try {
                require(bitmap.width.toLong() * bitmap.height <= ComicDecodePolicy.MAX_PIXELS)
                val output = ByteArrayOutputStream(); check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
                require(output.size() <= 3 * 1024 * 1024); return output.toByteArray()
            } finally { bitmap.recycle() }
        } finally { decoder.recycle() }
    }
    @Suppress("DEPRECATION")
    fun info(files: ReadingComicFiles, token: String, id: String, crop: Boolean): JSONObject {
        val page = files.page(token, id); var bounds = intArrayOf(0, 0, page.width, page.height)
        if (crop) {
            val decoder = BitmapRegionDecoder.newInstance(files.file(token, id).path, false) ?: error("Image region decoding is unavailable.")
            try {
                var sample = 1; while (maxOf(page.width, page.height) / sample > 256) sample *= 2
                val bitmap = decoder.decodeRegion(Rect(0, 0, page.width, page.height), BitmapFactory.Options().apply { inSampleSize = sample }) ?: error("Cannot inspect comic borders.")
                try {
                    val pixels = IntArray(bitmap.width * bitmap.height); bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
                    val r = ComicDecodePolicy.crop(bitmap.width, bitmap.height, pixels)
                    bounds = intArrayOf(r[0] * page.width / bitmap.width, r[1] * page.height / bitmap.height,
                        r[2] * page.width / bitmap.width, r[3] * page.height / bitmap.height)
                } finally { bitmap.recycle() }
            } finally { decoder.recycle() }
        }
        return JSONObject().put("left", bounds[0]).put("top", bounds[1]).put("right", bounds[2]).put("bottom", bounds[3])
    }
}
