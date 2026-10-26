package com.bugdeployer.multiplexr

/** Display uses wall time; expiration uses elapsed time so clock changes cannot extend playback. */
class AudioSleepTimer {
    var deadlineUtcMs = 0L
        private set
    private var deadlineElapsedMs = 0L
    var endOfChapter = false
        private set
    fun set(minutes: Long, utcNow: Long, elapsedNow: Long) {
        require(minutes == -1L || minutes == 0L || minutes in 1L..180L)
        clear()
        endOfChapter = minutes == -1L
        if (minutes > 0) {
            deadlineUtcMs = utcNow + minutes * 60000
            deadlineElapsedMs = elapsedNow + minutes * 60000
        }
    }
    fun expired(elapsedNow: Long) = deadlineElapsedMs > 0 && elapsedNow >= deadlineElapsedMs
    fun chapterEnded(): Boolean {
        val shouldPause = endOfChapter
        if (shouldPause) clear()
        return shouldPause
    }
    fun clear() { deadlineUtcMs = 0; deadlineElapsedMs = 0; endOfChapter = false }
}
