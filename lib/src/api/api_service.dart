/// Resilient SMS Server API Service
/// Provides HTTP API calls with automatic SMS fallback via ResilientMiddleware
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:resilient_middleware_flutter/resilient_middleware.dart';
import '../core/resilient_api.dart';
import '../models/request_model.dart';
import 'api_models.dart';

/// Main API Service for Resilient SMS Server
class ResilientApiService {
  static ResilientApiService? _instance;

  final String baseUrl;
  final ResilientMiddleware _middleware = ResilientMiddleware();
  String? _authToken;
  String? _currentUserId;
  String? _currentPhone;
  String? _currentPin;

  /// Callback triggered when session expires (401 unauthorized).
  /// Use this to redirect the user to the login screen.
  void Function()? onSessionExpired;

  ResilientApiService._internal({required this.baseUrl});

  /// Get singleton instance
  static ResilientApiService getInstance({required String baseUrl}) {
    _instance ??= ResilientApiService._internal(baseUrl: baseUrl);
    return _instance!;
  }

  /// Initialize the API service with middleware
  static Future<ResilientApiService> initialize({
    required String baseUrl,
    String? smsGateway,
    bool enableSMS = true,
    ResilienceStrategy strategy = ResilienceStrategy.balanced,
  }) async {
    final instance = getInstance(baseUrl: baseUrl);

    // Initialize middleware
    await ResilientMiddleware.initialize(
      smsGateway: smsGateway,
      enableSMS: enableSMS,
      strategy: strategy,
    );

    return instance;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  /// Set auth token after login
  void setAuthToken(String token) {
    _authToken = token;
  }

  /// Get current user ID
  String? get currentUserId => _currentUserId;

  /// Get current user phone number
  String? get currentPhone => _currentPhone;

  /// Get stored PIN (for authenticated operations like balance check)
  String? get currentPin => _currentPin;

  /// Check if HTTP response indicates an expired/invalid session
  bool _isUnauthorized(int statusCode) {
    if (statusCode == 401) {
      logout();
      onSessionExpired?.call();
      return true;
    }
    return false;
  }

  // ==================== HEALTH CHECK ====================

  /// Check server health
  Future<ApiResponse<HealthData>> healthCheck() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (data['status'] == 'healthy') {
        return ApiResponse.success(HealthData.fromJson(data));
      }
      return ApiResponse.error('SERVER_UNHEALTHY', 'Server is not healthy');
    } catch (e) {
      return ApiResponse.error('NETWORK_ERROR', e.toString());
    }
  }

  // ==================== USER ENDPOINTS ====================

  /// Register a new user
  Future<ApiResponse<User>> register({
    required String phone,
    required String pin,
    String? name,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/users/register'),
        headers: _headers,
        body: jsonEncode({
          'phone': phone,
          'pin': pin,
          if (name != null) 'name': name,
        }),
      );

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        return ApiResponse.success(User.fromJson(data['data']));
      }
      return ApiResponse.error(data['code'] ?? 'UNKNOWN', data['message']);
    } catch (e) {
      return ApiResponse.error('NETWORK_ERROR', e.toString());
    }
  }

  /// Login with phone and PIN
  Future<ApiResponse<LoginResponse>> login({
    required String phone,
    required String pin,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/users/login'),
        headers: _headers,
        body: jsonEncode({
          'phone': phone,
          'pin': pin,
        }),
      );

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        final loginResponse = LoginResponse.fromJson(data['data']);
        _authToken = loginResponse.token;
        _currentUserId = loginResponse.userId;
        _currentPhone = loginResponse.phone;
        _currentPin = pin;
        return ApiResponse.success(loginResponse);
      }
      return ApiResponse.error(data['code'] ?? 'UNKNOWN', data['message']);
    } catch (e) {
      return ApiResponse.error('NETWORK_ERROR', e.toString());
    }
  }

  /// Get user profile
  Future<ApiResponse<User>> getUser(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/$userId'),
        headers: _headers,
      );

      if (_isUnauthorized(response.statusCode)) {
        return ApiResponse.error('UNAUTHORIZED', 'Session expired');
      }

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        return ApiResponse.success(User.fromJson(data['data']));
      }
      return ApiResponse.error(data['code'] ?? 'UNKNOWN', data['message']);
    } catch (e) {
      return ApiResponse.error('NETWORK_ERROR', e.toString());
    }
  }

  /// Change user PIN
  Future<ApiResponse<void>> changePin({
    required String userId,
    required String currentPin,
    required String newPin,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/users/$userId/pin'),
        headers: _headers,
        body: jsonEncode({
          'currentPin': currentPin,
          'newPin': newPin,
        }),
      );

      if (_isUnauthorized(response.statusCode)) {
        return ApiResponse.error('UNAUTHORIZED', 'Session expired');
      }

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        _currentPin = newPin;
        return ApiResponse.success(null);
      }
      return ApiResponse.error(data['code'] ?? 'UNKNOWN', data['message']);
    } catch (e) {
      return ApiResponse.error('NETWORK_ERROR', e.toString());
    }
  }

  /// Reset PIN (forgot PIN flow)
  Future<ApiResponse<void>> resetPin({
    required String name,
    required String phone,
    required String newPin,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/users/reset-pin'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'phone': phone,
          'newPin': newPin,
        }),
      );

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        return ApiResponse.success(null);
      }
      return ApiResponse.error(data['code'] ?? 'UNKNOWN', data['message']);
    } catch (e) {
      return ApiResponse.error('NETWORK_ERROR', e.toString());
    }
  }

  /// Get all users (testing/admin)
  Future<ApiResponse<List<User>>> getAllUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users'),
        headers: _headers,
      );

      if (_isUnauthorized(response.statusCode)) {
        return ApiResponse.error('UNAUTHORIZED', 'Session expired');
      }

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        final users = (data['data']['users'] as List)
            .map((u) => User.fromJson(u))
            .toList();
        return ApiResponse.success(users);
      }
      return ApiResponse.error(data['code'] ?? 'UNKNOWN', data['message']);
    } catch (e) {
      return ApiResponse.error('NETWORK_ERROR', e.toString());
    }
  }

  // ==================== TRANSACTION ENDPOINTS ====================

  /// Transfer money (with SMS fallback)
  Future<ApiResponse<TransferResult>> transfer({
    required String from,
    required String to,
    required int amount,
    required String pin,
    bool useSMSFallback = true,
  }) async {
    if (useSMSFallback && _middleware.isInitialized) {
      return _transferWithFallback(
        from: from,
        to: to,
        amount: amount,
        pin: pin,
      );
    }
    return _transferDirect(
      from: from,
      to: to,
      amount: amount,
      pin: pin,
    );
  }

  /// Direct HTTP transfer
  Future<ApiResponse<TransferResult>> _transferDirect({
    required String from,
    required String to,
    required int amount,
    required String pin,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/transactions/transfer'),
        headers: _headers,
        body: jsonEncode({
          'from': from,
          'to': to,
          'amount': amount,
          'pin': pin,
        }),
      );

      if (_isUnauthorized(response.statusCode)) {
        return ApiResponse.error('UNAUTHORIZED', 'Session expired');
      }

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        return ApiResponse.success(TransferResult.fromJson(data['data']));
      }
      return ApiResponse.error(
        data['code'] ?? 'UNKNOWN',
        data['message'],
        data: data['data'],
      );
    } catch (e) {
      return ApiResponse.error('NETWORK_ERROR', e.toString());
    }
  }

  /// Transfer with SMS fallback via ResilientMiddleware
  Future<ApiResponse<TransferResult>> _transferWithFallback({
    required String from,
    required String to,
    required int amount,
    required String pin,
  }) async {
    Logger.info('in_transferWithFallback ');
    final request = Request(
      method: 'POST',
      url: '$baseUrl/api/transactions/transfer',
      body: {
        'from': from,
        'to': to,
        'amount': amount,
        'pin': pin,
      },
      headers: _headers,
      priority: Priority.critical,
      smsEligible: true,
    );

    final response = await _middleware.execute(request);

    if (response.isFromSMS) {
      // Check if this is a sent confirmation (T#TXN...#amount#user#pin)
      // or an incoming response (OK#ID#BAL:450K#TXN:A7F3B2)
      if (response.body.startsWith('T#')) {
        // SMS was sent - parse the sent SMS text to extract info
        final parts = response.body.split('#');
        return ApiResponse.success(TransferResult(
          transactionId: parts.length > 1 ? parts[1] : 'unknown',
          type: 'TRANSFER',
          amount: parts.length > 2 ? (int.tryParse(parts[2]) ?? amount) : amount,
          toUserId: to,
          newBalance: 0,
          transactionRef: parts.length > 1 ? parts[1] : 'unknown',
          fromSMS: true,
        ));
      }
      // Incoming SMS response from server
      return _parseSMSTransferResponse(response.body);
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        return ApiResponse.success(TransferResult.fromJson(data['data']));
      }
      return ApiResponse.error(data['code'] ?? 'UNKNOWN', data['message']);
    }

    if (response.statusCode == 202) {
      // Request queued
      return ApiResponse.queued(response.requestId ?? 'unknown');
    }

    return ApiResponse.error('REQUEST_FAILED', response.body);
  }

  /// Payment (with SMS fallback)
  Future<ApiResponse<PaymentResult>> payment({
    required String from,
    required String merchantId,
    required int amount,
    required String pin,
    bool useSMSFallback = true,
  }) async {
    if (useSMSFallback && _middleware.isInitialized) {
      return _paymentWithFallback(
        from: from,
        merchantId: merchantId,
        amount: amount,
        pin: pin,
      );
    }
    return _paymentDirect(
      from: from,
      merchantId: merchantId,
      amount: amount,
      pin: pin,
    );
  }

  /// Direct HTTP payment
  Future<ApiResponse<PaymentResult>> _paymentDirect({
    required String from,
    required String merchantId,
    required int amount,
    required String pin,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/transactions/payment'),
        headers: _headers,
        body: jsonEncode({
          'from': from,
          'merchantId': merchantId,
          'amount': amount,
          'pin': pin,
        }),
      );

      if (_isUnauthorized(response.statusCode)) {
        return ApiResponse.error('UNAUTHORIZED', 'Session expired');
      }

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        return ApiResponse.success(PaymentResult.fromJson(data['data']));
      }
      return ApiResponse.error(
        data['code'] ?? 'UNKNOWN',
        data['message'],
        data: data['data'],
      );
    } catch (e) {
      return ApiResponse.error('NETWORK_ERROR', e.toString());
    }
  }

  /// Payment with SMS fallback
  Future<ApiResponse<PaymentResult>> _paymentWithFallback({
    required String from,
    required String merchantId,
    required int amount,
    required String pin,
  }) async {
    final request = Request(
      method: 'POST',
      url: '$baseUrl/api/transactions/payment',
      body: {
        'from': from,
        'merchantId': merchantId,
        'amount': amount,
        'pin': pin,
      },
      headers: _headers,
      priority: Priority.high,
      smsEligible: true,
    );

    final response = await _middleware.execute(request);

    if (response.isFromSMS) {
      if (response.body.startsWith('P#')) {
        final parts = response.body.split('#');
        return ApiResponse.success(PaymentResult(
          transactionId: parts.length > 1 ? parts[1] : 'unknown',
          type: 'PAYMENT',
          amount: parts.length > 2 ? (int.tryParse(parts[2]) ?? amount) : amount,
          merchantId: merchantId,
          transactionRef: parts.length > 1 ? parts[1] : 'unknown',
          fromSMS: true,
        ));
      }
      return _parseSMSPaymentResponse(response.body);
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        return ApiResponse.success(PaymentResult.fromJson(data['data']));
      }
      return ApiResponse.error(data['code'] ?? 'UNKNOWN', data['message']);
    }

    if (response.statusCode == 202) {
      return ApiResponse.queued(response.requestId ?? 'unknown');
    }

    return ApiResponse.error('REQUEST_FAILED', response.body);
  }

  /// Get balance (with SMS fallback - critical priority)
  Future<ApiResponse<BalanceResult>> getBalance({
    required String phone,
    required String pin,
    bool useSMSFallback = true,
  }) async {
    if (useSMSFallback && _middleware.isInitialized) {
      return _getBalanceWithFallback(phone: phone, pin: pin);
    }
    return _getBalanceDirect(phone: phone, pin: pin);
  }

  /// Direct HTTP balance check
  Future<ApiResponse<BalanceResult>> _getBalanceDirect({
    required String phone,
    required String pin,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/transactions/balance?phone=$phone&pin=$pin'),
        headers: _headers,
      );

      if (_isUnauthorized(response.statusCode)) {
        return ApiResponse.error('UNAUTHORIZED', 'Session expired');
      }

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        return ApiResponse.success(BalanceResult.fromJson(data['data']));
      }
      return ApiResponse.error(data['code'] ?? 'UNKNOWN', data['message']);
    } catch (e) {
      return ApiResponse.error('NETWORK_ERROR', e.toString());
    }
  }

  /// Balance check with SMS fallback (critical - immediate SMS if offline)
  Future<ApiResponse<BalanceResult>> _getBalanceWithFallback({
    required String phone,
    required String pin,
  }) async {
    final request = Request(
      method: 'GET',
      url: '$baseUrl/api/transactions/balance?phone=$phone&pin=$pin',
      headers: _headers,
      priority: Priority.critical,
      smsEligible: true,
    );

    final response = await _middleware.execute(request);

    if (response.isFromSMS) {
      if (response.body.startsWith('B#')) {
        // SMS was sent - balance will arrive via response SMS
        return ApiResponse.success(BalanceResult(
          userId: phone,
          balance: 0,
          fromSMS: true,
        ));
      }
      return _parseSMSBalanceResponse(response.body);
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        return ApiResponse.success(BalanceResult.fromJson(data['data']));
      }
      return ApiResponse.error(data['code'] ?? 'UNKNOWN', data['message']);
    }

    if (response.statusCode == 202) {
      return ApiResponse.queued(response.requestId ?? 'unknown');
    }

    return ApiResponse.error('REQUEST_FAILED', response.body);
  }

  /// Get transaction history
  Future<ApiResponse<TransactionHistory>> getHistory({
    required String phone,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/transactions/history?phone=$phone&limit=$limit&offset=$offset'),
        headers: _headers,
      );

      if (_isUnauthorized(response.statusCode)) {
        return ApiResponse.error('UNAUTHORIZED', 'Session expired');
      }

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        return ApiResponse.success(TransactionHistory.fromJson(data['data']));
      }
      return ApiResponse.error(data['code'] ?? 'UNKNOWN', data['message']);
    } catch (e) {
      return ApiResponse.error('NETWORK_ERROR', e.toString());
    }
  }

  /// Get transaction details
  Future<ApiResponse<Transaction>> getTransaction(String transactionId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/transactions/$transactionId'),
        headers: _headers,
      );

      if (_isUnauthorized(response.statusCode)) {
        return ApiResponse.error('UNAUTHORIZED', 'Session expired');
      }

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        return ApiResponse.success(Transaction.fromJson(data['data']));
      }
      return ApiResponse.error(data['code'] ?? 'UNKNOWN', data['message']);
    } catch (e) {
      return ApiResponse.error('NETWORK_ERROR', e.toString());
    }
  }

  // ==================== SMS RESPONSE PARSERS ====================

  /// Parse SMS transfer response: OK#ID#BAL:450K#TXN:A7F3B2
  ApiResponse<TransferResult> _parseSMSTransferResponse(String smsBody) {
    try {
      final parts = smsBody.split('#');

      if (parts[0] == 'OK' && parts.length >= 4) {
        final balPart = parts[2]; // BAL:450K
        final txnPart = parts[3]; // TXN:A7F3B2

        final balance = _parseAmountFromSMS(balPart.replaceFirst('BAL:', ''));
        final txnRef = txnPart.replaceFirst('TXN:', '');

        return ApiResponse.success(TransferResult(
          transactionId: parts[1],
          type: 'TRANSFER',
          amount: 0, // Not included in SMS response
          newBalance: balance,
          transactionRef: txnRef,
          fromSMS: true,
        ));
      }

      if (parts[0] == 'ERR') {
        return ApiResponse.error(parts[2], 'Transaction failed via SMS');
      }

      return ApiResponse.error('SMS_PARSE_ERROR', 'Invalid SMS response format');
    } catch (e) {
      return ApiResponse.error('SMS_PARSE_ERROR', e.toString());
    }
  }

  /// Parse SMS payment response
  ApiResponse<PaymentResult> _parseSMSPaymentResponse(String smsBody) {
    try {
      final parts = smsBody.split('#');

      if (parts[0] == 'OK' && parts.length >= 4) {
        final paidPart = parts[2]; // PAID:15K
        final txnPart = parts[3]; // TXN:B2C4D5

        final paid = _parseAmountFromSMS(paidPart.replaceFirst('PAID:', ''));
        final txnRef = txnPart.replaceFirst('TXN:', '');

        return ApiResponse.success(PaymentResult(
          transactionId: parts[1],
          type: 'PAYMENT',
          amount: paid,
          transactionRef: txnRef,
          fromSMS: true,
        ));
      }

      if (parts[0] == 'ERR') {
        return ApiResponse.error(parts[2], 'Payment failed via SMS');
      }

      return ApiResponse.error('SMS_PARSE_ERROR', 'Invalid SMS response format');
    } catch (e) {
      return ApiResponse.error('SMS_PARSE_ERROR', e.toString());
    }
  }

  /// Parse SMS balance response: OK#ID#BAL:475K#CREDIT:25K
  ApiResponse<BalanceResult> _parseSMSBalanceResponse(String smsBody) {
    try {
      final parts = smsBody.split('#');

      if (parts[0] == 'OK' && parts.length >= 3) {
        final balPart = parts[2]; // BAL:475K
        final creditPart = parts.length > 3 ? parts[3] : 'CREDIT:0';

        final balance = _parseAmountFromSMS(balPart.replaceFirst('BAL:', ''));
        final credit = _parseAmountFromSMS(creditPart.replaceFirst('CREDIT:', ''));

        return ApiResponse.success(BalanceResult(
          userId: parts[1],
          balance: balance,
          credit: credit,
          fromSMS: true,
        ));
      }

      if (parts[0] == 'ERR') {
        return ApiResponse.error(parts[2], 'Balance check failed via SMS');
      }

      return ApiResponse.error('SMS_PARSE_ERROR', 'Invalid SMS response format');
    } catch (e) {
      return ApiResponse.error('SMS_PARSE_ERROR', e.toString());
    }
  }

  /// Parse compressed amount from SMS (50K → 50000, 1.5M → 1500000)
  int _parseAmountFromSMS(String amountStr) {
    final match = RegExp(r'^(\d+(?:\.\d+)?)(K|M)?$', caseSensitive: false)
        .firstMatch(amountStr.trim());

    if (match == null) return 0;

    double amount = double.parse(match.group(1)!);
    final unit = match.group(2)?.toUpperCase();

    if (unit == 'K') amount *= 1000;
    if (unit == 'M') amount *= 1000000;

    return amount.toInt();
  }

  // ==================== UTILITY ====================

  /// Logout - clear auth token and stored data
  void logout() {
    _authToken = null;
    _currentUserId = null;
    _currentPin = null;
  }

  /// Check if user is logged in
  bool get isLoggedIn => _authToken != null;

  /// Get network score from middleware
  Future<double> getNetworkScore() async {
    return await _middleware.getNetworkScore();
  }

  /// Get pending queue count
  Future<int> getQueueCount() async {
    return await _middleware.getQueueCount();
  }

  /// Dispose resources
  void dispose() {
    _middleware.dispose();
  }
}
