/// SMS compression utility for 160 character limit
library;

/// SMS compressor for reducing message size
class SMSCompressor {
  // Command dictionary
  static const Map<String, String> _commandDict = {
    'TRANSFER': 'T',
    'PAYMENT': 'P',
    'BALANCE': 'B',
    'DEPOSIT': 'D',
    'WITHDRAWAL': 'W',
    'VERIFY': 'V',
  };

  static const String separator = '#';
  static const int maxLength = 160;

  /// Compress a message for SMS
  static String compress(Map<String, dynamic> data) {
    final parts = <String>[];

    // Add command
    final command = data['command']?.toString().toUpperCase() ?? '';
    parts.add(_commandDict[command] ?? command);

    // Add transaction ID
    final id = data['id']?.toString() ?? '';
    parts.add(_compressId(id));

    // Add amount
    final amount = data['amount'];
    if (amount != null) {
      parts.add(_compressAmount(amount));
    } else {
      parts.add('');
    }

    // Add user/recipient
    final user = data['user']?.toString() ?? '';
    parts.add(_compressId(user));

    // Add auth code
    final auth = data['auth']?.toString() ?? '';
    parts.add(auth);

    final compressed = parts.join(separator);

    if (compressed.length > maxLength) {
      throw Exception(
        'Compressed message exceeds $maxLength characters: ${compressed.length}',
      );
    }

    return compressed;
  }

  /// Decompress an SMS message
  static Map<String, dynamic> decompress(String message) {
    final parts = message.split(separator);

    if (parts.isEmpty) {
      throw Exception('Invalid SMS format');
    }

    final result = <String, dynamic>{};

    // Decompress command
    if (parts.isNotEmpty) {
      result['command'] = _decompressCommand(parts[0]);
    }

    // Decompress ID
    if (parts.length > 1) {
      result['id'] = parts[1];
    }

    // Decompress amount
    if (parts.length > 2 && parts[2].isNotEmpty) {
      result['amount'] = _decompressAmount(parts[2]);
    }

    // Decompress user
    if (parts.length > 3) {
      result['user'] = parts[3];
    }

    // Decompress auth
    if (parts.length > 4) {
      result['auth'] = parts[4];
    }

    return result;
  }

  /// Compress amount (e.g., 1000 → 1K, 50000 → 50K, 1500000 → 1.5M)
  static String _compressAmount(dynamic amount) {
    final value = amount is String ? double.parse(amount) : amount.toDouble();

    if (value >= 1000000) {
      final millions = value / 1000000;
      return millions % 1 == 0
          ? '${millions.toInt()}M'
          : '${millions.toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      final thousands = value / 1000;
      return thousands % 1 == 0
          ? '${thousands.toInt()}K'
          : '${thousands.toStringAsFixed(1)}K';
    } else {
      return value.toInt().toString();
    }
  }

  /// Decompress amount (e.g., 1K → 1000, 1.5M → 1500000)
  static double _decompressAmount(String compressed) {
    if (compressed.endsWith('M')) {
      final value = double.parse(compressed.substring(0, compressed.length - 1));
      return value * 1000000;
    } else if (compressed.endsWith('K')) {
      final value = double.parse(compressed.substring(0, compressed.length - 1));
      return value * 1000;
    } else {
      return double.parse(compressed);
    }
  }

  /// Compress ID (e.g., USER123456 → U3456, MERCHANT789012 → M9012)
  static String _compressId(String id) {
    if (id.isEmpty) return '';

    // Extract prefix and numeric part
    final match = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(id.toUpperCase());

    if (match != null) {
      final prefix = match.group(1)![0]; // First letter
      final number = match.group(2)!;
      // Take last 4 digits
      final lastDigits = number.length > 4
          ? number.substring(number.length - 4)
          : number;
      return '$prefix$lastDigits';
    }

    // If no match, return last 6 characters
    return id.length > 6 ? id.substring(id.length - 6) : id;
  }

  /// Decompress command
  static String _decompressCommand(String compressed) {
    for (final entry in _commandDict.entries) {
      if (entry.value == compressed) {
        return entry.key;
      }
    }
    return compressed;
  }

  /// Validate message length
  static bool isValidLength(String message) {
    return message.length <= maxLength;
  }

  /// Get estimated compression ratio
  static double getCompressionRatio(String original, String compressed) {
    if (original.isEmpty) return 0;
    return compressed.length / original.length;
  }
}
