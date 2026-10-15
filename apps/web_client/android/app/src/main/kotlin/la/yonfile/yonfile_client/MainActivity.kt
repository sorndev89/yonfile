package la.yonfile.yonfile_client

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.Uri
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "la.yonfile/incoming_file"
    private val createDocumentRequest = 7401
    private var pendingResult: MethodChannel.Result? = null
    private var pendingPath: String? = null
    private val ioExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveIncomingFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("SAVE_BUSY", "A save dialog is already open", null)
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val fileName = call.argument<String>("fileName")
                if (path == null || fileName == null || !File(path).isFile) {
                    result.error("INVALID_FILE", "Temporary file is unavailable", null)
                    return@setMethodCallHandler
                }
                pendingResult = result
                pendingPath = path
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(Intent.EXTRA_TITLE, fileName)
                }
                startActivityForResult(intent, createDocumentRequest)
            }
    }

    @Deprecated("Deprecated in Android, retained for Flutter activity result compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != createDocumentRequest) return
        val result = pendingResult ?: return
        val path = pendingPath
        pendingResult = null
        pendingPath = null
        val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
        if (uri == null || path == null) {
            result.success(false)
            return
        }
        ioExecutor.execute {
            try {
                contentResolver.openOutputStream(uri, "w")!!.use { output ->
                    FileInputStream(path).use { input -> input.copyTo(output, 64 * 1024) }
                }
                runOnUiThread { result.success(true) }
            } catch (error: Exception) {
                runOnUiThread { result.error("SAVE_FAILED", error.message, null) }
            }
        }
    }
}
