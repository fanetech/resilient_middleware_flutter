/// Request model for API calls
library;

/// Priority levels for requests
enum Priority {
  critical(10), // Medical, emergency
  high(8), // Payments, transfers
  normal(5), // Updates, posts
  low(3); // Analytics, logs

  const Priority(this.value);
  final int value;
}

/// Request configuration
class Request {
  final String method;
  final String url;
  final Map<String, String>? headers;
  final Map<String, dynamic>? body;
  final Priority priority;
  final bool smsEligible;
  final String? idempotencyKey;
  final Duration? timeout;

  Request({
    required this.method,
    required this.url,
    this.headers,
    this.body,
    this.priority = Priority.normal,
    this.smsEligible = false,
    this.idempotencyKey,
    this.timeout,
  });

  Map<String, dynamic> toJson() {
    return {
      'method': method,
      'url': url,
      'headers': headers,
      'body': body,
      'priority': priority.value,
      'smsEligible': smsEligible ? 1 : 0,
      'idempotencyKey': idempotencyKey,
    };
  }

  factory Request.fromJson(Map<String, dynamic> json) {
    return Request(
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
      smsEligible: json['smsEligible'] == 1,
      idempotencyKey: json['idempotencyKey'] as String?,
    );
  }
}
