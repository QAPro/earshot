package tech.baileyenterprises.earshot

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Receives documents shared or "opened with" Earshot, copies them into the
 * app's cache and hands the path to Flutter over the "earshot/share" channel.
 */
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private var pending: String? = null
    private var dartReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "earshot/share").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "getInitialFile") {
                    dartReady = true
                    result.success(pending)
                    pending = null
                } else {
                    result.notImplemented()
                }
            }
        }
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        if (intent == null) return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            Intent.ACTION_VIEW -> intent.data
            else -> null
        }
        val sharedText = if (uri == null && intent.action == Intent.ACTION_SEND) intent.getStringExtra(Intent.EXTRA_TEXT) else null
        if (uri == null && sharedText == null) return
        // Don't re-handle the same intent after a rotation or restart.
        intent.action = null
        Thread {
            val path = try {
                if (uri != null) copyToCache(uri, intent.type) else writeText(sharedText!!)
            } catch (e: Exception) {
                null
            } ?: return@Thread
            runOnUiThread {
                if (dartReady) channel?.invokeMethod("fileShared", path) else pending = path
            }
        }.start()
    }

    private fun copyToCache(uri: Uri, type: String?): String {
        var name: String? = null
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) name = c.getString(0)
            }
        }
        if (name == null) name = uri.lastPathSegment?.substringAfterLast('/')
        var safe = (name ?: "document").replace(Regex("[\\\\/:*?\"<>|]"), "_")
        if (!safe.contains('.')) {
            val mime = type ?: contentResolver.getType(uri)
            val ext = when (mime) {
                "text/markdown" -> "md"
                else -> MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "txt"
            }
            safe = "$safe.$ext"
        }
        // A fresh folder per share keeps the original file name intact.
        val dir = File(File(cacheDir, "shared"), System.currentTimeMillis().toString()).apply { mkdirs() }
        val out = File(dir, safe)
        contentResolver.openInputStream(uri)!!.use { input -> out.outputStream().use { input.copyTo(it) } }
        return out.absolutePath
    }

    private fun writeText(text: String): String {
        val dir = File(File(cacheDir, "shared"), System.currentTimeMillis().toString()).apply { mkdirs() }
        val firstLine = text.lineSequence().firstOrNull { it.isNotBlank() }?.take(40)?.trim() ?: "Shared text"
        val out = File(dir, firstLine.replace(Regex("[\\\\/:*?\"<>|]"), "_") + ".txt")
        out.writeText(text)
        return out.absolutePath
    }
}
