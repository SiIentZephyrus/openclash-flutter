package dev.silentz.openclash_client

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {
    private data class PendingExport(val text: String, val result: MethodChannel.Result)

    private var pendingExport: PendingExport? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openclash/log_export")
            .setMethodCallHandler { call, result ->
                if (call.method != "save" && call.method != "share") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val text = call.argument<String>("text")
                if (text.isNullOrEmpty()) {
                    result.error("empty_logs", "没有可导出的日志", null)
                } else if (call.method == "save") {
                    saveLogs(text, result)
                } else {
                    shareLogs(text, result)
                }
            }
    }

    private fun saveLogs(text: String, result: MethodChannel.Result) {
        if (pendingExport != null) {
            result.error("export_in_progress", "正在保存日志", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "text/plain"
            putExtra(Intent.EXTRA_TITLE, logFileName())
        }
        pendingExport = PendingExport(text, result)
        try {
            startActivityForResult(intent, CREATE_LOG)
        } catch (_: Exception) {
            pendingExport = null
            result.error("picker_unavailable", "无法打开系统文件选择器", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CREATE_LOG) return
        val export = pendingExport ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingExport = null
            export.result.success(false)
            return
        }
        Thread {
            val saved = runCatching {
                val stream = contentResolver.openOutputStream(uri) ?: throw IOException()
                stream.bufferedWriter(Charsets.UTF_8).use { it.write(export.text) }
            }
            runOnUiThread {
                pendingExport = null
                saved.fold(
                    onSuccess = { export.result.success(true) },
                    onFailure = { export.result.error("save_failed", "无法写入日志文件", null) },
                )
            }
        }.start()
    }

    private fun shareLogs(text: String, result: MethodChannel.Result) {
        Thread {
            val prepared = runCatching {
                val directory = File(cacheDir, "shared_logs")
                directory.mkdirs()
                val expiresBefore = System.currentTimeMillis() - 86_400_000L
                directory.listFiles()?.filter { it.lastModified() < expiresBefore }?.forEach { it.delete() }
                val file = File(directory, logFileName())
                file.writeText(text, Charsets.UTF_8)
                val uri = FileProvider.getUriForFile(this, "$packageName.log_files", file)
                Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    clipData = ClipData.newRawUri(file.name, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
            runOnUiThread {
                try {
                    startActivity(Intent.createChooser(prepared.getOrThrow(), "分享日志"))
                    result.success(true)
                } catch (_: Exception) {
                    result.error("share_failed", "无法分享日志文件", null)
                }
            }
        }.start()
    }

    private fun logFileName(): String =
        "OpenClash-" + SimpleDateFormat("yyyyMMdd-HHmmss-SSS", Locale.ROOT).format(Date()) + ".txt"

    private companion object {
        const val CREATE_LOG = 71
    }
}
