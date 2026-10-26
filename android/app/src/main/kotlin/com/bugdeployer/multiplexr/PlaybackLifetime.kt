package com.bugdeployer.multiplexr

/** Ownership decisions shared by task removal, view disposal and reattachment. */
object PlaybackLifetime {
    fun visiblePip(inPipMode: Boolean, stopped: Boolean): Boolean = inPipMode && !stopped

    // App authentication protects browsing, not an already authorized public
    // background/PiP session. Private collection playback remains restricted.
    fun pauseOnDeparture(background: Boolean, privateCollection: Boolean, inPip: Boolean): Boolean =
        privateCollection || (!background && !inPip)

    fun keepAfterTaskRemoval(background: Boolean, privateCollection: Boolean,
        playWhenReady: Boolean, hasMedia: Boolean, ended: Boolean): Boolean =
        background && !privateCollection && playWhenReady && hasMedia && !ended

    fun release(views: Int, background: Boolean, serviceAttached: Boolean): Boolean =
        views == 0 && !background && !serviceAttached

    fun reuse(background: Boolean, previousCollection: String, previousAsset: String,
        collection: String, asset: String, previousUri: String?, uri: String): Boolean =
        background && collection.isNotEmpty() && asset.isNotEmpty() &&
        previousCollection == collection && previousAsset == asset && previousUri == uri
}
