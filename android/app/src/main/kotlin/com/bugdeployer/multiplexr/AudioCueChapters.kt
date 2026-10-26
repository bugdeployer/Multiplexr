package com.bugdeployer.multiplexr

import org.json.JSONArray
import org.json.JSONObject

/** CUE INDEX 01 markers refer to existing sources; audio files are never split. */
object AudioCueChapters {
    fun parse(text: String, files: List<JSONObject>): JSONArray {
        data class Entry(val file: JSONObject, val number: Int, var title: String = "", var start: Long? = null)
        val entries = mutableListOf<Entry>(); var source: JSONObject? = null; var track: Entry? = null
        for (line in text.lineSequence().map { it.trim() }) {
            Regex("^FILE\\s+(?:\"([^\"]+)\"|(\\S+))\\s+\\S+$", RegexOption.IGNORE_CASE).matchEntire(line)?.let { match ->
                val name = match.groupValues[1].ifEmpty { match.groupValues[2] }.replace('\\', '/').substringAfterLast('/')
                val candidates = files.filter { it.getString("filename").equals(name, true) }
                require(candidates.size == 1) { "CUE file must identify one audio source." }
                source = candidates.single(); track = null
            }
            Regex("^TRACK\\s+(\\d+)\\s+AUDIO$", RegexOption.IGNORE_CASE).matchEntire(line)?.let {
                require(source != null && entries.size < 1000)
                track = Entry(source!!, it.groupValues[1].toInt()); entries.add(track!!)
            }
            Regex("^TITLE\\s+\"(.*)\"$", RegexOption.IGNORE_CASE).matchEntire(line)?.let { if (track != null) track!!.title = it.groupValues[1] }
            Regex("^INDEX\\s+01\\s+(\\d+):(\\d{2}):(\\d{2})$", RegexOption.IGNORE_CASE).matchEntire(line)?.let {
                val minutes = it.groupValues[1].toLong(); val seconds = it.groupValues[2].toLong(); val frames = it.groupValues[3].toLong()
                require(track != null && seconds < 60 && frames < 75 && minutes < 100000)
                track!!.start = (minutes * 60 + seconds) * 1000 + frames * 1000 / 75
            }
        }
        require(entries.isNotEmpty() && entries.all { it.start != null })
        val result = JSONArray()
        for ((i, entry) in entries.withIndex()) {
            val id = entry.file.getString("id"); val start = entry.start!!
            val duration = entry.file.optLong("durationMs")
            val next = entries.getOrNull(i + 1)?.takeIf { it.file.getString("id") == id }?.start ?: duration.takeIf { it > 0 }
            require((duration == 0L || start < duration) && (next == null || next > start))
            val c = JSONObject().put("id", "$id:cue:$start").put("fileId", id).put("title", entry.title.ifBlank { "Chapter ${entry.number}" }).put("startMs", start)
            if (next != null) c.put("endMs", next)
            result.put(c)
        }
        return result
    }
}
