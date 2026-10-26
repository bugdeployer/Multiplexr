package com.bugdeployer.multiplexr

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import java.io.InputStream

class ReadingAndroidSources(private val context: Context, private val cancelled: () -> Boolean = { false }) : ReadingSourceTree {
    override fun root(uri: String): ReadingDocument {
        val tree = Uri.parse(uri)
        require(context.contentResolver.persistedUriPermissions.any { it.isReadPermission && it.uri == tree }) { "Folder grant is missing." }
        val document = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        return ReadingDocument("${tree.authority}:${DocumentsContract.getTreeDocumentId(tree)}", document.toString(), "Root", true)
    }
    override fun children(document: ReadingDocument): List<ReadingDocument> {
        val uri = Uri.parse(document.uri)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(uri, DocumentsContract.getDocumentId(uri))
        val cursor = context.contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null) ?: error("Cannot read folder.")
        return cursor.use { c -> buildList { while (c.moveToNext()) {
            ReadingPublication.check(cancelled)
            val id = c.getString(0); val child = DocumentsContract.buildDocumentUriUsingTree(uri, id)
            add(ReadingDocument("${uri.authority}:$id", child.toString(), c.getString(1) ?: "Untitled", c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR))
            require(size <= 200000) { "Too many folder entries." }
        } } }
    }
    override fun open(document: ReadingDocument): InputStream = context.contentResolver.openInputStream(Uri.parse(document.uri)) ?: error("Cannot read source.")
    override fun cover(bytes: ByteArray): String = ReadingArtworkFiles.store(context, bytes)
}
