/// Queue item model for offline request storage
library;

import 'dart:convert';
import 'request_model.dart';

/// Status of a queued request
enum QueueStatus {
  pending,
  processing,
  completed,
  failed,
  expired,
}

/// Queued request item
class QueuedRequest {
  final String id;
  final Request request;
  final int retryCount;
  final int maxRetries;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final QueueStatus status;

  QueuedRequest({
    required this.id,
    required this.request,
    this.retryCount = 0,
    this.maxRetries = 3,
    required this.createdAt,
    this.expiresAt,
    this.status = QueueStatus.pending,
  });

  /// Check if request has expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Check if max retries reached
  bool get hasReachedMaxRetries => retryCount >= maxRetries;

  /// Create a copy with updated fields
  QueuedRequest copyWith({
    String? id,
    Request? request,
    int? retryCount,
    int? maxRetries,
    DateTime? createdAt,
    DateTime? expiresAt,
    QueueStatus? status,
  }) {
    return QueuedRequest(
      id: id ?? this.id,
      request: request ?? this.request,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'method': request.method,
      'url': request.url,
      'headers': request.headers != null
          ? jsonEncode(request.headers)
          : null,
      'body': request.body != null
          ? jsonEncode(request.body)
          : null,
      'priority': request.priority.value,
      'retry_count': retryCount,
      'max_retries': maxRetries,
      'created_at': createdAt.millisecondsSinceEpoch,
      'expires_at': expiresAt?.millisecondsSinceEpoch,
      'status': status.name,
      'idempotency_key': request.idempotencyKey,
      'sms_eligible': request.smsEligible ? 1 : 0,
    };
  }

  /// Parse a string that could be JSON or Dart Map.toString() format
  static Map<String, String>? _parseMapString(String data) {
    // Try JSON first
    try {
      return Map<String, String>.from(jsonDecode(data) as Map);
    } catch (_) {
      // Fall back to parsing Dart toString format: {key: value, key2: value2}
      return _parseDartMapToString(data);
    }
  }

  /// Parse a string that could be JSON or Dart Map.toString() format (dynamic values)
  static Map<String, dynamic>? _parseMapStringDynamic(String data) {
    // Try JSON first
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      // Fall back to parsing Dart toString format
      final result = _parseDartMapToString(data);
      return result != null ? Map<String, dynamic>.from(result) : null;
    }
  }

  /// Parse Dart's Map.toString() format: {key: value, key2: value2}
  static Map<String, String>? _parseDartMapToString(String data) {
    try {
      // Remove outer braces
      String inner = data.trim();
      if (inner.startsWith('{') && inner.endsWith('}')) {
        inner = inner.substring(1, inner.length - 1);
      }

      if (inner.isEmpty) return {};

      final result = <String, String>{};
      // Split by comma, but be careful with values that might contain commas
      final pairs = inner.split(RegExp(r',\s*(?=[^:]+:)'));

      for (final pair in pairs) {
        final colonIndex = pair.indexOf(':');
        if (colonIndex != -1) {
          final key = pair.substring(0, colonIndex).trim();
          final value = pair.substring(colonIndex + 1).trim();
          result[key] = value;
        }
      }

      return result;
    } catch (_) {
      return null;
    }
  }

  factory QueuedRequest.fromJson(Map<String, dynamic> json) {
    // Parse headers from JSON string or Dart toString format
    Map<String, String>? headers;
    if (json['headers'] != null) {
      final headersData = json['headers'];
      if (headersData is String) {
        headers = _parseMapString(headersData);
      } else if (headersData is Map) {
        headers = Map<String, String>.from(headersData);
      }
    }

    // Parse body from JSON string or Dart toString format
    Map<String, dynamic>? body;
    if (json['body'] != null) {
      final bodyData = json['body'];
      if (bodyData is String) {
        body = _parseMapStringDynamic(bodyData);
      } else if (bodyData is Map) {
        body = Map<String, dynamic>.from(bodyData);
      }
    }

    return QueuedRequest(
      id: json['id'] as String,
      request: Request(
        method: json['method'] as String,
        url: json['url'] as String,
        headers: headers,
        body: body,
        priority: Priority.values.firstWhere(
          (p) => p.value == json['priority'],
          orElse: () => Priority.normal,
        ),
        smsEligible: json['sms_eligible'] == 1,
        idempotencyKey: json['idempotency_key'] as String?,
      ),
      retryCount: json['retry_count'] as int? ?? 0,
      maxRetries: json['max_retries'] as int? ?? 3,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      expiresAt: json['expires_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['expires_at'] as int)
          : null,
      status: QueueStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => QueueStatus.pending,
      ),
    );
  }
}
