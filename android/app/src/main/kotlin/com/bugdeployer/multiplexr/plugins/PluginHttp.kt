package com.bugdeployer.multiplexr.plugins

import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.InetAddress
import java.net.URI
import java.util.concurrent.TimeUnit

internal object PluginNetworkPolicy {
    fun packageOrigins(value: String): Set<String> {
        val origin = URI(value).let { "https://${it.host}" }
        url(value, setOf(origin))
        return if (origin == "https://github.com") setOf(origin, "https://release-assets.githubusercontent.com") else setOf(origin)
    }
    fun publicAddress(address: InetAddress): Boolean {
        if(address.isAnyLocalAddress || address.isLoopbackAddress || address.isLinkLocalAddress || address.isSiteLocalAddress || address.isMulticastAddress) return false
        val b = address.address.map { it.toInt() and 255 }
        if(b.size == 4) return b[0] !in setOf(0, 10, 127) && b[0] < 224 &&
            !(b[0] == 100 && b[1] in 64..127) && !(b[0] == 169 && b[1] == 254) &&
            !(b[0] == 172 && b[1] in 16..31) && !(b[0] == 192 && (b[1] == 168 || b[1] == 0 || b[1] == 2)) &&
            !(b[0] == 198 && b[1] in setOf(18,19,51)) && !(b[0] == 203 && b[1] == 0 && b[2] == 113)
        // Only global unicast IPv6; exclude documentation and transition ranges.
        return b.size == 16 && b[0] in 0x20..0x3f && !(b[0] == 0x20 && b[1] == 0x01 && (b[2] < 2 || b[2] == 0x0d && b[3] == 0xb8)) && !(b[0] == 0x20 && b[1] == 0x02)
    }
    fun url(value: String, origins: Set<String>): HttpUrl {
        require(value.length <= 4096)
        val url = value.toHttpUrlOrNullSafe()
        require(url.scheme == "https" && url.port == 443 && url.username.isEmpty() && url.password.isEmpty() && url.fragment == null && "https://${url.host}" in origins) { "Network destination denied" }
        return url
    }
    private fun String.toHttpUrlOrNullSafe(): HttpUrl = HttpUrl.Builder().apply {
        val u = URI(this@toHttpUrlOrNullSafe); require(u.scheme == "https" && u.host != null && u.userInfo == null && u.fragment == null && (u.port == -1 || u.port == 443))
        scheme("https"); host(u.host); port(443); encodedPath(u.rawPath.takeUnless { it.isNullOrEmpty() } ?: "/"); encodedQuery(u.rawQuery)
    }.build()
}
internal class PluginHttp(private val client: OkHttpClient = secureClient()) {
    companion object { private fun secureClient() = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        .proxy(java.net.Proxy.NO_PROXY).connectionPool(ConnectionPool(0, 1, TimeUnit.SECONDS))
        .dns(object: Dns { override fun lookup(hostname: String): List<InetAddress> = InetAddress.getAllByName(hostname).toList().also { values -> require(values.isNotEmpty() && values.all(PluginNetworkPolicy::publicAddress)) { "Private network denied" } } })
        .connectTimeout(5, TimeUnit.SECONDS).readTimeout(5, TimeUnit.SECONDS).callTimeout(10, TimeUnit.SECONDS).build() }
    fun get(url: String, origins: Set<String>, header: Pair<String,String>? = null, maximum: Int = 65536, binary: Boolean = false, register: (Call) -> Unit, unregister: (Call) -> Unit = {}, check: () -> Unit, payload: String? = null): Map<String, Any> {
        require(payload == null || payload.toByteArray(Charsets.UTF_8).size <= 8192)
        var destination = PluginNetworkPolicy.url(url, origins)
        val initial = destination.host
        repeat(4) {
            check()
            val builder = Request.Builder().url(destination).get().header("Accept-Encoding", "identity")
                .header("User-Agent", "Multiplexr/${com.bugdeployer.multiplexr.BuildConfig.VERSION_NAME} (+https://github.com/bugdeployer/Multiplexr)")
            if (payload != null) builder.post(payload.toRequestBody("application/json; charset=utf-8".toMediaType()))
            if(header != null) { require(destination.host == initial); builder.header(header.first, header.second) }
            val call = client.newCall(builder.build()); register(call)
            try { call.execute().use { response ->
                check()
                if(response.code in setOf(301,302,303,307,308)) {
                    require(payload == null) { "POST redirects denied" }
                    val next = destination.resolve(response.header("Location") ?: error("Missing redirect")) ?: error("Invalid redirect")
                    destination = PluginNetworkPolicy.url(next.toString(), origins)
                    require(header == null || destination.host == initial) { "Credential redirect denied" }
                } else {
                    val body = response.body ?: error("Empty response")
                    require(body.contentLength() <= maximum)
                    val bytes = body.byteStream().use { input -> val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192); while(true) { val n = input.read(buffer); if(n < 0) break; require(output.size() + n <= maximum); output.write(buffer,0,n) }; output.toByteArray() }; require(bytes.size <= maximum) { "Response limit exceeded" }
                    check(); if(binary) return mapOf("status" to response.code,"body" to PluginEncoding.encode(bytes))
                    val text = Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString()
                    // Never expose response headers, Set-Cookie or credential reflections.
                    val redacted = header?.second?.let { text.replace(it, "[redacted]").replace(it.removePrefix("Bearer "), "[redacted]") } ?: text
                    return mapOf("status" to response.code, "body" to redacted)
                }
            } } finally { unregister(call) }
        }
        error("Redirect limit exceeded")
    }
}
