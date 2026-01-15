package com.resilient.middleware

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Telephony
import android.telephony.SmsMessage
import android.util.Log
import io.flutter.plugin.common.EventChannel

/**
 * SMS Broadcast Receiver for handling incoming SMS messages
 * Listens for SMS_RECEIVED broadcast and forwards to Flutter
 */
class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsReceiver"
        const val EVENT_CHANNEL_NAME = "com.resilient.middleware/sms_receiver"

        // Static event sink for streaming SMS to Flutter
        private var eventSink: EventChannel.EventSink? = null

        /**
        * Set the event sink for streaming SMS messages
         */
        fun setEventSink(sink: EventChannel.EventSink?) {
            eventSink = sink
        }
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        try {
            val bundle: Bundle? = intent.extras
            if (bundle != null) {
                val pdus = bundle.get("pdus") as? Array<*>
                val format = bundle.getString("format")

                if (pdus != null) {
                    val messages = arrayOfNulls<SmsMessage>(pdus.size)
                    val messageData = mutableListOf<Map<String, Any>>()

                    for (i in pdus.indices) {
                        messages[i] = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                            SmsMessage.createFromPdu(pdus[i] as ByteArray, format)
                        } else {
                            @Suppress("DEPRECATION")
                            SmsMessage.createFromPdu(pdus[i] as ByteArray)
                        }

                        val smsMessage = messages[i]
                        if (smsMessage != null) {
                            val messageInfo = mapOf(
                                "address" to (smsMessage.originatingAddress ?: ""),
                                "body" to (smsMessage.messageBody ?: ""),
                                "timestamp" to smsMessage.timestampMillis,
                                "serviceCenterAddress" to (smsMessage.serviceCenterAddress ?: "")
                            )

                            messageData.add(messageInfo)

                            Log.d(TAG, "SMS received from: ${smsMessage.originatingAddress}")
                            Log.d(TAG, "SMS body: ${smsMessage.messageBody}")
                        }
                    }

                    // Send to Flutter via event channel
                    if (messageData.isNotEmpty()) {
                        sendToFlutter(messageData)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing SMS: ${e.message}", e)
        }
    }

    /**
     * Send SMS data to Flutter via EventChannel
     */
    private fun sendToFlutter(messages: List<Map<String, Any>>) {
        try {
            eventSink?.success(mapOf(
                "messages" to messages,
                "count" to messages.size,
                "timestamp" to System.currentTimeMillis()
            ))
            Log.d(TAG, "SMS data sent to Flutter: ${messages.size} message(s)")
        } catch (e: Exception) {
            Log.e(TAG, "Error sending SMS to Flutter: ${e.message}", e)
        }
    }
}

/**
 * Event Channel Stream Handler for SMS reception
 */
class SmsStreamHandler : EventChannel.StreamHandler {
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        SmsReceiver.setEventSink(events)
        Log.d("SmsStreamHandler", "Event sink registered for SMS reception")
    }

    override fun onCancel(arguments: Any?) {
        SmsReceiver.setEventSink(null)
        Log.d("SmsStreamHandler", "Event sink cancelled for SMS reception")
    }
}
