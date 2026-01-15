package com.resilient.middleware

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * SMS Bridge for handling SMS sending and receiving
 * Communicates between Flutter and native Android SMS functionality
 */
class SmsBridge(
    private val context: Context,
    private val activity: Activity?
) : MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.resilient.middleware/sms"
        const val SMS_PERMISSION_REQUEST_CODE = 1001

        // Permission names
        private val SMS_PERMISSIONS = arrayOf(
            Manifest.permission.SEND_SMS,
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS,
            Manifest.permission.READ_PHONE_STATE
        )
    }

    private var pendingResult: Result? = null

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "sendSMS" -> sendSMS(call, result)
            "checkPermissions" -> checkPermissions(result)
            "requestPermissions" -> requestPermissions(result)
            else -> result.notImplemented()
        }
    }

    /**
     * Send SMS message
     */
    private fun sendSMS(call: MethodCall, result: Result) {
        try {
            val phoneNumber = call.argument<String>("phoneNumber")
            val message = call.argument<String>("message")

            if (phoneNumber == null || message == null) {
                result.error(
                    "INVALID_ARGUMENTS",
                    "Phone number and message are required",
                    null
                )
                return
            }

            // Check if we have SMS permission
            if (!hasPermissions()) {
                result.error(
                    "PERMISSION_DENIED",
                    "SMS permission not granted",
                    null
                )
                return
            }

            // Get SMS manager
            val smsManager = SmsManager.getDefault()

            // Check message length - split if necessary
            if (message.length > 160) {
                // Split long messages
                val parts = smsManager.divideMessage(message)
                smsManager.sendMultipartTextMessage(
                    phoneNumber,
                    null,
                    parts,
                    null,
                    null
                )
            } else {
                // Send single SMS
                smsManager.sendTextMessage(
                    phoneNumber,
                    null,
                    message,
                    null,
                    null
                )
            }

            result.success(mapOf(
                "success" to true,
                "message" to "SMS sent successfully",
                "phoneNumber" to phoneNumber,
                "messageLength" to message.length
            ))

        } catch (e: SecurityException) {
            result.error(
                "PERMISSION_DENIED",
                "SMS permission not granted: ${e.message}",
                null
            )
        } catch (e: Exception) {
            result.error(
                "SMS_SEND_FAILED",
                "Failed to send SMS: ${e.message}",
                e.toString()
            )
        }
    }

    /**
     * Check if SMS permissions are granted
     */
    private fun checkPermissions(result: Result) {
        val granted = hasPermissions()
        result.success(mapOf(
            "granted" to granted,
            "permissions" to SMS_PERMISSIONS.map { permission ->
                mapOf(
                    "name" to permission,
                    "granted" to (ContextCompat.checkSelfPermission(
                        context,
                        permission
                    ) == PackageManager.PERMISSION_GRANTED)
                )
            }
        ))
    }

    /**
     * Request SMS permissions
     */
    private fun requestPermissions(result: Result) {
        if (activity == null) {
            result.error(
                "NO_ACTIVITY",
                "Activity is required to request permissions",
                null
            )
            return
        }

        // Check if already granted
        if (hasPermissions()) {
            result.success(mapOf(
                "granted" to true,
                "message" to "Permissions already granted"
            ))
            return
        }

        // Store result for callback
        pendingResult = result

        // Request permissions
        ActivityCompat.requestPermissions(
            activity,
            SMS_PERMISSIONS,
            SMS_PERMISSION_REQUEST_CODE
        )
    }

    /**
     * Handle permission request result
     */
    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        if (requestCode == SMS_PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }

            pendingResult?.success(mapOf(
                "granted" to allGranted,
                "message" to if (allGranted) "Permissions granted" else "Permissions denied",
                "permissions" to permissions.mapIndexed { index, permission ->
                    mapOf(
                        "name" to permission,
                        "granted" to (grantResults.getOrNull(index) == PackageManager.PERMISSION_GRANTED)
                    )
                }
            ))

            pendingResult = null
        }
    }

    /**
     * Check if all required SMS permissions are granted
     */
    private fun hasPermissions(): Boolean {
        return SMS_PERMISSIONS.all { permission ->
            ContextCompat.checkSelfPermission(
                context,
                permission
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * Get SMS manager instance
     */
    fun getSmsManager(): SmsManager {
        return SmsManager.getDefault()
    }
}
