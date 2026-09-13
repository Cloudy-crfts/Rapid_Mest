package com.rapidmesh.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Native Bluetooth layer: BLE advertising + RFCOMM server/client
        RapidMeshNative(this, flutterEngine).register()
    }
}
