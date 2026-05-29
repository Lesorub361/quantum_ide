package com.example.quantum_ide.provider

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import java.io.File
import java.io.FileNotFoundException

class UbuntuDocumentProvider : DocumentsProvider() {

    private fun getBaseDir(): File {
        val context = context ?: throw FileNotFoundException()
        // Expose the root files directory so both user projects and the Ubuntu rootfs are accessible
        return context.filesDir
    }

    override fun queryRoots(projection: Array<String>?): Cursor {
        val result = MatrixCursor(projection ?: DEFAULT_ROOT_PROJECTION)
        val baseDir = getBaseDir()
        
        val row = result.newRow()
        row.add(DocumentsContract.Root.COLUMN_ROOT_ID, baseDir.absolutePath)
        row.add(DocumentsContract.Root.COLUMN_DOCUMENT_ID, baseDir.absolutePath)
        row.add(DocumentsContract.Root.COLUMN_SUMMARY, null) 
        row.add(
            DocumentsContract.Root.COLUMN_FLAGS,
            DocumentsContract.Root.FLAG_SUPPORTS_CREATE or DocumentsContract.Root.FLAG_SUPPORTS_IS_CHILD
        )
        row.add(DocumentsContract.Root.COLUMN_TITLE, "QuantumIDE")
        row.add(DocumentsContract.Root.COLUMN_MIME_TYPES, "*/*")
        row.add(DocumentsContract.Root.COLUMN_AVAILABLE_BYTES, baseDir.freeSpace)
        row.add(DocumentsContract.Root.COLUMN_ICON, com.example.quantum_ide.R.mipmap.ic_launcher)
        return result
    }

    override fun queryDocument(documentId: String, projection: Array<String>?): Cursor {
        val result = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)
        includeFile(result, documentId)
        return result
    }

    override fun queryChildDocuments(parentId: String, proj: Array<String>?, sort: String?): Cursor {
        val result = MatrixCursor(proj ?: DEFAULT_DOCUMENT_PROJECTION)
        File(parentId).listFiles()?.forEach { includeFile(result, it.absolutePath) }
        return result
    }

    override fun openDocument(docId: String, mode: String, sig: CancellationSignal?): ParcelFileDescriptor {
        return ParcelFileDescriptor.open(File(docId), ParcelFileDescriptor.parseMode(mode))
    }

    override fun onCreate() = true

    private fun includeFile(result: MatrixCursor, docId: String) {
        val f = File(docId)
        val row = result.newRow()
        row.add(DocumentsContract.Document.COLUMN_DOCUMENT_ID, f.absolutePath)
        row.add(DocumentsContract.Document.COLUMN_DISPLAY_NAME, f.name)
        row.add(DocumentsContract.Document.COLUMN_SIZE, f.length())
        row.add(DocumentsContract.Document.COLUMN_MIME_TYPE, if (f.isDirectory) DocumentsContract.Document.MIME_TYPE_DIR else "application/octet-stream")
        row.add(DocumentsContract.Document.COLUMN_LAST_MODIFIED, f.lastModified())
        row.add(DocumentsContract.Document.COLUMN_FLAGS, DocumentsContract.Document.FLAG_SUPPORTS_DELETE or DocumentsContract.Document.FLAG_SUPPORTS_WRITE)
    }

    companion object {
        private val DEFAULT_ROOT_PROJECTION = arrayOf(
            DocumentsContract.Root.COLUMN_ROOT_ID,
            DocumentsContract.Root.COLUMN_MIME_TYPES,
            DocumentsContract.Root.COLUMN_FLAGS,
            DocumentsContract.Root.COLUMN_ICON,
            DocumentsContract.Root.COLUMN_TITLE,
            DocumentsContract.Root.COLUMN_SUMMARY,
            DocumentsContract.Root.COLUMN_DOCUMENT_ID,
            DocumentsContract.Root.COLUMN_AVAILABLE_BYTES
        )
        private val DEFAULT_DOCUMENT_PROJECTION = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_FLAGS,
            DocumentsContract.Document.COLUMN_SIZE
        )
    }
}
