package com.bugdeployer.multiplexr

import org.json.JSONObject
import org.json.JSONArray

/** Folder membership is source evidence; online metadata never owns it. */
object AudioScanReconciliation {
    /** Append only; source and chapter IDs, user order and progress stay intact. */
    fun append(book: JSONObject, files: List<JSONObject>, chapters: JSONArray) {
        val sources = book.getJSONArray("files")
        val navigation = book.getJSONArray("chapters")
        val sourceIds = (0 until sources.length()).map { sources.getJSONObject(it).getString("id") }.toMutableSet()
        val chapterIds = (0 until navigation.length()).map { navigation.getJSONObject(it).getString("id") }.toMutableSet()
        for (file in files) if (sourceIds.add(file.getString("id"))) sources.put(file)
        for (i in 0 until chapters.length()) {
            val chapter = chapters.getJSONObject(i)
            require(chapter.getString("fileId") in sourceIds)
            if (chapterIds.add(chapter.getString("id"))) navigation.put(chapter)
        }
    }
    sealed class Decision {
        data class Append(val owner: String) : Decision()
        data object Create : Decision()
        data object Unchanged : Decision()
        data object Review : Decision()
    }

    fun decide(existingOwners: Set<String>, folderOwner: String?, freshCount: Int): Decision {
        require(freshCount >= 0)
        if (freshCount == 0) return Decision.Unchanged
        val owners = existingOwners + listOfNotNull(folderOwner)
        if (owners.size > 1) return Decision.Review
        return owners.singleOrNull()?.let { Decision.Append(it) } ?: Decision.Create
    }
}
