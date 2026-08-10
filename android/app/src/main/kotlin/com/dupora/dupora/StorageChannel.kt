package com.dupora.dupora

import android.content.Context
import android.os.Build
import android.os.storage.StorageManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Enumerates Android storage volumes (internal storage, SD cards, USB OTG
 * where the platform exposes a `StorageVolume`) via [StorageManager].
 *
 * Android 11+ scoped storage means most of these are only *browsable*
 * through Storage Access Framework document trees (see [SafChannel]) rather
 * than raw filesystem paths, but volume-level metadata (name, removable,
 * free/total space) is still available directly.
 */
class StorageChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "com.dupora/storage"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listVolumes" -> result.success(listVolumes())
            else -> result.notImplemented()
        }
    }

    private fun listVolumes(): List<Map<String, Any?>> {
        val storageManager = context.getSystemService(Context.STORAGE_SERVICE) as? StorageManager
            ?: return emptyList()

        val volumes = mutableListOf<Map<String, Any?>>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            for (volume in storageManager.storageVolumes) {
                val dir = volume.directory
                val total = dir?.totalSpace ?: 0L
                val free = dir?.freeSpace ?: 0L
                volumes.add(
                    mapOf(
                        "path" to (dir?.absolutePath ?: ""),
                        "label" to (volume.getDescription(context) ?: "Storage"),
                        "isRemovable" to volume.isRemovable,
                        "isPrimary" to volume.isPrimary,
                        "totalBytes" to total,
                        "freeBytes" to free,
                    ),
                )
            }
        }
        return volumes
    }
}
