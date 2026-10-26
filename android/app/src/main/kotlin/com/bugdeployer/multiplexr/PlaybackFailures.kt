package com.bugdeployer.multiplexr

object PlaybackFailures {
    fun message(code: Int): String = when (code) {
        2001, 2002 -> "The source could not be reached. Check its connection and retry."
        2005 -> "This file is missing. Reconnect its folder and scan the collection."
        2006 -> "Access to this file was lost. Select its root folder again in collection settings."
        3001, 3002, 3003, 3004 -> "This file or subtitle could not be read. Try another file or an external player."
        4001, 4002, 4003, 4004, 4005 -> "This device cannot decode this video or audio format. Try an external player."
        else -> "Playback stopped unexpectedly. Retry or open this file in an external player."
    }
}
