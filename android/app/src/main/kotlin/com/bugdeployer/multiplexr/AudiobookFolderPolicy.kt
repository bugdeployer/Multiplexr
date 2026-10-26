package com.bugdeployer.multiplexr

/** Only unambiguous new membership is inferred. Existing records are always retained. */
object AudiobookFolderPolicy {
    fun issue(depth: Int, filenames: List<String>, albums: List<String>, hasChildFolders: Boolean): String? {
        if (depth > 2) return "Audio is nested below Series/Audiobook. Move chapter files directly into the audiobook folder."
        if (depth < 2 && hasChildFolders && !(depth == 0 && filenames.size == 1 && filenames.single().endsWith(".m4b", true))) return "Audio files are mixed with child folders. Use a separate folder for each audiobook."
        val sameAlbum = albums.isNotEmpty() && albums.all { it.isNotBlank() } && albums.map { it.trim().lowercase() }.distinct().size == 1
        if (depth == 0 && filenames.size > 1 && !sameAlbum) return "Loose audio files do not identify one audiobook. Put each audiobook in its own folder."
        if (depth == 1 && filenames.count { it.endsWith(".m4b", true) } > 1 && !sameAlbum) return "Multiple M4Bs do not identify one audiobook. Use Series/Audiobook/audio files."
        return null
    }
}
