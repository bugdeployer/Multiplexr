// Historical provider fixture, excluded from application artifacts.
package com.bugdeployer.multiplexr

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MetadataHttpException(val status: Int) : Exception("Metadata provider HTTP $status")

/** Token never crosses the Flutter bridge after entry and is encrypted at rest. */
class MetadataProvider(context: Context) {
    private val prefs = context.getSharedPreferences("metadata_provider", Context.MODE_PRIVATE)
    private val seriesCache = mutableMapOf<Int, Pair<Long, JSONObject>>()
    private val alias = "multiplexr_tmdb"
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun configured() = prefs.contains("ciphertext")
    private fun token(): String {
        val data = prefs.getString("ciphertext", null) ?: error("Add your TMDB API key or read token in Settings → Metadata.")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(prefs.getString("iv", ""), Base64.NO_WRAP)))
        return String(cipher.doFinal(Base64.decode(data, Base64.NO_WRAP)), Charsets.UTF_8)
    }
    fun save(value: String) {
        val text = value.trim()
        if (text.isEmpty()) { check(prefs.edit().clear().commit()); return }
        require(!text.contains('\n') && !text.contains('\r')) { "Enter a valid API key or read token." }
        request("configuration", text) // Validate before replacing a working token.
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        check(prefs.edit().putString("ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP)).commit())
    }
    fun search(type: String, query: String, page: Int = 1): JSONObject {
        require(type in listOf("movie", "tv"))
        require(page in 1..500)
        require(query.trim().isNotEmpty() && query.length <= 200)
        return request("search/$type?include_adult=false&page=$page&query=${java.net.URLEncoder.encode(query, "UTF-8")}", token())
    }
    fun details(type: String, id: Int, season: Int?, episode: Int?): JSONObject {
        require(type in listOf("movie", "tv") && id > 0)
        val path = if (type == "tv" && season != null && episode != null) {
            require(season >= 0 && episode > 0)
            "tv/$id/season/$season/episode/$episode"
        } else "$type/$id?append_to_response=credits"
        val result = request(path, token())
        if (type == "tv" && season != null && episode != null) {
            val cached = seriesCache[id]
            val show = if (cached != null && System.currentTimeMillis() - cached.first < 3600000) cached.second
                else request("tv/$id?append_to_response=credits", token()).also { seriesCache[id] = System.currentTimeMillis() to it }
            result.put("series", show)
        }
        return result
    }
    fun images(type: String, id: Int, kind: String): List<String> {
        require(type in listOf("movie", "tv") && id > 0 && kind in listOf("posters", "backdrops"))
        val images = request("$type/$id/images", token()).optJSONArray(kind) ?: return emptyList()
        return (0 until images.length()).take(40).map { "https://image.tmdb.org/t/p/${if (kind == "posters") "w342" else "w1280"}${images.getJSONObject(it).getString("file_path")}" }
    }
    private fun request(path: String, bearer: String): JSONObject {
        val apiKey = bearer.matches(Regex("[0-9a-fA-F]+"))
        val suffix = if (apiKey) {
            (if ('?' in path) "&" else "?") + "api_key=" + java.net.URLEncoder.encode(bearer, "UTF-8")
        } else ""
        val connection = URL("https://api.themoviedb.org/3/$path$suffix").openConnection() as HttpURLConnection
        connection.connectTimeout = 15000; connection.readTimeout = 15000
        connection.instanceFollowRedirects = false
        if (!apiKey) connection.setRequestProperty("Authorization", "Bearer $bearer")
        connection.setRequestProperty("Accept", "application/json")
        try {
            when (connection.responseCode) {
                200 -> return connection.inputStream.bufferedReader().use { JSONObject(it.readText()) }
                401, 403 -> throw MetadataHttpException(connection.responseCode)
                429 -> throw MetadataHttpException(429)
                else -> throw MetadataHttpException(connection.responseCode)
            }
        } finally { connection.disconnect() }
    }
}
