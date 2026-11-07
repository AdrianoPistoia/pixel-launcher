package com.adrip.pixel_launcher

import android.accessibilityservice.AccessibilityService
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null // un selector o pedido de borrado a la vez
    private val host by lazy { AppWidgetHost(applicationContext, 1024) }
    private var widgetId = 0 // el widget que se está eligiendo

    // los widgets se actualizan solo mientras el launcher está a la vista
    override fun onStart() {
        super.onStart()
        host.startListening()
    }

    override fun onStop() {
        super.onStop()
        runCatching { host.stopListening() }
    }

    private fun await(result: MethodChannel.Result) {
        pending?.success(null)
        pending = result
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        // Widget de Android dentro de Flutter; avisa su tamaño para que el widget elija su diseño.
        engine.platformViewsController.registry.registerViewFactory(
            "pixel_launcher/widget",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                    val id = args as Int
                    val view = host.createView(context, id, AppWidgetManager.getInstance(context).getAppWidgetInfo(id))
                    view.addOnLayoutChangeListener { v, l, t, r, b, oldL, oldT, oldR, oldB ->
                        if (r - l == oldR - oldL && b - t == oldB - oldT) return@addOnLayoutChangeListener
                        val d = v.resources.displayMetrics.density
                        val w = ((r - l) / d).toInt()
                        val h = ((b - t) / d).toInt()
                        @Suppress("DEPRECATION")
                        (v as AppWidgetHostView).updateAppWidgetSize(Bundle(), w, h, w, h)
                    }
                    return object : PlatformView {
                        override fun getView() = view
                        override fun dispose() {}
                    }
                }
            },
        )
        MethodChannel(engine.dartExecutor.binaryMessenger, "pixel_launcher").setMethodCallHandler { call, result ->
            when (call.method) {
                // Selector de imágenes del sistema (sin permisos). Devuelve [{path, uri}]: path es una copia
                // propia para mostrarla, uri la original (para poder borrarla del teléfono).
                "pickImages" -> {
                    await(result)
                    startActivityForResult(
                        Intent(Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("image/*")
                            .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true),
                        PICK_IMAGES,
                    )
                }
                // Borra la original del teléfono. Devuelve true si se borró.
                "deleteImage" -> {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    val media = if (Build.VERSION.SDK_INT >= 30) runCatching { MediaStore.getMediaUri(this, uri) }.getOrNull() else null
                    if (media != null && Build.VERSION.SDK_INT >= 30) {
                        // Android 11+: el sistema pide confirmación
                        await(result)
                        startIntentSenderForResult(
                            MediaStore.createDeleteRequest(contentResolver, listOf(media)).intentSender,
                            DELETE_IMAGE, null, 0, 0, 0,
                        )
                    } else {
                        result.success(runCatching { DocumentsContract.deleteDocument(contentResolver, uri) }.getOrDefault(false))
                    }
                }
                // Apaga o reinicia. Con root, directo ("root"); si no, abre el menú de apagado de Android
                // con el servicio de accesibilidad ("dialog"); si no está activado, "none".
                "power" -> {
                    val cmd = if (call.argument<String>("action") == "reboot") "svc power reboot" else "svc power shutdown"
                    Thread {
                        val rooted = runCatching { Runtime.getRuntime().exec(arrayOf("su", "-c", cmd)).waitFor() == 0 }
                            .getOrDefault(false)
                        runOnUiThread {
                            result.success(
                                when {
                                    rooted -> "root"
                                    PowerService.instance?.performGlobalAction(AccessibilityService.GLOBAL_ACTION_POWER_DIALOG) == true -> "dialog"
                                    else -> "none"
                                },
                            )
                        }
                    }.start()
                }
                // Selector de widgets del sistema (y su configuración, si tiene). Devuelve el id o null.
                "pickWidget" -> {
                    await(result)
                    widgetId = host.allocateAppWidgetId()
                    runCatching {
                        startActivityForResult(
                            Intent(AppWidgetManager.ACTION_APPWIDGET_PICK).putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId),
                            PICK_WIDGET,
                        )
                    }.onFailure { widgetDone(false) }
                }
                "deleteWidget" -> {
                    host.deleteAppWidgetId(call.argument<Int>("id")!!)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("startActivityForResult alcanza para un selector a la vez")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_WIDGET && resultCode == RESULT_OK) {
            val info = AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId)
            if (info?.configure != null) {
                runCatching { host.startAppWidgetConfigureActivityForResult(this, widgetId, 0, CONFIGURE_WIDGET, null) }
                    .onFailure { widgetDone(false) }
                return
            }
        }
        if (requestCode == PICK_WIDGET || requestCode == CONFIGURE_WIDGET) return widgetDone(resultCode == RESULT_OK)
        if (requestCode != PICK_IMAGES && requestCode != DELETE_IMAGE) return
        val result = pending ?: return
        pending = null
        if (requestCode == DELETE_IMAGE) {
            result.success(resultCode == RESULT_OK)
            return
        }
        val clip = data?.clipData
        val uris = if (clip != null) (0 until clip.itemCount).map { clip.getItemAt(it).uri } else listOfNotNull(data?.data)
        for (uri in uris) {
            // que el permiso sobreviva al reinicio, para poder borrarla después
            runCatching {
                contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }
        }
        // se copian a la carpeta de la app: así se muestran aunque se pierda el permiso del URI
        Thread {
            val dir = File(filesDir, "photos").apply { mkdirs() }
            val photos = uris.mapNotNull { uri ->
                runCatching {
                    val f = File(dir, "${System.nanoTime()}")
                    contentResolver.openInputStream(uri)!!.use { input -> f.outputStream().use { input.copyTo(it) } }
                    mapOf("path" to f.path, "uri" to uri.toString())
                }.getOrNull()
            }
            runOnUiThread { result.success(photos) }
        }.start()
    }

    private fun widgetDone(ok: Boolean) {
        if (!ok) host.deleteAppWidgetId(widgetId)
        pending?.success(if (ok) widgetId else null)
        pending = null
    }

    companion object {
        const val PICK_IMAGES = 1
        const val DELETE_IMAGE = 2
        const val PICK_WIDGET = 3
        const val CONFIGURE_WIDGET = 4
    }
}
