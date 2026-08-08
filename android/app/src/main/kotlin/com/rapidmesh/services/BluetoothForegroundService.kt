package com.rapidmesh.app.services

import android.app.Service
import android.content.Intent
import android.os.IBinder

/**
 * Bluetooth foreground service placeholder.
 *
 * Declared in AndroidManifest.xml with foregroundServiceType="connectedDevice".
 * Keeps the process priority while Bluetooth connections are active.
 */
class BluetoothForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }
}
