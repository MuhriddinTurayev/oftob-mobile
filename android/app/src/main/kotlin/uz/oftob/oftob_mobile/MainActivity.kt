package uz.oftob.oftob_mobile

import android.graphics.Rect
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Ekran chetidagi SI yorlig'i: uni sudraganda Android «orqaga» imosi ishga tushmasin (Android 10+)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "oftob/gesture").setMethodCallHandler { call, result ->
            if (call.method == "exclude") {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val r = call.arguments as? List<*>
                    val rects = if (r != null && r.size == 4) {
                        val n = r.map { (it as Number).toInt() }
                        listOf(Rect(n[0], n[1], n[2], n[3]))
                    } else emptyList()
                    window.decorView.systemGestureExclusionRects = rects
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
