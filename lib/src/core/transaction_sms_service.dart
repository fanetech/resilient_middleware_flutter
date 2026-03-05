/// Transaction SMS Service - sends financial transaction SMS via Twilio
library;

import 'native_sms_bridge.dart';
import '../utils/logger.dart';

/// Result of a transfer SMS operation: success flag + raw SMS text that was sent
typedef TransferSmsResult = ({bool success, String message});

/// Service responsible for sending financial transaction SMS messages via Twilio.
///
/// SMS format (adapted from SMSGateway.buildSMSMessage TRANSFER case):
///   T#<transactionId>#<amount>#<recipientPhone>#<pin>
///
/// Example: T#TXN1707123456789#5000#+22676543211#123456
class TransactionSmsService {
  static final TransactionSmsService _instance = TransactionSmsService._internal();
  factory TransactionSmsService() => _instance;
  TransactionSmsService._internal();

  /// Twilio number that receives transaction SMS on the backend
  static const String twilioNumber = '+16615184543';

  final NativeSMSBridge _bridge = NativeSMSBridge();

  /// Generate a unique transaction ID: TXN + current timestamp in milliseconds
  String generateTransactionId() => 'TXN${DateTime.now().millisecondsSinceEpoch}';

  /// Send a transfer SMS to the Twilio number.
  ///
  /// Builds the message using the same format as [SMSGateway.buildSMSMessage]
  /// for the TRANSFER command: T#<transactionId>#<amount>#<recipientPhone>#<pin>
  ///
  /// Returns [TransferSmsResult] with the success flag and the raw SMS text sent.
  Future<TransferSmsResult> sendTransfer({
    required String transactionId,
    required double amount,
    required String recipientPhone,
    required String pin,
  }) async {
    final message = 'T#$transactionId#${amount.toInt()}#$recipientPhone#$pin';
    Logger.info('[TransactionSmsService] Sending: $message → $twilioNumber');
    final success = await _bridge.sendSMS(twilioNumber, message);
    if (success) {
      Logger.info('[TransactionSmsService] Transfer SMS sent successfully');
    } else {
      Logger.warning('[TransactionSmsService] Transfer SMS failed');
    }
    return (success: success, message: message);
  }
}
