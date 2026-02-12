/// API Models for Resilient SMS Server
library;

/// Generic API Response wrapper
class ApiResponse<T> {
  final String status;
  final T? data;
  final String? code;
  final String? message;
  final String? queuedRequestId;
  final Map<String, dynamic>? errorData;

  ApiResponse._({
    required this.status,
    this.data,
    this.code,
    this.message,
    this.queuedRequestId,
    this.errorData,
  });

  /// Success response
  factory ApiResponse.success(T data) {
    return ApiResponse._(status: 'success', data: data);
  }

  /// Error response
  factory ApiResponse.error(String code, String? message, {Map<String, dynamic>? data}) {
    return ApiResponse._(
      status: 'error',
      code: code,
      message: message,
      errorData: data,
    );
  }

  /// Queued response (request queued for later processing)
  factory ApiResponse.queued(String requestId) {
    return ApiResponse._(
      status: 'queued',
      queuedRequestId: requestId,
      message: 'Request queued for processing',
    );
  }

  bool get isSuccess => status == 'success';
  bool get isError => status == 'error';
  bool get isQueued => status == 'queued';
}

/// Health check response
class HealthData {
  final String status;
  final String timestamp;
  final String version;
  final String database;
  final int users;
  final int transactions;
  final int totalVolume;

  HealthData({
    required this.status,
    required this.timestamp,
    required this.version,
    required this.database,
    required this.users,
    required this.transactions,
    required this.totalVolume,
  });

  factory HealthData.fromJson(Map<String, dynamic> json) {
    return HealthData(
      status: json['status'] ?? 'unknown',
      timestamp: json['timestamp'] ?? '',
      version: json['version'] ?? '1.0.0',
      database: json['database'] ?? '',
      users: json['stats']?['users'] ?? 0,
      transactions: json['stats']?['transactions'] ?? 0,
      totalVolume: json['stats']?['totalVolume'] ?? 0,
    );
  }
}

/// User model
class User {
  final String userId;
  final String? name;
  final String? phone;
  final int balance;
  final String? formattedBalance;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  User({
    required this.userId,
    this.name,
    this.phone,
    required this.balance,
    this.formattedBalance,
    this.createdAt,
    this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: json['userId'],
      name: json['name'],
      phone: json['phone'],
      balance: json['balance'] ?? 0,
      formattedBalance: json['formattedBalance'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'name': name,
    'phone': phone,
    'balance': balance,
    'formattedBalance': formattedBalance,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };
}

/// Login response
class LoginResponse {
  final String userId;
  final String? name;
  final String? phone;
  final int balance;
  final String? formattedBalance;
  final String token;

  LoginResponse({
    required this.userId,
    this.name,
    this.phone,
    required this.balance,
    this.formattedBalance,
    required this.token,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      userId: json['userId'],
      name: json['name'],
      phone: json['phone'],
      balance: json['balance'] ?? 0,
      formattedBalance: json['formattedBalance'],
      token: json['token'],
    );
  }
}

/// Transfer result
class TransferResult {
  final String transactionId;
  final String type;
  final int amount;
  final String? fromUserId;
  final String? toUserId;
  final int newBalance;
  final String? formattedBalance;
  final String transactionRef;
  final DateTime? createdAt;
  final bool fromSMS;

  TransferResult({
    required this.transactionId,
    required this.type,
    required this.amount,
    this.fromUserId,
    this.toUserId,
    required this.newBalance,
    this.formattedBalance,
    required this.transactionRef,
    this.createdAt,
    this.fromSMS = false,
  });

  factory TransferResult.fromJson(Map<String, dynamic> json) {
    return TransferResult(
      transactionId: json['transactionId'],
      type: json['type'],
      amount: json['amount'] ?? 0,
      fromUserId: json['fromUserId'],
      toUserId: json['toUserId'],
      newBalance: json['newBalance'] ?? 0,
      formattedBalance: json['formattedBalance'],
      transactionRef: json['transactionRef'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
    );
  }
}

/// Payment result
class PaymentResult {
  final String transactionId;
  final String type;
  final int amount;
  final String? fromUserId;
  final String? merchantId;
  final int? newBalance;
  final String? formattedBalance;
  final String transactionRef;
  final DateTime? createdAt;
  final bool fromSMS;

  PaymentResult({
    required this.transactionId,
    required this.type,
    required this.amount,
    this.fromUserId,
    this.merchantId,
    this.newBalance,
    this.formattedBalance,
    required this.transactionRef,
    this.createdAt,
    this.fromSMS = false,
  });

  factory PaymentResult.fromJson(Map<String, dynamic> json) {
    return PaymentResult(
      transactionId: json['transactionId'],
      type: json['type'],
      amount: json['amount'] ?? 0,
      fromUserId: json['fromUserId'],
      merchantId: json['merchantId'],
      newBalance: json['newBalance'],
      formattedBalance: json['formattedBalance'],
      transactionRef: json['transactionRef'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
    );
  }
}

/// Balance result
class BalanceResult {
  final String userId;
  final int balance;
  final String? formattedBalance;
  final int credit;
  final DateTime? lastUpdated;
  final bool fromSMS;

  BalanceResult({
    required this.userId,
    required this.balance,
    this.formattedBalance,
    this.credit = 0,
    this.lastUpdated,
    this.fromSMS = false,
  });

  factory BalanceResult.fromJson(Map<String, dynamic> json) {
    return BalanceResult(
      userId: json['userId'],
      balance: json['balance'] ?? 0,
      formattedBalance: json['formattedBalance'],
      credit: json['credit'] ?? 0,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'])
          : null,
    );
  }
}

/// Transaction model
class Transaction {
  final String transactionId;
  final String type;
  final int? amount;
  final String? formattedAmount;
  final String status;
  final String fromUserId;
  final String? toUserId;
  final String? smsText;
  final String? responseText;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? completedAt;

  Transaction({
    required this.transactionId,
    required this.type,
    this.amount,
    this.formattedAmount,
    required this.status,
    required this.fromUserId,
    this.toUserId,
    this.smsText,
    this.responseText,
    this.errorMessage,
    required this.createdAt,
    this.completedAt,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      transactionId: json['transactionId'],
      type: json['type'],
      amount: json['amount'],
      formattedAmount: json['formattedAmount'],
      status: json['status'],
      fromUserId: json['fromUserId'],
      toUserId: json['toUserId'],
      smsText: json['smsText'],
      responseText: json['responseText'],
      errorMessage: json['errorMessage'],
      createdAt: DateTime.parse(json['createdAt']),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
    );
  }

  bool get isTransfer => type == 'TRANSFER';
  bool get isPayment => type == 'PAYMENT';
  bool get isBalance => type == 'BALANCE';
  bool get isCompleted => status == 'COMPLETED';
  bool get isPending => status == 'PENDING';
  bool get isFailed => status == 'FAILED';
}

/// Transaction history response
class TransactionHistory {
  final List<Transaction> transactions;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;

  TransactionHistory({
    required this.transactions,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  factory TransactionHistory.fromJson(Map<String, dynamic> json) {
    return TransactionHistory(
      transactions: (json['transactions'] as List)
          .map((t) => Transaction.fromJson(t))
          .toList(),
      total: json['pagination']?['total'] ?? 0,
      limit: json['pagination']?['limit'] ?? 20,
      offset: json['pagination']?['offset'] ?? 0,
      hasMore: json['pagination']?['hasMore'] ?? false,
    );
  }
}

/// Transaction types enum
enum TransactionType {
  transfer,
  payment,
  balance;

  String get value {
    switch (this) {
      case TransactionType.transfer:
        return 'TRANSFER';
      case TransactionType.payment:
        return 'PAYMENT';
      case TransactionType.balance:
        return 'BALANCE';
    }
  }

  static TransactionType fromString(String value) {
    switch (value.toUpperCase()) {
      case 'TRANSFER':
        return TransactionType.transfer;
      case 'PAYMENT':
        return TransactionType.payment;
      case 'BALANCE':
        return TransactionType.balance;
      default:
        return TransactionType.transfer;
    }
  }
}

/// Transaction status enum
enum TransactionStatus {
  pending,
  completed,
  failed,
  cancelled;

  String get value {
    switch (this) {
      case TransactionStatus.pending:
        return 'PENDING';
      case TransactionStatus.completed:
        return 'COMPLETED';
      case TransactionStatus.failed:
        return 'FAILED';
      case TransactionStatus.cancelled:
        return 'CANCELLED';
    }
  }

  static TransactionStatus fromString(String value) {
    switch (value.toUpperCase()) {
      case 'PENDING':
        return TransactionStatus.pending;
      case 'COMPLETED':
        return TransactionStatus.completed;
      case 'FAILED':
        return TransactionStatus.failed;
      case 'CANCELLED':
        return TransactionStatus.cancelled;
      default:
        return TransactionStatus.pending;
    }
  }
}

/// Error codes
class ApiErrorCodes {
  static const String missingFields = 'MISSING_FIELDS';
  static const String invalidPin = 'INVALID_PIN';
  static const String invalidPinFormat = 'INVALID_PIN_FORMAT';
  static const String userNotFound = 'USER_NOT_FOUND';
  static const String phoneExists = 'PHONE_EXISTS';
  static const String insufficientFunds = 'INSUFFICIENT_FUNDS';
  static const String dailyLimitExceeded = 'DAILY_LIMIT_EXCEEDED';
  static const String invalidCredentials = 'INVALID_CREDENTIALS';
  static const String transactionNotFound = 'TRANSACTION_NOT_FOUND';
  static const String networkError = 'NETWORK_ERROR';
  static const String smsParseError = 'SMS_PARSE_ERROR';
  static const String unauthorized = 'UNAUTHORIZED';
  static const String forbidden = 'FORBIDDEN';
}
