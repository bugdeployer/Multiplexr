// Historical provider fixture, excluded from application artifacts.
package com.bugdeployer.multiplexr
import java.net.HttpURLConnection
import java.net.URL

object MusicArtwork {
    fun download(value: String): String {
        var url = URL(value)
        repeat(6) {
            require(url.protocol == "https" && (url.host == "coverartarchive.org" || url.host == "archive.org" || url.host.endsWith(".archive.org")))
            val connection = url.openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false; connection.connectTimeout = 20000; connection.readTimeout = 20000
            connection.setRequestProperty("User-Agent", "Multiplexr/0.5.0 (https://bugdeployer.github.io)")
            try {
                if (connection.responseCode in listOf(301, 302, 303, 307, 308)) {
                    url = URL(url, connection.getHeaderField("Location")); return@repeat
                }
                require(connection.responseCode == 200) { "This cover is unavailable. Choose another image." }
                return connection.inputStream.use { AudioArtwork.encode(it.readBytesBounded(20_000_000)) }
            } finally { connection.disconnect() }
        }
        error("Too many artwork redirects.")
    }
}
