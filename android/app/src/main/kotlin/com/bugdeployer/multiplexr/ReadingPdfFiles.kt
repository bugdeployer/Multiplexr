package com.bugdeployer.multiplexr

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.util.UUID

/** Worker-thread fixed-page source. Pages, descriptors and bitmaps have bounded lifetimes. */
class ReadingPdfFiles(private val directory: File, private val input: (String) -> InputStream) {
    private data class Handle(val file: File, val renderer: PdfRenderer)
    private val handles = mutableMapOf<String, Handle>()
    init { directory.mkdirs(); directory.listFiles()?.filter { it.name.startsWith("publication-") && it.isFile }?.forEach { it.delete() } }

    fun open(title: JSONObject, fingerprint: String, cancelled: () -> Boolean): JSONObject {
        require(handles.isEmpty()) { "Close the current PDF first." }
        require(title.getString("format") == "pdf")
        val (file, digest) = copy(input(title.getJSONObject("source").getString("uri")), directory, cancelled)
        var renderer: PdfRenderer? = null
        try {
            require(digest == fingerprint) { "PDF changed. Scan its folder again." }
            renderer = renderer(file)
            val pages = pages(renderer, cancelled)
            val token = UUID.randomUUID().toString()
            handles[token] = Handle(file, renderer)
            return JSONObject().put("token", token).put("pages", pages)
        } catch (e: Exception) { renderer?.close(); file.delete(); throw e }
    }

    fun info(token: String, id: String): JSONObject = page(token, id) { p ->
        JSONObject().put("left", 0).put("top", 0).put("right", p.width).put("bottom", p.height)
    }

    fun tile(token: String, id: String, left: Int, top: Int, width: Int, height: Int, target: Int): ByteArray = page(token, id) { p ->
        require(left >= 0 && top >= 0 && width > 0 && height > 0 && left.toLong() + width <= p.width && top.toLong() + height <= p.height)
        require(target in 1..4096)
        val scale = minOf(target.toDouble() / width, kotlin.math.sqrt(2_000_000.0 / (width.toDouble() * height)))
        val bitmap = Bitmap.createBitmap(maxOf(1, (width * scale).toInt()), maxOf(1, (height * scale).toInt()), Bitmap.Config.ARGB_8888)
        try {
            bitmap.eraseColor(Color.WHITE)
            val matrix = Matrix().apply { setValues(floatArrayOf(scale.toFloat(), 0f, (-left * scale).toFloat(), 0f, scale.toFloat(), (-top * scale).toFloat(), 0f, 0f, 1f)) }
            p.render(bitmap, null, matrix, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            ByteArrayOutputStream().use { out ->
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, out))
                require(out.size() <= 8 * 1024 * 1024)
                out.toByteArray()
            }
        } finally { bitmap.recycle() }
    }

    private fun <T> page(token: String, id: String, action: (PdfRenderer.Page) -> T): T {
        val handle = handles[token] ?: error("PDF reader is closed.")
        val index = id.removePrefix("page-").toIntOrNull() ?: error("Invalid PDF page.")
        require(id == "page-$index" && index in 0 until handle.renderer.pageCount)
        return handle.renderer.openPage(index).use(action)
    }
    fun close(token: String) { handles.remove(token)?.let { try { it.renderer.close() } finally { it.file.delete() } } }
    fun closeAll() { handles.keys.toList().forEach(::close) }
    fun cacheBytes() = directory.listFiles()?.sumOf { it.length() } ?: 0L
    fun clearIdleCache() { val active = handles.values.map { it.file }; directory.listFiles()?.filter { it !in active }?.forEach { it.delete() } }

    companion object {
        private fun renderer(file: File): PdfRenderer {
            val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            try { return PdfRenderer(descriptor) }
            catch (e: Exception) { descriptor.close(); throw IllegalArgumentException("This PDF is damaged or password protected. Try an external reader.", e) }
        }
        private fun copy(stream: InputStream, directory: File, cancelled: () -> Boolean): Pair<File, String> {
            directory.mkdirs()
            val file = File.createTempFile("publication-", ".pdf", directory)
            try {
                val digest = MessageDigest.getInstance("SHA-256")
                var count = 0L
                stream.use { source -> file.outputStream().use { output ->
                    val buffer = ByteArray(65536)
                    while (true) {
                        ReadingPublication.check(cancelled)
                        val n = source.read(buffer); if (n < 0) break
                        count += n; require(count <= 512L * 1024 * 1024) { "PDF exceeds the 512 MiB reader limit." }
                        output.write(buffer, 0, n); digest.update(buffer, 0, n)
                    }
                } }
                return file to digest.digest().joinToString("") { "%02x".format(it) }
            } catch (e: Exception) { file.delete(); throw e }
        }
        private fun pages(renderer: PdfRenderer, cancelled: () -> Boolean): JSONArray {
            require(renderer.pageCount in 1..10000) { "PDF must contain 1–10000 pages." }
            return JSONArray().also { result ->
                for (i in 0 until renderer.pageCount) {
                    ReadingPublication.check(cancelled)
                    renderer.openPage(i).use { p -> result.put(JSONObject().put("id", "page-$i").put("width", p.width).put("height", p.height)) }
                }
            }
        }
        fun inspect(stream: InputStream, filename: String, directory: File, cancelled: () -> Boolean): ReadingPublication.Result {
            val (file, digest) = copy(stream, directory, cancelled)
            try {
                val opened = try { renderer(file) } catch (_: IllegalArgumentException) {
                    val header = ByteArray(5).also { bytes -> file.inputStream().use { it.read(bytes) } }
                    require(String(header, Charsets.US_ASCII) == "%PDF-") { "Not a PDF publication." }
                    return ReadingPublication.Result(ReadingPublication.metadata(filename.substringBeforeLast('.')),
                        JSONArray().put(JSONObject().put("id", "page-0").put("href", "page-0").put("label", "Open with an external reader")), digest, null, "")
                }
                opened.use { renderer ->
                    val pages = pages(renderer, cancelled)
                    val order = JSONArray()
                    for (i in 0 until pages.length()) order.put(JSONObject().put("id", "page-$i").put("href", "page-$i").put("label", "Page ${i + 1}"))
                    val cover = renderer.openPage(0).use { page ->
                        val scale = minOf(480.0 / page.width, 720.0 / page.height)
                        val bitmap = Bitmap.createBitmap(maxOf(1, (page.width * scale).toInt()), maxOf(1, (page.height * scale).toInt()), Bitmap.Config.ARGB_8888)
                        try {
                            bitmap.eraseColor(Color.WHITE); page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            ByteArrayOutputStream().use { out -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, out); out.toByteArray() }
                        } finally { bitmap.recycle() }
                    }
                    return ReadingPublication.Result(ReadingPublication.metadata(filename.substringBeforeLast('.')), order, digest, cover, "")
                }
            } finally { file.delete() }
        }
    }
}
