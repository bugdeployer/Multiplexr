package com.bugdeployer.multiplexr

/** Activity-result request codes share one namespace across every document picker. */
enum class DocumentRequest(val code: Int) {
    ROOT(61), BACKUP(64), THEME(65), SUBTITLE(73), AUDIO(81), CHAPTERS(82), COVER(83)
}
