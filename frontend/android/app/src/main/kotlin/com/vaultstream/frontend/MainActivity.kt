package com.vaultstream.frontend

import android.app.PictureInPictureParams
import android.app.PictureInPictureUiState
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.graphics.Rect
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var pipChannel: MethodChannel? = null
    private var pipParams: PictureInPictureParams? = null
    private var autoPip = false

    private fun supportsPip() = Build.VERSION.SDK_INT >= 26 &&
        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vaultstream/picture_in_picture")
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(supportsPip())
                "configure" -> {
                    if (supportsPip()) {
                        val ratio = (call.argument<Double>("ratio") ?: 1.0).coerceIn(1.0 / 2.39, 2.39)
                        val bounds = Rect(call.argument<Int>("left")!!, call.argument<Int>("top")!!,
                            call.argument<Int>("right")!!, call.argument<Int>("bottom")!!)
                        autoPip = call.argument<Boolean>("playing") == true
                        val builder = PictureInPictureParams.Builder()
                            .setAspectRatio(Rational((ratio * 10000).toInt(), 10000))
                            .setSourceRectHint(bounds)
                        // Flutter changes from a page layout to video-only;
                        // this window does not support seamless buffer resizing.
                        if (Build.VERSION.SDK_INT >= 31) builder.setAutoEnterEnabled(autoPip).setSeamlessResizeEnabled(false)
                        pipParams = builder.build()
                        setPictureInPictureParams(pipParams!!)
                    }
                    result.success(null)
                }
                "disable" -> {
                    autoPip = false
                    if (Build.VERSION.SDK_INT >= 31 && supportsPip()) {
                        setPictureInPictureParams(PictureInPictureParams.Builder().setAutoEnterEnabled(false).build())
                    }
                    pipParams = null
                    result.success(null)
                }
                "enter" -> {
                    val params = pipParams
                    if (!supportsPip() || params == null) result.success(false)
                    else try { result.success(enterPictureInPictureMode(params)) }
                    catch (_: IllegalStateException) { result.success(false) }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT in 26..30 && autoPip) {
            pipParams?.let { enterPictureInPictureMode(it) }
        }
    }

    override fun onPictureInPictureUiStateChanged(pipState: PictureInPictureUiState) {
        super.onPictureInPictureUiStateChanged(pipState)
        if (Build.VERSION.SDK_INT >= 35 && pipState.isTransitioningToPip) {
            pipChannel?.invokeMethod("modeChanged", true)
        }
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(inPip, newConfig)
        pipChannel?.invokeMethod("modeChanged", inPip)
    }

    override fun onStop() {
        if (Build.VERSION.SDK_INT >= 26 && isInPictureInPictureMode) {
            pipChannel?.invokeMethod("dismissed", null)
        }
        super.onStop()
    }
}
