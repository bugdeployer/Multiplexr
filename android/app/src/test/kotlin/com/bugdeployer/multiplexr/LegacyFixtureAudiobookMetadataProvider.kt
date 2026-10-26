// Historical provider fixture, excluded from application artifacts.
package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/** Public catalog metadata only; this provider never requests audio or account data. */
object AudiobookMetadataProvider {
    private val regions = mapOf("us" to ".com", "uk" to ".co.uk", "au" to ".com.au", "ca" to ".ca", "de" to ".de", "fr" to ".fr", "in" to ".in", "it" to ".it", "es" to ".es", "jp" to ".co.jp")
    private val images = setOf("m.media-amazon.com", "images-na.ssl-images-amazon.com", "images-eu.ssl-images-amazon.com", "images.amazon.com")
    private var lastRequest = 0L
    @Synchronized fun search(title: String, author: String, region: String, page: Int = 1): JSONArray {
        require(title.trim().isNotEmpty() && title.length <= 300 && author.length <= 300)
        require(page in 1..1000)
        val domain = regions[region] ?: throw IllegalArgumentException("Unsupported catalog region.")
        val wait = 1000 - (System.currentTimeMillis() - lastRequest)
        if (wait > 0) Thread.sleep(wait)
        lastRequest = System.currentTimeMillis()
        fun encode(value: String) = URLEncoder.encode(value, "UTF-8")
        val query = "title=${encode(title.trim())}&num_results=50&page=${page - 1}&products_sort_by=Relevance&response_groups=contributors,product_desc,product_attrs,series,media" + if (author.isBlank()) "" else "&author=${encode(author.trim())}"
        if (Regex("(?:[Bb]0[A-Za-z0-9]{8}|[0-9]{10})").matches(title.trim())) {
            val response = JSONObject(String(get(URL("https://api.audible$domain/1.0/catalog/products/${title.trim().uppercase()}?response_groups=contributors,product_desc,product_attrs,series,media"), 2_000_000), Charsets.UTF_8))
            return JSONArray().put(normalize(response.getJSONObject("product")))
        }
        val response = JSONObject(String(get(URL("https://api.audible$domain/1.0/catalog/products?$query"), 2_000_000), Charsets.UTF_8))
        val products = response.optJSONArray("products") ?: throw IllegalStateException("The catalog returned an unexpected response.")
        return searchResults(products)
    }
    internal fun searchResults(products: JSONArray): JSONArray {
        val output = JSONArray()
        for (i in 0 until minOf(50, products.length())) {
            val product = products.getJSONObject(i)
            if (product.optString("content_type") !in setOf("", "Product", "Audiobook")) continue
            if (product.optString("title").isBlank() || !Regex("[A-Za-z0-9]{10}").matches(product.optString("asin"))) continue
            output.put(normalize(product))
        }
        return output
    }
    fun normalize(product: JSONObject): JSONObject {
        fun text(value: String) = value.replace(Regex("<[^>]*>"), " ").replace("&amp;", "&").replace("&quot;", "\"").replace("&#39;", "'").replace("&nbsp;", " ").replace("&lt;", "<").replace("&gt;", ">").replace(Regex("\\s+"), " ").trim()
        fun names(key: String): String {
            val values = product.optJSONArray(key) ?: return ""
            return (0 until minOf(values.length(), 30)).mapNotNull { values.optJSONObject(it)?.optString("name")?.takeIf(String::isNotBlank) }.joinToString(", ") { text(it) }
        }
        val series = product.optJSONArray("series")?.optJSONObject(0)
        val sequence = Regex("[0-9]+(?:\\.[0-9]+)?").find(series?.optString("sequence") ?: "")?.value?.toDoubleOrNull() ?: 0.0
        val covers = product.optJSONObject("product_images") ?: JSONObject()
        val cover = covers.keys().asSequence().sortedByDescending { it.toIntOrNull() ?: 0 }.map { covers.optString(it) }.firstOrNull { allowedCover(it) } ?: ""
        return JSONObject().put("providerId", product.getString("asin")).put("metadataSource", "audible")
            .put("title", text(product.getString("title"))).put("author", names("authors")).put("narrator", names("narrators"))
            .put("description", text(product.optString("merchandising_summary"))).put("language", product.optString("language"))
            .put("publisher", text(product.optString("publisher_name"))).put("publicationDate", product.optString("release_date"))
            .put("series", text(series?.optString("title") ?: "")).put("seriesId", series?.optString("asin")?.takeIf(String::isNotBlank)?.let { "audible:$it" } ?: "")
            .put("seriesOrder", sequence).put("coverUrl", cover).put("runtimeMinutes", product.optInt("runtime_length_min"))
    }
    fun allowedCover(value: String): Boolean = try {
        val url = URL(value)
        url.protocol == "https" && url.host.lowercase() in images && url.userInfo == null && url.port == -1
    } catch (_: Exception) { false }
    fun cover(value: String): String {
        require(allowedCover(value)) { "Unsupported cover image host." }
        return AudioArtwork.encode(get(URL(value), 20_000_000, true))
    }
    private fun get(url: URL, limit: Int, image: Boolean = false): ByteArray {
        val connection = url.openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15000; connection.readTimeout = 15000
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("User-Agent", "Multiplexr (+https://github.com/bugdeployer/Multiplexr)")
            connection.setRequestProperty("Accept", if (image) "image/*" else "application/json")
            val status = connection.responseCode
            if (status !in 200..299) throw MetadataHttpException(status)
            return connection.inputStream.use { it.readBytesBounded(limit) }
        } finally { connection.disconnect() }
    }
}
