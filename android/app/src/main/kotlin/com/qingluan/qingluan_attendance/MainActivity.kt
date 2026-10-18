package com.qingluan.qingluan_attendance

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "qingluan/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "version" -> result.success(packageManager.getPackageInfo(packageName, 0).versionName)
                    "install" -> {
                        try {
                            val file = File(call.argument<String>("path") ?: "").canonicalFile
                            val root = File(cacheDir, "updates").canonicalFile
                            require(file.path.startsWith(root.path + File.separator) && file.isFile && file.extension == "apk") {
                                "安装包路径无效，请重新下载"
                            }
                            val archive = packageManager.getPackageArchiveInfo(file.path, 0)
                            require(archive?.packageName == packageName) { "安装包不属于青鸾考勤，请更换下载源" }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                                result.success(false)
                            } else {
                                val uri = FileProvider.getUriForFile(this, "$packageName.update-files", file)
                                startActivity(Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                })
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.error("install_failed", e.message ?: "无法打开系统安装器", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // Android hides the soft keyboard when it believes a hardware keyboard
        // is attached and "show virtual keyboard" is off. The attendance app is
        // touch-first, so panels explicitly ask for the IME when a field gains
        // focus. SHOW_FORCED ignores that hardware-keyboard state.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "qingluan/keyboard",
        ).setMethodCallHandler { call, result ->
            if (call.method != "show") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val view = currentFocus ?: window.decorView
            val imm =
                getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showSoftInput(view, InputMethodManager.SHOW_FORCED)
            result.success(null)
        }
    }
}
