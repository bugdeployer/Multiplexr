package com.bugdeployer.multiplexr.plugins

/** Loaded only by the isolated process, never by Flutter or LibraryHost. */
internal object QuickJs {
    init { System.loadLibrary("multiplexr_sandbox") }
    @Volatile var gateway: ((String) -> String)? = null
    fun hostCall(request: ByteArray): ByteArray? = gateway?.invoke(String(request, Charsets.UTF_8))?.toByteArray(Charsets.UTF_8)
    external fun execute(source: ByteArray, input: ByteArray, id: Long): ByteArray
    external fun cancel(id: Long)
}
