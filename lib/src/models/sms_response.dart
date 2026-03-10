/// Parsed SMS response from the resilient SMS server.
library;

/// Represents a fully-parsed server SMS response.
///
/// Format: OK#<txnId>#<fields...>  or  ERR#<txnId>#<ERROR_CODE>#<details...>
/// Amounts are compressed: 50K → 50 000, 1.5M → 1 500 000
class SmsResponse {
  final bool isSuccess;
  final String transactionId;

  // Success fields
  final double? balance;       // BAL:xxx
  final double? amountPaid;    // PAID:xxx
  final double? credit;        // CREDIT:xxx
  final String? transactionRef; // TXN:xxx

  // Error fields
  final String? errorCode;
  final Map<String, dynamic> errorDetails; // optional key:value pairs after error code

  const SmsResponse._({
    required this.isSuccess,
    required this.transactionId,
    this.balance,
    this.amountPaid,
    this.credit,
    this.transactionRef,
    this.errorCode,
    this.errorDetails = const {},
  });

  /// Parse a raw SMS body string into an [SmsResponse].
  ///
  /// Strips any carrier/provider prefix before the actual payload
  /// (e.g. Twilio trial accounts prepend "Sent from your Twilio trial account - ").
  ///
  /// Returns `null` if the string cannot be parsed at all.
  static SmsResponse? parse(String raw) {
    final cleaned = _extractPayload(raw.trim());
    final parts = cleaned.split('#');
    if (parts.length < 2) return null;

    final status = parts[0].toUpperCase();
    final txnId = parts[1];

    if (status == 'OK') {
      double? balance;
      double? amountPaid;
      double? credit;
      String? transactionRef;

      for (var i = 2; i < parts.length; i++) {
        final kv = parts[i].split(':');
        if (kv.length != 2) continue;
        final key = kv[0].toUpperCase();
        final val = kv[1];

        switch (key) {
          case 'BAL':
            balance = _parseAmount(val);
          case 'PAID':
            amountPaid = _parseAmount(val);
          case 'CREDIT':
            credit = _parseAmount(val);
          case 'TXN':
            transactionRef = val;
        }
      }

      return SmsResponse._(
        isSuccess: true,
        transactionId: txnId,
        balance: balance,
        amountPaid: amountPaid,
        credit: credit,
        transactionRef: transactionRef,
      );
    }

    if (status == 'ERR') {
      final errorCode = parts.length > 2 ? parts[2] : 'UNKNOWN';
      final details = <String, dynamic>{};

      // parts[3..] may carry optional key:value pairs (e.g. BAL:10K, LIMIT:1M)
      for (var i = 3; i < parts.length; i++) {
        final kv = parts[i].split(':');
        if (kv.length == 2) {
          final key = kv[0].toUpperCase();
          final val = kv[1];
          // Try to parse as amount; fall back to raw string
          final numeric = _parseAmount(val);
          details[key] = numeric ?? val;
        } else {
          details['detail_$i'] = parts[i];
        }
      }

      return SmsResponse._(
        isSuccess: false,
        transactionId: txnId,
        errorCode: errorCode,
        errorDetails: details,
      );
    }

    return null; // unknown status prefix
  }

  /// Extracts the actual OK#/ERR# payload, stripping any carrier prefix.
  static String _extractPayload(String raw) {
    final okIdx = raw.indexOf('OK#');
    final errIdx = raw.indexOf('ERR#');
    if (okIdx >= 0 && (errIdx < 0 || okIdx < errIdx)) return raw.substring(okIdx);
    if (errIdx >= 0) return raw.substring(errIdx);
    return raw;
  }

  /// Decompress compressed amounts: 50K → 50000, 1.5M → 1500000, 435 → 435
  static double? _parseAmount(String value) {
    if (value.isEmpty) return null;
    try {
      if (value.endsWith('M')) {
        return double.parse(value.substring(0, value.length - 1)) * 1000000;
      } else if (value.endsWith('K')) {
        return double.parse(value.substring(0, value.length - 1)) * 1000;
      } else {
        return double.parse(value);
      }
    } catch (_) {
      return null;
    }
  }

  /// HTTP status code equivalent for this SMS response.
  int get httpStatusCode {
    if (isSuccess) return 200;
    switch (errorCode) {
      case 'USER_NOT_FOUND':
      case 'RECIPIENT_NOT_FOUND':
      case 'MERCHANT_NOT_FOUND':
        return 404;
      case 'INVALID_PIN':
        return 401;
      case 'INSUFFICIENT_FUNDS':
      case 'DAILY_LIMIT_EXCEEDED':
        return 402;
      case 'PROCESSING_FAILED':
        return 400;
      default:
        return 500;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'isSuccess': isSuccess,
      'transactionId': transactionId,
      if (balance != null) 'balance': balance,
      if (amountPaid != null) 'amountPaid': amountPaid,
      if (credit != null) 'credit': credit,
      if (transactionRef != null) 'transactionRef': transactionRef,
      if (errorCode != null) 'errorCode': errorCode,
      if (errorDetails.isNotEmpty) 'errorDetails': errorDetails,
    };
  }

  @override
  String toString() => 'SmsResponse(${toJson()})';
}