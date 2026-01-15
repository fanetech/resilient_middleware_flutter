/// SMS gateway for fallback communication
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart';
import '../models/queue_item.dart';
import '../models/response_model.dart';
import '../utils/sms_compressor.dart';
import '../utils/logger.dart';
import 'native_sms_bridge.dart';

/// SMS Gateway for fallback communication
class SMSGateway {
  static final SMSGateway _instance = SMSGateway._internal();
  factory SMSGateway() => _instance;
  SMSGateway._internal();

  static const String defaultGatewayNumber = '+22670000000';
  String _gatewayNumber = defaultGatewayNumber;

  final StreamController<String> _responseController =
      StreamController<String>.broadcast();

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
            _responseController.add(body);
            Logger.info('Incoming SMS response: $body');
          }
        });

        Logger.info('Native SMS bridge initialized for Android');
      }
    } catch (e) {
      Logger.error('Failed to initialize SMS gateway', e);
    }
  }

  /// Set gateway number
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

  /// Send SMS for a queued request
  Future<bool> sendSMS(QueuedRequest request) async {
    try {
      // Check permissions
      if (!await hasPermissions()) {
        Logger.warning('SMS permissions not granted');
        return false;
      }

      // Compress request
      final message = compressRequest(request);

      // Validate message length
      if (!SMSCompressor.isValidLength(message)) {
        Logger.error('SMS message exceeds 160 characters: ${message.length}');
        return false;
      }

      // Send SMS using native bridge (Android only)
      if (!Platform.isAndroid || !_nativeBridgeInitialized) {
        Logger.warning('SMS sending only supported on Android');
        return false;
      }

      // Use native bridge for Android
      final success = await _nativeBridge.sendSMS(_gatewayNumber, message);

      if (success) {
        Logger.info('SMS sent successfully: $message');
      }

      return success;
    } catch (e, stackTrace) {
      Logger.error('Failed to send SMS', e, stackTrace);
      return false;
    }
  }

  /// Compress request to SMS format
  String compressRequest(QueuedRequest request) {
    // Extract relevant data from request
    // This is a simplified version - actual implementation will depend on request structure

    final data = <String, dynamic>{
      'command': _extractCommand(request),
      'id': request.id,
      'amount': _extractAmount(request),
      'user': _extractUser(request),
      'auth': _extractAuth(request),
    };

    return SMSCompressor.compress(data);
  }

  /// Parse SMS response
  Response parseResponse(String smsBody) {
    try {
      final data = SMSCompressor.decompress(smsBody);

      // Check if success or error
      if (smsBody.startsWith('OK#')) {
        return Response(
          statusCode: 200,
          body: data.toString(),
          isFromSMS: true,
        );
      } else if (smsBody.startsWith('ERR#')) {
        return Response(
          statusCode: 400,
          body: data.toString(),
          isFromSMS: true,
        );
      }

      return Response(
        statusCode: 200,
        body: smsBody,
        isFromSMS: true,
      );
    } catch (e) {
      Logger.error('Failed to parse SMS response', e);
      return Response(
        statusCode: 500,
        body: 'Failed to parse SMS response',
        isFromSMS: true,
      );
    }
  }

  /// Listen for SMS responses
  Stream<String> listenForResponses() {
    // TODO: Implement SMS receiver for incoming messages
    // This will be implemented with native Android code in Step 6
    return _responseController.stream;
  }

  /// Extract command from request
  String _extractCommand(QueuedRequest request) {
    // TODO: Implement command extraction based on URL/method
    // This is a placeholder
    if (request.request.url.contains('transfer')) return 'TRANSFER';
    if (request.request.url.contains('payment')) return 'PAYMENT';
    if (request.request.url.contains('balance')) return 'BALANCE';
    return 'VERIFY';
  }

  /// Extract amount from request body
  String _extractAmount(QueuedRequest request) {
    // TODO: Extract from request body
    return '';
  }

  /// Extract user from request body
  String _extractUser(QueuedRequest request) {
    // TODO: Extract from request body
    return '';
  }

  /// Extract auth from request body
  String _extractAuth(QueuedRequest request) {
    // TODO: Extract from request body
    return '';
  }

  /// Dispose resources
  void dispose() {
    _responseController.close();
    if (_nativeBridgeInitialized) {
      _nativeBridge.dispose();
    }
  }
}
