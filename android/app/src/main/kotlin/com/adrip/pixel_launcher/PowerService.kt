package com.adrip.pixel_launcher

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

// Servicio de accesibilidad solo para abrir el menú de apagado de Android (botón APAGAR sin root).
// No escucha eventos ni lee la pantalla.
class PowerService : AccessibilityService() {
    override fun onServiceConnected() {
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    companion object {
        var instance: PowerService? = null
    }
}
