package tech.kmlab.kmlab_toolbox

import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * kmlab Toolbox · Android 宿主
 *
 * 这里只做一件事：给「原生 Toast」开一条通道。
 *
 * 为什么需要它？—— Flutter 的 SnackBar 画在 Flutter 视图树里，而 WebView 是
 * PlatformView，在原生视图层级里比 Flutter 树更靠上，SnackBar 会被整个盖住
 * （见 DESIGN.md BUG #12）。所以提示一律走系统 Toast。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "km/toast"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
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
    }
}
