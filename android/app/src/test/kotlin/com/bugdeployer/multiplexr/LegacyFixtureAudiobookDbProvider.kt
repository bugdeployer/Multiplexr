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

class AudiobookDbProvider(context: Context) {
    private val prefs = context.getSharedPreferences("audiobookdb_provider", Context.MODE_PRIVATE)
    private val alias = "multiplexr_audiobookdb"
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
        val data = prefs.getString("ciphertext", null) ?: error("Add your AudiobookDB API key in Settings â†’ Metadata.")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(prefs.getString("iv", ""), Base64.NO_WRAP)))
        return String(cipher.doFinal(Base64.decode(data, Base64.NO_WRAP)), Charsets.UTF_8)
    }
    fun save(value: String) {
        val text = value.trim()
        if (text.isEmpty()) { check(prefs.edit().clear().commit()); return }
        require(!text.contains('\n') && !text.contains('\r')) { "Enter a valid API key or read token." }
        request("auth/apikey", text) // Validate before replacing a working token.
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        check(prefs.edit().putString("ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP)).commit())
    }

    private fun request(path: String, credential: String = token(), body: JSONObject? = null): String {
        val c = URL("https://audiobookdb.org/api/$path").openConnection() as HttpURLConnection
        c.connectTimeout = 15000; c.readTimeout = 15000; c.instanceFollowRedirects = false
        c.setRequestProperty("X-API-Key", credential)
        c.setRequestProperty("User-Agent", "Multiplexr/0.5.0 (https://github.com/bugdeployer/Multiplexr)")
        c.setRequestProperty("Accept", "application/json")
        try {
            if (body != null) { c.requestMethod = "POST"; c.doOutput = true; c.setRequestProperty("Content-Type", "application/json"); c.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) } }
            if (c.responseCode == 429) throw MetadataHttpException(429)
            if (c.responseCode !in 200..299) throw MetadataHttpException(c.responseCode)
            return c.inputStream.use { String(it.readBytesBounded(2_000_000), Charsets.UTF_8) }
        } finally { c.disconnect() }
    }
    fun cover(value: String): String {
        if (AudiobookMetadataProvider.allowedCover(value)) return AudiobookMetadataProvider.cover(value)
        val url = URL(value)
        require(url.protocol == "https" && url.userInfo == null && url.port == -1 && (url.host == "audiobookdb.org" || url.host.endsWith(".audiobookdb.org"))) { "Unsupported AudiobookDB artwork host. Apply text metadata or choose artwork manually." }
        val c = url.openConnection() as HttpURLConnection
        c.connectTimeout = 15000; c.readTimeout = 15000; c.instanceFollowRedirects = false
        try { if (c.responseCode !in 200..299) throw MetadataHttpException(c.responseCode); return AudioArtwork.encode(c.inputStream.use { it.readBytesBounded(20_000_000) }) } finally { c.disconnect() }
    }
    fun search(title: String, author: String, page: Int = 1): org.json.JSONArray {
        require(page in 1..1000)
        require(title.trim().isNotEmpty() && title.length <= 300 && author.length <= 300)
        if (Regex("(?:[Bb]0[A-Za-z0-9]{8}|[0-9]{10})").matches(title.trim())) {
            val book = JSONObject(request("audiobooks/external/audible/" + title.trim().uppercase()))
            val releaseId = book.optString("matchedReleaseId")
            val release = if (releaseId.isNotEmpty()) {
                require(Regex("[A-Za-z0-9_-]{1,64}").matches(releaseId))
                JSONObject(request("releases/$releaseId"))
            } else null
            return org.json.JSONArray().put(normalize(book, release))
        }
        require((title + " " + author).trim().length >= 3) { "Enter at least three search characters or an Audible ASIN." }
        val hits = org.json.JSONArray(request("search", body = JSONObject().put("q", (title + " " + author).trim()).put("type", "books")))
        val result = org.json.JSONArray()
        for (i in ((page - 1) * 5) until minOf(hits.length(), page * 5)) {
            val id = hits.getJSONObject(i).getString("id"); require(Regex("[A-Za-z0-9_-]{1,64}").matches(id))
            val book = JSONObject(request("books/$id"))
            val releases = book.optJSONArray("releases") ?: org.json.JSONArray()
            if (releases.length() == 0) result.put(normalize(book, null))
            else for (j in 0 until minOf(releases.length(), 5)) result.put(normalize(book, releases.getJSONObject(j)))
        }
        return result
    }
    companion object {
        fun normalize(book: JSONObject, release: JSONObject?): JSONObject {
            fun text(v: JSONObject, k: String) = if (v.isNull(k)) "" else v.optString(k)
            fun names(v: JSONObject, role: String): String {
                val people = v.optJSONArray("people") ?: org.json.JSONArray()
                return (0 until people.length()).map { people.getJSONObject(it) }.filter { it.optJSONObject("role")?.optString("name").equals(role, true) }.mapNotNull { it.optJSONObject("person")?.optString("name")?.takeIf(String::isNotBlank) }.distinct().joinToString(", ")
            }
            val recording = release ?: JSONObject()
            val image = recording.optJSONArray("images")?.optJSONObject(0) ?: book.optJSONObject("coverImage")
            val cover = image?.optString("url")?.takeIf { it.startsWith("https://") }?.trimEnd('/')?.plus("/large.jpg") ?: ""
            return JSONObject().put("metadataSource", "audiobookdb").put("providerId", "audiobookdb:" + book.getString("id") + ":" + recording.optString("id"))
                .put("title", book.getString("title")).put("author", names(book, "Author")).put("narrator", names(recording, "Narrator"))
                .put("description", text(book, "description")).put("language", recording.optJSONObject("language")?.optString("name") ?: "")
                .put("publisher", recording.optJSONObject("publisher")?.optString("name") ?: "").put("publicationDate", text(recording, "releaseDate"))
                .put("edition", listOf(text(recording, "title"), text(recording, "disambiguation"), text(recording, "duration")).filter(String::isNotBlank).joinToString(" Â· "))
                .put("coverUrl", cover)
        }
    }
}
