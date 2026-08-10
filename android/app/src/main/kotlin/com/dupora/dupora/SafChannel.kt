package com.dupora.dupora

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.concurrent.atomic.AtomicInteger

/**
 * Storage Access Framework bridge.
 *
 * Android 11+ (this project's minimum) does not expose most user storage as
 * raw filesystem paths, so SAF document trees are the only universally
 * correct way to browse/read arbitrary user-picked folders (including SD
 * cards and, where the provider exposes it, USB OTG). Per the project spec,
 * hashing must still happen via the Rust BLAKE3 engine rather than in Dart:
 * [readChunk] streams raw bytes out to Dart, which feeds them into the
 * native incremental hasher (`dupora_stream_hasher_*` in
 * `rust/src/ffi/stream_hasher.rs`) rather than hashing them in Dart itself.
 *
 * Uses the classic `startActivityForResult`/`onActivityResult` pair (via
 * [handleActivityResult], called from [MainActivity]) rather than the
 * AndroidX Activity Result API, so `MainActivity` can stay a plain
 * `FlutterActivity` instead of requiring a `ComponentActivity` base class.
 *
 * NOTE: this class has not been exercised on a physical Android device or
 * emulator as part of this build (see BUILD.md / KNOWN LIMITATIONS) - it is
 * written against the documented SAF/DocumentsContract APIs but is
 * device-unverified.
 */
class SafChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "com.dupora/saf"
        const val REQUEST_CODE_PICK_DIRECTORY = 42_001
    }

    private val openStreams = mutableMapOf<Int, InputStream>()
    private val nextHandle = AtomicInteger(1)
    private var pendingPickResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pickDirectory" -> pickDirectory(result)
                "listPersistedTrees" -> result.success(listPersistedTrees())
                "releaseTree" -> {
                    releaseTree(call.argument<String>("treeUri")!!)
                    result.success(null)
                }
                "listChildren" -> result.success(
                    listChildren(
                        call.argument<String>("treeUri")!!,
                        call.argument<String>("parentDocumentId"),
                    ),
                )
                "openStream" -> result.success(openStream(call.argument<String>("documentUri")!!))
                "readChunk" -> result.success(
                    readChunk(call.argument<Int>("handle")!!, call.argument<Int>("size")!!),
                )
                "closeStream" -> {
                    closeStream(call.argument<Int>("handle")!!)
                    result.success(null)
                }
                "deleteDocument" -> result.success(
                    deleteDocument(call.argument<String>("documentUri")!!),
                )
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("SAF_ERROR", e.message, null)
        }
    }

    private fun pickDirectory(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("SAF_BUSY", "A directory picker is already open", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        activity.startActivityForResult(intent, REQUEST_CODE_PICK_DIRECTORY)
    }

    /** Called from `MainActivity.onActivityResult`. Returns true if it was ours to handle. */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE_PICK_DIRECTORY) return false
        val result = pendingPickResult
        pendingPickResult = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            result?.success(null)
            return true
        }
        activity.contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
        result?.success(
            mapOf(
                "treeUri" to uri.toString(),
                "displayName" to (DocumentsContract.getTreeDocumentId(uri) ?: uri.toString()),
            ),
        )
        return true
    }

    private fun listPersistedTrees(): List<Map<String, String>> {
        return activity.contentResolver.persistedUriPermissions
            .filter { it.isReadPermission }
            .map { mapOf("treeUri" to it.uri.toString()) }
    }

    private fun releaseTree(treeUri: String) {
        val uri = Uri.parse(treeUri)
        activity.contentResolver.releasePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
    }

    private fun listChildren(treeUri: String, parentDocumentId: String?): List<Map<String, Any?>> {
        val tree = Uri.parse(treeUri)
        val parentId = parentDocumentId ?: DocumentsContract.getTreeDocumentId(tree)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val out = mutableListOf<Map<String, Any?>>()
        activity.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameCol = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeCol = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeCol = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
            val modifiedCol = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (cursor.moveToNext()) {
                val documentId = cursor.getString(idCol)
                val mimeType = cursor.getString(mimeCol)
                out.add(
                    mapOf(
                        "documentId" to documentId,
                        "documentUri" to DocumentsContract.buildDocumentUriUsingTree(tree, documentId).toString(),
                        "name" to cursor.getString(nameCol),
                        "mimeType" to mimeType,
                        "isDirectory" to (mimeType == DocumentsContract.Document.MIME_TYPE_DIR),
                        "size" to cursor.getLong(sizeCol),
                        "lastModified" to cursor.getLong(modifiedCol),
                    ),
                )
            }
        }
        return out
    }

    private fun openStream(documentUri: String): Int {
        val stream = activity.contentResolver.openInputStream(Uri.parse(documentUri))
            ?: throw IllegalStateException("Unable to open $documentUri")
        val handle = nextHandle.getAndIncrement()
        openStreams[handle] = stream
        return handle
    }

    private fun readChunk(handle: Int, size: Int): ByteArray {
        val stream = openStreams[handle] ?: throw IllegalStateException("Unknown stream handle $handle")
        val buffer = ByteArray(size)
        val read = stream.read(buffer)
        if (read <= 0) return ByteArray(0)
        return if (read == size) buffer else buffer.copyOf(read)
    }

    private fun closeStream(handle: Int) {
        openStreams.remove(handle)?.close()
    }

    private fun deleteDocument(documentUri: String): Boolean {
        val uri = Uri.parse(documentUri)
        return DocumentsContract.deleteDocument(activity.contentResolver, uri)
    }
}
