package com.adrip.pixel_launcher

import android.accessibilityservice.AccessibilityService
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
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
import rikka.shizuku.Shizuku
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
                // Selector de archivos del sistema (cualquier tipo, sin permisos) para adjuntar a Claude.
                // Devuelve [{path, name, mime, size}]: copias en la carpeta de la app (se borran al mandarlas).
                "pickFiles" -> {
                    await(result)
                    startActivityForResult(
                        Intent(Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("*/*")
                            .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true),
                        PICK_FILES,
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
                // Pestaña TERMINAL: corre bash de Termux con estos argumentos, en segundo plano o en una
                // sesión visible. Requiere allow-external-apps=true en ~/.termux/termux.properties.
                "termux" -> result.success(
                    runCatching {
                        startService(
                            Intent("com.termux.RUN_COMMAND")
                                .setClassName("com.termux", "com.termux.app.RunCommandService")
                                .putExtra("com.termux.RUN_COMMAND_PATH", "$TERMUX/usr/bin/bash")
                                .putExtra("com.termux.RUN_COMMAND_ARGUMENTS", call.argument<List<String>>("args")!!.toTypedArray())
                                .putExtra("com.termux.RUN_COMMAND_WORKDIR", "$TERMUX/home")
                                .putExtra("com.termux.RUN_COMMAND_BACKGROUND", call.argument<Boolean>("background") == true)
                                .putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", "0"), // la sesión nueva queda al frente
                        )
                        // Android 10+ no deja que el servicio de Termux abra su pantalla desde atrás (haría falta "Mostrar sobre otras apps"): la abrimos nosotros, que estamos al frente
                        if (call.argument<Boolean>("background") != true) {
                            startActivity(Intent().setClassName("com.termux", "com.termux.app.TermuxActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        }
                        null
                    }.getOrElse { it.message ?: "no se pudo hablar con Termux" },
                )
                "termuxPermission" -> {
                    if (checkSelfPermission(RUN_COMMAND) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        await(result)
                        requestPermissions(arrayOf(RUN_COMMAND), TERMUX_PERMISSION)
                    }
                }
                "shizukuPermission" -> when {
                    !Shizuku.pingBinder() -> result.success(false)
                    Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED -> result.success(true)
                    else -> {
                        await(result)
                        Shizuku.requestPermission(SHIZUKU_PERMISSION)
                    }
                }
                // Comando como usuario shell (uid 2000) vía Shizuku. Devuelve {code, out, err}.
                "shizuku" -> {
                    if (!Shizuku.pingBinder() || Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                        return@setMethodCallHandler result.error("no-shizuku", "Shizuku no está corriendo o no dio permiso", null)
                    }
                    val cmd = call.argument<String>("cmd")!!
                    Thread {
                        val out = runCatching { shell(cmd) }
                        runOnUiThread {
                            out.fold({ result.success(it) }, { result.error("shizuku", it.message, null) })
                        }
                    }.start()
                }
                // Con Claude trabajando, servicio en primer plano: si Android mata al launcher, muere el MCP
                // (permisos) y el turno se queda sin poder usar tools.
                "keepAlive" -> {
                    val i = Intent(this, KeepAlive::class.java)
                    runCatching {
                        when {
                            call.arguments != true -> stopService(i)
                            Build.VERSION.SDK_INT >= 26 -> startForegroundService(i)
                            else -> startService(i)
                        }
                    }
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
        if (requestCode != PICK_IMAGES && requestCode != DELETE_IMAGE && requestCode != PICK_FILES) return
        val result = pending ?: return
        pending = null
        if (requestCode == PICK_FILES) {
            val clip = data?.clipData
            val uris = if (clip != null) (0 until clip.itemCount).map { clip.getItemAt(it).uri } else listOfNotNull(data?.data)
            Thread {
                val dir = File(filesDir, "attachments").apply { mkdirs() }
                val files = uris.mapNotNull { uri ->
                    runCatching {
                        var name = "archivo"
                        var size = 0L
                        contentResolver.query(uri, null, null, null, null)?.use { c ->
                            if (c.moveToFirst()) {
                                c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }?.let { name = c.getString(it) }
                                c.getColumnIndex(android.provider.OpenableColumns.SIZE).takeIf { it >= 0 }?.let { size = c.getLong(it) }
                            }
                        }
                        val f = File(dir, "${System.nanoTime()}")
                        contentResolver.openInputStream(uri)!!.use { input -> f.outputStream().use { input.copyTo(it) } }
                        mapOf("path" to f.path, "name" to name, "mime" to (contentResolver.getType(uri) ?: ""), "size" to f.length())
                    }.getOrNull()
                }
                runOnUiThread { result.success(files) }
            }.start()
            return
        }
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

    private val shizukuListener = Shizuku.OnRequestPermissionResultListener { code, grant ->
        if (code != SHIZUKU_PERMISSION) return@OnRequestPermissionResultListener
        pending?.success(grant == PackageManager.PERMISSION_GRANTED)
        pending = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Shizuku.addRequestPermissionResultListener(shizukuListener)
    }

    override fun onDestroy() {
        Shizuku.removeRequestPermissionResultListener(shizukuListener)
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != TERMUX_PERMISSION) return
        pending?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        pending = null
    }

    // ponytail: newProcess es privado desde la API 13 de Shizuku; si lo sacan, pasar a UserService.
    private val newProcess by lazy {
        Shizuku::class.java.getDeclaredMethod(
            "newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java,
        ).apply { isAccessible = true }
    }

    private fun shell(cmd: String): Map<String, Any> {
        val p = newProcess.invoke(null, arrayOf("sh", "-c", cmd), null, null) as Process
        p.outputStream.close()
        // stdout y stderr en paralelo: si uno se llena y nadie lo lee, el comando se traba
        var out = ""
        var err = ""
        val readers = listOf(
            Thread { out = p.inputStream.bufferedReader().readText() },
            Thread { err = p.errorStream.bufferedReader().readText() },
        ).onEach { it.start() }
        // waitFor(timeout) de ShizukuRemoteProcess llama exitValue(), que por binder llega como IllegalArgumentException y no se atrapa
        val killer = Thread { runCatching { Thread.sleep(5 * 60_000L); p.destroy() } }.apply { isDaemon = true; start() }
        p.waitFor()
        killer.interrupt()
        readers.forEach { it.join(2000) }
        return mapOf("code" to runCatching { p.exitValue() }.getOrDefault(-1), "out" to out, "err" to err)
    }

    private fun widgetDone(ok: Boolean) {
        if (!ok) host.deleteAppWidgetId(widgetId)
        pending?.success(if (ok) widgetId else null)
        pending = null
    }

    companion object {
        const val PICK_IMAGES = 1
        const val DELETE_IMAGE = 2
        const val PICK_FILES = 7
        const val PICK_WIDGET = 3
        const val CONFIGURE_WIDGET = 4
        const val TERMUX_PERMISSION = 5
        const val SHIZUKU_PERMISSION = 6
        const val RUN_COMMAND = "com.termux.permission.RUN_COMMAND"
        const val TERMUX = "/data/data/com.termux/files"
    }
}

/** Solo sube la prioridad del proceso (y muestra el aviso) mientras Claude tiene un turno en curso. */
class KeepAlive : android.app.Service() {
    override fun onBind(intent: Intent?): android.os.IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(android.app.NotificationManager::class.java).createNotificationChannel(
                android.app.NotificationChannel("claude", "Claude trabajando", android.app.NotificationManager.IMPORTANCE_LOW),
            )
            android.app.Notification.Builder(this, "claude")
        } else {
            @Suppress("DEPRECATION") android.app.Notification.Builder(this)
        }.setSmallIcon(R.mipmap.ic_launcher).setContentTitle("Claude está trabajando").setOngoing(true).build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(1, n, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(1, n)
        }
        return START_NOT_STICKY
    }
}
