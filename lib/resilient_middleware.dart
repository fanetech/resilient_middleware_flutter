/// Resilient Middleware - Automatic network failure handling for Flutter
///
/// A Flutter plugin that automatically handles network failures by implementing
/// a triple-channel communication system: Internet → Local Queue → SMS Fallback
///
/// ## Features
/// - Automatic network detection and quality assessment
/// - Local queue management with SQLite for offline requests
/// - SMS fallback when internet is unavailable for critical transactions
/// - Automatic retry with exponential backoff
/// - Zero-config integration
///
/// ## Quick Start
/// ```dart
/// // 1. Initialize in your main.dart
/// await ResilientMiddleware.initialize(
///   smsGateway: '+22670000000',
///   enableSMS: true,
///   strategy: ResilienceStrategy.balanced,
/// );
///
/// // 2. Use ResilientHttp instead of http package
/// final response = await ResilientHttp.post(
///   'https://api.example.com/transfer',
///   body: {'amount': 5000, 'recipient': 'USER123'},
///   priority: Priority.high,
///   smsEligible: true,
/// );
///
/// // 3. Handle response
/// if (response.isSuccess) {
///   if (response.isFromSMS) {
///     print('Transaction completed via SMS');
///   } else if (response.isFromCache) {
///     print('Transaction queued for processing');
///   } else {
///     print('Transaction completed successfully');
///   }
/// }
/// ```
///
/// ## Advanced Configuration
/// ```dart
/// ResilientMiddleware.configure(
///   strategy: ResilienceStrategy.aggressive,
///   smsTimeout: Duration(minutes: 3),
///   smsCostWarning: true,
///   maxQueueSize: 1000,
/// );
/// ```
library resilient_middleware;

// Core API
export 'src/core/resilient_api.dart';
export 'src/core/network_detector.dart';
export 'src/core/queue_manager.dart';
export 'src/core/sms_gateway.dart';
export 'src/core/native_sms_bridge.dart';

// Models
export 'src/models/request_model.dart';
export 'src/models/response_model.dart';
export 'src/models/queue_item.dart';

// Utils
export 'src/utils/logger.dart';
export 'src/utils/sms_compressor.dart';

// Database
export 'src/database/offline_database.dart';

import 'dart:convert';
import 'src/core/resilient_api.dart';
import 'src/models/request_model.dart';
import 'src/models/response_model.dart';

/// Simple HTTP client wrapper with resilience
class ResilientHttp {
  /// GET request with resilience
  static Future<Response> get(
    String url, {
    Map<String, String>? headers,
    Priority priority = Priority.normal,
    bool smsEligible = false,
    String? idempotencyKey,
  }) async {
    final request = Request(
      method: 'GET',
      url: url,
      headers: headers,
      priority: priority,
      smsEligible: smsEligible,
      idempotencyKey: idempotencyKey,
    );

    return await ResilientMiddleware().execute(request);
  }

  /// POST request with resilience
  static Future<Response> post(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    Priority priority = Priority.normal,
    bool smsEligible = false,
    String? idempotencyKey,
  }) async {
    // Add content-type header if not present
    final finalHeaders = headers ?? {};
    if (!finalHeaders.containsKey('Content-Type')) {
      finalHeaders['Content-Type'] = 'application/json';
    }

    final request = Request(
      method: 'POST',
      url: url,
      headers: finalHeaders,
      body: body,
      priority: priority,
      smsEligible: smsEligible,
      idempotencyKey: idempotencyKey,
    );

    return await ResilientMiddleware().execute(request);
  }

  /// PUT request with resilience
  static Future<Response> put(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    Priority priority = Priority.normal,
    bool smsEligible = false,
    String? idempotencyKey,
  }) async {
    // Add content-type header if not present
    final finalHeaders = headers ?? {};
    if (!finalHeaders.containsKey('Content-Type')) {
      finalHeaders['Content-Type'] = 'application/json';
    }

    final request = Request(
      method: 'PUT',
      url: url,
      headers: finalHeaders,
      body: body,
      priority: priority,
      smsEligible: smsEligible,
      idempotencyKey: idempotencyKey,
    );

    return await ResilientMiddleware().execute(request);
  }

  /// DELETE request with resilience
  static Future<Response> delete(
    String url, {
    Map<String, String>? headers,
    Priority priority = Priority.normal,
    bool smsEligible = false,
    String? idempotencyKey,
  }) async {
    final request = Request(
      method: 'DELETE',
      url: url,
      headers: headers,
      priority: priority,
      smsEligible: smsEligible,
      idempotencyKey: idempotencyKey,
    );

    return await ResilientMiddleware().execute(request);
  }

  /// Decode JSON response body
  static Map<String, dynamic> parseJson(Response response) {
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
