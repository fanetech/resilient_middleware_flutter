/// Response model for API calls
library;

/// HTTP Response
class Response {
  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final bool isFromCache;
  final bool isFromSMS;

  Response({
    required this.statusCode,
    required this.body,
    this.headers = const {},
    this.isFromCache = false,
    this.isFromSMS = false,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  Map<String, dynamic> toJson() {
    return {
      'statusCode': statusCode,
      'body': body,
      'headers': headers,
      'isFromCache': isFromCache,
      'isFromSMS': isFromSMS,
    };
  }

  factory Response.fromJson(Map<String, dynamic> json) {
    return Response(
      statusCode: json['statusCode'] as int,
      body: json['body'] as String,
      headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
      isFromCache: json['isFromCache'] as bool? ?? false,
      isFromSMS: json['isFromSMS'] as bool? ?? false,
    );
  }
}
