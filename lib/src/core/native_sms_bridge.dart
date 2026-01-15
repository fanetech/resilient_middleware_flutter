/// Native SMS bridge for Android platform communication
library;

import 'dart:async';
import 'package:flutter/services.dart';
import '../utils/logger.dart';

/// Native SMS Bridge for communicating with Android SMS functionality
class NativeSMSBridge {
  static final NativeSMSBridge _instance = NativeSMSBridge._internal();
  factory NativeSMSBridge() => _instance;
  NativeSMSBridge._internal();

  // Method channel for SMS operations
  static const MethodChannel _methodChannel =
      MethodChannel('com.resilient.middleware/sms');

  // Event channel for receiving incoming SMS
  static const EventChannel _eventChannel =
      EventChannel('com.resilient.middleware/sms_receiver');

  StreamSubscription<dynamic>? _smsSubscription;
  final StreamController<Map<String, dynamic>> _incomingController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of incoming SMS messages
  Stream<Map<String, dynamic>> get incomingMessages =>
      _incomingController.stream;

  /// Initialize SMS receiver
  Future<void> initialize() async {
    try {
      // Listen to incoming SMS
      _smsSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Map<dynamic, dynamic>) {
            final messages = event['messages'] as List<dynamic>?;
            if (messages != null && messages.isNotEmpty) {
              for (final message in messages) {
                if (message is Map<dynamic, dynamic>) {
                  final smsData = Map<String, dynamic>.from(message);
                  _incomingController.add(smsData);
                  Logger.info('SMS received from: ${smsData['address']}');
                }
              }
            }
          }
        },
        onError: (dynamic error) {
          Logger.error('Error receiving SMS', error);
        },
      );

      Logger.info('Native SMS bridge initialized');
    } catch (e) {
      Logger.error('Failed to initialize native SMS bridge', e);
    }
  }

  /// Send SMS via native Android bridge
  Future<bool> sendSMS(String phoneNumber, String message) async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'sendSMS',
        {
          'phoneNumber': phoneNumber,
          'message': message,
        },
      );

      if (result != null && result['success'] == true) {
        Logger.info('Native SMS sent successfully to $phoneNumber');
        return true;
      }

      return false;
    } on PlatformException catch (e) {
      Logger.error(
        'Platform exception sending SMS: ${e.code}',
        e.message,
      );
      return false;
    } catch (e) {
      Logger.error('Failed to send SMS via native bridge', e);
      return false;
    }
  }

  /// Check if SMS permissions are granted
  Future<bool> hasPermissions() async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'checkPermissions',
      );

      if (result != null) {
        return result['granted'] == true;
      }

      return false;
    } catch (e) {
      Logger.error('Failed to check SMS permissions', e);
      return false;
    }
  }

  /// Request SMS permissions
  Future<bool> requestPermissions() async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'requestPermissions',
      );

      if (result != null) {
        final granted = result['granted'] == true;
        if (granted) {
          Logger.info('Native SMS permissions granted');
        } else {
          Logger.warning('Native SMS permissions denied');
        }
        return granted;
      }

      return false;
    } on PlatformException catch (e) {
      Logger.error(
        'Platform exception requesting permissions: ${e.code}',
        e.message,
      );
      return false;
    } catch (e) {
      Logger.error('Failed to request SMS permissions', e);
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _smsSubscription?.cancel();
    _smsSubscription = null;
    _incomingController.close();
  }
}
