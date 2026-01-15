package com.resilient.middleware

import android.app.Activity
import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * ResilientMiddlewarePlugin
 *
 * Main plugin class for Resilient Middleware
 * Handles SMS bridge registration and communication with Flutter
 */
class ResilientMiddlewarePlugin : FlutterPlugin, ActivityAware, PluginRegistry.RequestPermissionsResultListener {

    private lateinit var smsMethodChannel: MethodChannel
    private lateinit var smsEventChannel: EventChannel
    private var smsBridge: SmsBridge? = null
    private var context: Context? = null
    private var activity: Activity? = null

    /**
     * Called when the plugin is attached to the Flutter engine
     */
    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext

        // Setup SMS Method Channel for sending SMS and checking permissions
        smsMethodChannel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            SmsBridge.CHANNEL_NAME
        )

        // Setup SMS Event Channel for receiving incoming SMS
        smsEventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            SmsReceiver.EVENT_CHANNEL_NAME
        )

        // Register event channel stream handler
        smsEventChannel.setStreamHandler(SmsStreamHandler())
    }

    /**
     * Called when the plugin is detached from the Flutter engine
     */
    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        smsMethodChannel.setMethodCallHandler(null)
        smsEventChannel.setStreamHandler(null)
        context = null
    }

    /**
     * Called when activity is attached
     */
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity

        // Initialize SMS bridge with context and activity
        smsBridge = SmsBridge(context!!, activity)
        smsMethodChannel.setMethodCallHandler(smsBridge)

        // Register for permission results
        binding.addRequestPermissionsResultListener(this)
    }

    /**
     * Called when activity is reattached (e.g., after configuration change)
     */
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    /**
     * Called when activity is detached
     */
    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    /**
     * Called when activity is detached
     */
    override fun onDetachedFromActivity() {
        activity = null
        smsBridge = null
        smsMethodChannel.setMethodCallHandler(null)
    }

    /**
     * Handle permission request results
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        smsBridge?.onRequestPermissionsResult(
            requestCode,
            permissions as Array<String>,
            grantResults
        )
        return true
    }
}
