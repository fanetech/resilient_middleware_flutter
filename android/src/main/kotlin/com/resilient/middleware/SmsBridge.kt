package com.resilient.middleware

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * SMS Bridge for handling SMS sending and receiving
 * Supports sending to Africa's Talking shortcodes (e.g. 6076)
 */
class SmsBridge(
    private val context: Context,
    private val activity: Activity?
) : MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.resilient.middleware/sms"
        const val SMS_PERMISSION_REQUEST_CODE = 1001
        private const val SMS_SENT_ACTION = "com.resilient.middleware.SMS_SENT"

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
     * Get SmsManager compatible with all Android versions
     */
    private fun getSmsManagerCompat(): SmsManager {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }
    }

    /**
     * Send SMS message with sent confirmation via PendingIntent
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

            if (!hasPermissions()) {
                result.error(
                    "PERMISSION_DENIED",
                    "SMS permission not granted",
                    null
                )
                return
            }

            val smsManager = getSmsManagerCompat()

            // Create PendingIntent for sent confirmation
            val sentIntent = PendingIntent.getBroadcast(
                context,
                0,
                Intent(SMS_SENT_ACTION),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            // Register receiver to listen for sent confirmation
            val sentReceiver = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context?, intent: Intent?) {
                    try {
                        context.unregisterReceiver(this)
                    } catch (_: Exception) {}

                    when (resultCode) {
                        Activity.RESULT_OK -> {
                            result.success(mapOf(
                                "success" to true,
                                "message" to "SMS sent successfully",
                                "phoneNumber" to phoneNumber,
                                "messageLength" to message.length
                            ))
                        }
                        SmsManager.RESULT_ERROR_NO_SERVICE -> {
                            result.error(
                                "NO_SERVICE",
                                "No cellular service available",
                                null
                            )
                        }
                        SmsManager.RESULT_ERROR_RADIO_OFF -> {
                            result.error(
                                "RADIO_OFF",
                                "Radio/cellular is turned off",
                                null
                            )
                        }
                        else -> {
                            result.error(
                                "SMS_SEND_FAILED",
                                "SMS send failed with code: $resultCode",
                                null
                            )
                        }
                    }
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(
                    sentReceiver,
                    IntentFilter(SMS_SENT_ACTION),
                    Context.RECEIVER_NOT_EXPORTED
                )
            } else {
                context.registerReceiver(
                    sentReceiver,
                    IntentFilter(SMS_SENT_ACTION)
                )
            }

            // Send SMS (works with both phone numbers and shortcodes)
            if (message.length > 160) {
                val parts = smsManager.divideMessage(message)
                val sentIntents = ArrayList<PendingIntent>(parts.size)
                for (i in parts.indices) {
                    sentIntents.add(sentIntent)
                }
                smsManager.sendMultipartTextMessage(
                    phoneNumber,
                    null,
                    parts,
                    sentIntents,
                    null
                )
            } else {
                smsManager.sendTextMessage(
                    phoneNumber,
                    null,
                    message,
                    sentIntent,
                    null
                )
            }

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

        if (hasPermissions()) {
            result.success(mapOf(
                "granted" to true,
                "message" to "Permissions already granted"
            ))
            return
        }

        pendingResult = result

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
}
