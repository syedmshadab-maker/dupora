package com.dupora.dupora

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var safChannel: SafChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        safChannel = SafChannel(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SafChannel.CHANNEL_NAME)
            .setMethodCallHandler(safChannel)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, StorageChannel.CHANNEL_NAME)
            .setMethodCallHandler(StorageChannel(this))
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        safChannel.handleActivityResult(requestCode, resultCode, data)
    }
}
