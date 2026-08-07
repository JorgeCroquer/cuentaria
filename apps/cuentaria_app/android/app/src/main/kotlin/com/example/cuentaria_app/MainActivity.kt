package com.example.cuentaria_app

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Backs [SystemShare] (#192, ADR-0021 §5): stages the Backup File in the
/// cache dir, hands it to `ACTION_SEND` through the app's [FileProvider], and
/// resolves the Dart call once the user has picked a target from the chooser
/// — Android has no signal for "the receiving app finished sending it", so a
/// chosen target is the closest available proxy for "share completed".
class MainActivity : FlutterActivity() {
    private val channelName = "cuentaria/system_share"
    private val targetChosenAction = "com.example.cuentaria_app.SHARE_TARGET_CHOSEN"

    private var pendingResult: MethodChannel.Result? = null
    private val targetChosenReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                pendingResult?.success(true)
                pendingResult = null
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ContextCompat.registerReceiver(
            this,
            targetChosenReceiver,
            IntentFilter(targetChosenAction),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "shareFile") {
                    val filename = call.argument<String>("filename")
                    val content = call.argument<String>("content")
                    if (filename == null || content == null) {
                        result.error("invalid_args", "filename and content are required", null)
                    } else {
                        shareFile(filename, content, result)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        unregisterReceiver(targetChosenReceiver)
        super.onDestroy()
    }

    private fun shareFile(filename: String, content: String, result: MethodChannel.Result) {
        val stagingDir = File(cacheDir, "backup").apply { mkdirs() }
        val file = File(stagingDir, filename)
        file.writeText(content)

        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)

        val sendIntent =
            Intent(Intent.ACTION_SEND).apply {
                type = "application/x-ndjson"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

        val targetChosenIntent = Intent(targetChosenAction).setPackage(packageName)
        val targetChosenPendingIntent =
            PendingIntent.getBroadcast(
                this,
                0,
                targetChosenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )

        pendingResult = result
        startActivity(Intent.createChooser(sendIntent, null, targetChosenPendingIntent.intentSender))
    }
}
