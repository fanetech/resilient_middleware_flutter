/// Transaction model for banking demo
class Transaction {
  final String id;
  final String type; // 'sent', 'received'
  final double amount;
  final String recipient;
  final DateTime timestamp;
  final String status; // 'completed', 'pending', 'failed', 'queued', 'sms'
  final bool isFromSMS;

  Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.recipient,
    required this.timestamp,
    required this.status,
    this.isFromSMS = false,
  });

  String get statusDisplay {
    switch (status) {
      case 'completed':
        return '✅ Completed';
      case 'pending':
        return '⏳ Pending';
      case 'failed':
        return '❌ Failed';
      case 'queued':
        return '📦 Queued';
      case 'sms':
        return '📱 Sent via SMS';
      default:
        return status;
    }
  }
}
