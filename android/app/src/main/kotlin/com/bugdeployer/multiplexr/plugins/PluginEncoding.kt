package com.bugdeployer.multiplexr.plugins

import okio.ByteString.Companion.decodeBase64
import okio.ByteString.Companion.toByteString

/** Standard base64 without API-26 java.util.Base64 dependencies. */
internal object PluginEncoding {
    fun decode(text: String): ByteArray {
        require(text.matches(Regex("[A-Za-z0-9+/]*={0,2}"))) { "Invalid base64" }
        return requireNotNull(text.decodeBase64()) { "Invalid base64" }.toByteArray()
    }
    fun encode(bytes: ByteArray): String = bytes.toByteString().base64()
}
