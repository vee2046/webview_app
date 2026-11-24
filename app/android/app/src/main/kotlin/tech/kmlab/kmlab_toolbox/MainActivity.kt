package tech.kmlab.kmlab_toolbox

import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * kmlab Toolbox · Android 宿主
 *
 * 两条通道：
 *   1. `km/toast`   —— 原生 Toast（WebView 是 PlatformView，会把 Flutter 的 SnackBar 整个盖住，见 DESIGN.md BUG #12）
 *   2. `km/install` —— 拉起系统安装界面（自动更新用）
 *
 * 为什么安装要走原生？—— 安装 APK 要用 `content://` URI +
 * `FLAG_GRANT_READ_URI_PERMISSION` 把文件读权限授予系统安装器，
 * `url_launcher` 给不了这个授权，只能自己发 Intent。
 */
class MainActivity : FlutterActivity() {

    private val toastChannelName = "km/toast"
    private val installChannelName = "km/install"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, toastChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "show") {
                    val message = call.argument<String>("message") ?: ""
                    runOnUiThread {
                        Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "installApk") {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty() || !File(path).exists()) {
                        result.error("no_file", "APK 不存在：$path", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri: Uri = FileProvider.getUriForFile(
                            this, "$packageName.km.fileprovider", File(path)
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
