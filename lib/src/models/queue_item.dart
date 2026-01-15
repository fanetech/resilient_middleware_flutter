/// Queue item model for offline request storage
library;

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
      'headers': request.headers != null ?
          request.headers.toString() : null,
      'body': request.body != null ?
          request.body.toString() : null,
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

  factory QueuedRequest.fromJson(Map<String, dynamic> json) {
    return QueuedRequest(
      id: json['id'] as String,
      request: Request(
        method: json['method'] as String,
        url: json['url'] as String,
        headers: json['headers'] != null
            ? Map<String, String>.from(json['headers'] as Map)
            : null,
        body: json['body'] as Map<String, dynamic>?,
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
