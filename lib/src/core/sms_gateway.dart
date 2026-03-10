/// SMS gateway for fallback communication via Africa's Talking
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart';
import '../models/queue_item.dart';
import '../models/response_model.dart';
import '../models/sms_response.dart';
import '../utils/logger.dart';
import 'native_sms_bridge.dart';
import 'transaction_sms_service.dart';

/// Result of an SMS send operation
class SMSSendResult {
  final bool success;
  final String smsText;

  const SMSSendResult({required this.success, required this.smsText});
}

/// SMS Gateway for fallback communication
class SMSGateway {
  static final SMSGateway _instance = SMSGateway._internal();
  factory SMSGateway() => _instance;
  SMSGateway._internal();

  static const String defaultGatewayNumber = '+16615184543';
  static const int maxSMSLength = 160;
  String _gatewayNumber = defaultGatewayNumber;

  final StreamController<Response> _responseController =
      StreamController<Response>.broadcast();

  // Native SMS bridge for Android
  final NativeSMSBridge _nativeBridge = NativeSMSBridge();
  bool _nativeBridgeInitialized = false;


  /// Initialize SMS gateway
  Future<void> initialize() async {
    try {
      // Initialize native bridge for Android
      if (Platform.isAndroid) {
        await _nativeBridge.initialize();
        _nativeBridgeInitialized = true;

        // Listen to incoming SMS responses
        _nativeBridge.incomingMessages.listen((smsData) {
          final body = smsData['body'] as String?;
          if (body != null) {
            Logger.info('Incoming SMS response: $body');
            final parsed = parseResponse(body);
            _responseController.add(parsed);
          }
        });

        Logger.info('Native SMS bridge initialized for Android');
      }
    } catch (e) {
      Logger.error('Failed to initialize SMS gateway', e);
    }
  }

  /// Set gateway number (shortcode or phone number)
  void setGatewayNumber(String number) {
    _gatewayNumber = number;
    Logger.info('SMS gateway number set to: $number');
  }

  /// Get gateway number
  String getGatewayNumber() => _gatewayNumber;

  /// Request SMS permissions
  Future<bool> requestPermissions() async {
    // Try native bridge first for Android
    if (Platform.isAndroid && _nativeBridgeInitialized) {
      return await _nativeBridge.requestPermissions();
    }

    // Fallback to permission_handler
    final status = await Permission.sms.request();
    final granted = status.isGranted;

    if (granted) {
      Logger.info('SMS permissions granted');
    } else {
      Logger.warning('SMS permissions denied');
    }

    return granted;
  }

  /// Check if SMS permissions are granted
  Future<bool> hasPermissions() async {
    // Try native bridge first for Android
    if (Platform.isAndroid && _nativeBridgeInitialized) {
      return await _nativeBridge.hasPermissions();
    }

    // Fallback to permission_handler
    return await Permission.sms.isGranted;
  }

  /// Send SMS for a queued request.
  ///
  /// TRANSFER commands are routed to [TransactionSmsService] which sends to
  /// the Twilio number using the format adapted from [buildSMSMessage]:
  ///   T#<transactionId>#<amount>#<recipientPhone>#<pin>
  ///
  /// All other commands use [buildSMSMessage] and send to [_gatewayNumber].
  ///
  /// Returns [SMSSendResult] with success status and the SMS text that was sent.
  Future<SMSSendResult> sendSMS(QueuedRequest request) async {
    Logger.info('[SMSGateway] sendSMS — request: $request');
    if (!Platform.isAndroid || !_nativeBridgeInitialized) {
      Logger.warning('[SMSGateway] SMS sending only supported on Android');
      final preview = buildSMSMessage(request);
      return SMSSendResult(success: false, smsText: preview);
    }

    // All other commands → buildSMSMessage + gateway number
    final message = buildSMSMessage(request);
    Logger.info('[SMSGateway] Sending: $message → $_gatewayNumber');

    try {
      if (message.length > maxSMSLength) {
        Logger.error('[SMSGateway] Message too long: ${message.length} chars');
        return SMSSendResult(success: false, smsText: message);
      }

      Logger.info('_gatewayNumber: $_gatewayNumber');
      Logger.info('_gatewayNumbermessage: $message');
      final success = await _nativeBridge.sendSMS(_gatewayNumber, message);
      //final success = null;
      if (success) {
        Logger.info('[SMSGateway] SMS sent successfully');
      } else {
        Logger.warning('[SMSGateway] SMS send failed');
      }
      return SMSSendResult(success: success, smsText: message);
    } catch (e, stackTrace) {
      Logger.error('[SMSGateway] Failed to send SMS', e, stackTrace);
      return SMSSendResult(success: false, smsText: message);
    }
  }

  /// Build SMS message from a queued request
  /// Format: CMD#transactionId#amount#toUserId#pin
  /// Example: T#TXN1707123456#5000#22660766010#22655000961#123456
  String buildSMSMessage(QueuedRequest request) {
    final command = _extractCommand(request);
    final transactionId = _generateTransactionId();
    final body = request.request.body;
    Logger.info('[SMSGateway] buildSMSMessage — command: $command, transactionId: $transactionId, body: $body');

    switch (command) {
      case 'TRANSFER':
        final amount = body?['amount']?.toString() ?? '0';
        final from = body?['from']?.toString() ?? '';
        final to = body?['to']?.toString() ?? '';
        final pin = body?['pin']?.toString() ?? '';
        return 'T#$transactionId#$amount#$from#$to#$pin';

      case 'PAYMENT':
        final amount = body?['amount']?.toString() ?? '0';
        final merchantId = body?['merchantId']?.toString() ?? '';
        final pin = body?['pin']?.toString() ?? '';
        return 'P#$transactionId#$amount#$merchantId#$pin';

      case 'BALANCE':
        // Balance params are in URL query string (GET request, no body)
        // e.g. /api/transactions/balance?phone=+226...&pin=123456
        final uri = Uri.tryParse(request.request.url);
        final phone = uri?.queryParameters['phone'] ?? body?['phone']?.toString() ?? '';
        final pin = uri?.queryParameters['pin'] ?? body?['pin']?.toString() ?? '';
        Logger.info('[SMSGateway] BALANCE — phone: $phone, pin empty: ${pin.isEmpty}');
        return 'B#$transactionId#$phone#$pin';

      default:
        return 'V#$transactionId';
    }
  }

  /// Generate a unique transaction ID: TXN + timestamp
  String _generateTransactionId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'TXN$now';
  }

  /// Parse incoming SMS response from server.
  ///
  /// Converts the compressed plain-text SMS format into a [Response] whose
  /// [Response.body] is a JSON string of [SmsResponse.toJson].
  Response parseResponse(String smsBody) {
    try {
      final parsed = SmsResponse.parse(smsBody);

      if (parsed == null) {
        Logger.warning('[SMSGateway] Unrecognised SMS response: $smsBody');
        return Response(
          statusCode: 400,
          body: jsonEncode({'error': 'PROCESSING_FAILED', 'raw': smsBody}),
          isFromSMS: true,
        );
      }

      Logger.info('[SMSGateway] Parsed SMS response: $parsed');

      return Response(
        statusCode: parsed.httpStatusCode,
        body: jsonEncode(parsed.toJson()),
        isFromSMS: true,
      );
    } catch (e) {
      Logger.error('Failed to parse SMS response', e);
      return Response(
        statusCode: 500,
        body: jsonEncode({'error': 'PROCESSING_FAILED', 'raw': smsBody}),
        isFromSMS: true,
      );
    }
  }

  /// Listen for incoming SMS responses (already parsed)
  Stream<Response> listenForResponses() {
    return _responseController.stream;
  }

  /// Extract command from request URL
  String _extractCommand(QueuedRequest request) {
    final url = request.request.url.toLowerCase();
    if (url.contains('transfer')) return 'TRANSFER';
    if (url.contains('payment')) return 'PAYMENT';
    if (url.contains('balance')) return 'BALANCE';
    return 'VERIFY';
  }

  /// Dispose resources
  void dispose() {
    _responseController.close();
    if (_nativeBridgeInitialized) {
      _nativeBridge.dispose();
    }
  }
}
