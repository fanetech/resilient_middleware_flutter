/// Main Resilient API for automatic network failure handling
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/request_model.dart';
import '../models/response_model.dart';
import '../models/queue_item.dart';
import 'network_detector.dart';
import 'queue_manager.dart';
import 'sms_gateway.dart';
import '../utils/logger.dart';

/// Resilience strategy types
enum ResilienceStrategy {
  aggressive, // Always try network first, quick SMS fallback (1 min)
  balanced, // Smart detection, 5 min wait before SMS
  conservative, // Minimize SMS usage, long waits (15 min)
  custom, // User-defined rules
}

/// SMS cost provider callback for cost warnings
typedef SMSCostProvider = Future<double> Function(String message);

/// Callback for SMS cost warnings
typedef SMSCostWarningCallback = Future<bool> Function(double estimatedCost);

/// Main Resilient Middleware API
class ResilientMiddleware {
  static final ResilientMiddleware _instance = ResilientMiddleware._internal();
  factory ResilientMiddleware() => _instance;
  ResilientMiddleware._internal();

  // Core components
  final NetworkDetector _networkDetector = NetworkDetector();
  final QueueManager _queueManager = QueueManager();
  final SMSGateway _smsGateway = SMSGateway();

  // Configuration
  bool _initialized = false;
  bool _enableSMS = true;
  ResilienceStrategy _strategy = ResilienceStrategy.balanced;
  Duration _smsThreshold = const Duration(minutes: 5);
  Duration _timeout = const Duration(seconds: 30);
  int _maxQueueSize = 1000;
  bool _smsCostWarning = false;
  SMSCostProvider? _smsCostProvider;
  SMSCostWarningCallback? _smsCostWarningCallback;
  bool _batchSMS = false;

  // Queued items waiting for SMS threshold
  final Map<String, Timer> _smsTimers = {};

  // Stream controller for network status updates
  StreamSubscription<NetworkStatus>? _networkSubscription;

  /// Initialize the middleware
  static Future<void> initialize({
    String? smsGateway,
    bool enableSMS = true,
    Duration timeout = const Duration(seconds: 30),
    ResilienceStrategy strategy = ResilienceStrategy.balanced,
    SMSCostProvider? smsCostProvider,
    bool smsCostWarning = false,
    SMSCostWarningCallback? smsCostWarningCallback,
    bool batchSMS = false,
    int maxQueueSize = 1000,
  }) async {
    final instance = ResilientMiddleware();

    if (instance._initialized) {
      Logger.warning('ResilientMiddleware already initialized');
      return;
    }

    // Set configuration
    instance._enableSMS = enableSMS;
    instance._timeout = timeout;
    instance._strategy = strategy;
    instance._maxQueueSize = maxQueueSize;
    instance._smsCostWarning = smsCostWarning;
    instance._smsCostProvider = smsCostProvider;
    instance._smsCostWarningCallback = smsCostWarningCallback;
    instance._batchSMS = batchSMS;

    // Set SMS threshold based on strategy
    instance._smsThreshold = instance._getSMSThresholdForStrategy(strategy);

    if (smsGateway != null) {
      instance._smsGateway.setGatewayNumber(smsGateway);
    }

    // Initialize components
    await instance._networkDetector.initialize();
    await instance._queueManager.initialize();

    // Initialize and request SMS permissions if enabled
    if (enableSMS) {
      await instance._smsGateway.initialize();
      await instance._smsGateway.requestPermissions();
    }

    // Subscribe to network status changes to process queue
    instance._subscribeToNetworkChanges();

    instance._initialized = true;
    Logger.info('ResilientMiddleware initialized successfully with ${strategy.name} strategy');
  }

  /// Get SMS threshold based on strategy
  Duration _getSMSThresholdForStrategy(ResilienceStrategy strategy) {
    switch (strategy) {
      case ResilienceStrategy.aggressive:
        return const Duration(minutes: 1);
      case ResilienceStrategy.balanced:
        return const Duration(minutes: 5);
      case ResilienceStrategy.conservative:
        return const Duration(minutes: 15);
      case ResilienceStrategy.custom:
        return _smsThreshold; // Use custom value
    }
  }

  /// Subscribe to network status changes
  void _subscribeToNetworkChanges() {
    _networkSubscription = _networkDetector.networkStream.listen((status) {
      Logger.debug('Network status changed: ${status.type.name}, score: ${status.qualityScore}');

      // When network becomes available, process the queue
      if (status.isStable && status.qualityScore > 0.5) {
        Logger.info('Network is now stable, processing queue...');
        _queueManager.processQueue();
      }
    });
  }

  /// Execute a request with resilience
  ///
  /// Decision Flow:
  /// 1. Check Network Score
  /// 2. Score > 0.7 → Try HTTP (30s timeout)
  /// 3. Score > 0.3 → Try HTTP (5s timeout)
  /// 4. Score = 0.0 → Is Urgent? → Send SMS Immediately : Queue Request
  /// 5. Wait threshold → Still Offline? → Propose SMS
  Future<Response> execute(Request request) async {
    if (!_initialized) {
      throw Exception('ResilientMiddleware not initialized. Call initialize() first.');
    }

    Logger.info('Executing request: ${request.method} ${request.url} [Priority: ${request.priority.name}]');

    // Get network score
    final networkScore = await _networkDetector.getNetworkScore();
    Logger.debug('Network score: $networkScore');

    // Apply strategy-based decision flow
    return await _applyDecisionFlow(request, networkScore);
  }

  /// Apply decision flow based on network score and strategy
  Future<Response> _applyDecisionFlow(Request request, double networkScore) async {
    // AGGRESSIVE Strategy: Try HTTP first, quick SMS fallback
    if (_strategy == ResilienceStrategy.aggressive) {
      if (networkScore > 0.3) {
        // Try HTTP even with poor network
        final response = await _tryHTTP(request, const Duration(seconds: 10));
        if (response.statusCode < 500) {
          return response;
        }
      }

      // Quick SMS fallback for high priority
      if (request.priority.value >= Priority.high.value && _enableSMS && request.smsEligible) {
        return await _queueWithSMSFallback(request, const Duration(minutes: 1));
      }

      return await _queueRequest(request).then((_) => Response(
        statusCode: 202,
        body: 'Request queued for retry',
        isFromCache: true,
      ));
    }

    // BALANCED Strategy: Smart detection, reasonable wait
    if (_strategy == ResilienceStrategy.balanced) {
      if (networkScore > 0.7) {
        // Good network - try HTTP with standard timeout
        return await _tryHTTP(request, _timeout);
      } else if (networkScore > 0.3) {
        // Poor network - try HTTP with shorter timeout
        return await _tryHTTP(request, const Duration(seconds: 5));
      } else if (networkScore == 0.0) {
        // No network
        if (request.priority == Priority.critical && _enableSMS && request.smsEligible) {
          // Critical request - try SMS immediately
          return await _trySMS(request);
        } else if (request.priority.value >= Priority.high.value && _enableSMS && request.smsEligible) {
          // High priority - queue with SMS fallback after threshold
          return await _queueWithSMSFallback(request, _smsThreshold);
        } else {
          // Normal priority - just queue
          await _queueRequest(request);
          return Response(
            statusCode: 202,
            body: 'Request queued for later processing',
            isFromCache: true,
          );
        }
      } else {
        // Very poor network - queue and wait
        return await _queueWithSMSFallback(request, _smsThreshold);
      }
    }

    // CONSERVATIVE Strategy: Minimize SMS, long waits
    if (_strategy == ResilienceStrategy.conservative) {
      if (networkScore > 0.5) {
        // Only try HTTP if network is decent
        return await _tryHTTP(request, _timeout);
      } else {
        // Queue for all poor network conditions
        await _queueRequest(request);

        // Only use SMS for critical requests after long wait
        if (request.priority == Priority.critical && _enableSMS && request.smsEligible) {
          return await _queueWithSMSFallback(request, const Duration(minutes: 15));
        }

        return Response(
          statusCode: 202,
          body: 'Request queued - network quality insufficient',
          isFromCache: true,
        );
      }
    }

    // CUSTOM Strategy: Use default balanced behavior
    return await _applyDecisionFlow(request, networkScore);
  }

  /// Queue request with SMS fallback after threshold
  Future<Response> _queueWithSMSFallback(Request request, Duration threshold) async {
    await _queueRequest(request);

    // Set up timer for SMS fallback
    final requestId = await _queueManager.enqueue(request);

    _smsTimers[requestId] = Timer(threshold, () async {
      // Check if network is still unavailable
      final score = await _networkDetector.getNetworkScore();

      if (score < 0.3 && _enableSMS && request.smsEligible) {
        Logger.info('SMS threshold reached for request $requestId, attempting SMS fallback');

        // Get the queued request
        final queuedRequests = await _queueManager.getPendingRequests(100);
        final queuedRequest = queuedRequests.where((r) => r.id == requestId).firstOrNull;

        if (queuedRequest != null) {
          // Check cost if provider is available
          if (_smsCostWarning && _smsCostProvider != null && _smsCostWarningCallback != null) {
            final message = _smsGateway.compressRequest(queuedRequest);
            final cost = await _smsCostProvider!(message);
            final approved = await _smsCostWarningCallback!(cost);

            if (!approved) {
              Logger.info('SMS fallback cancelled by user - cost too high: \$$cost');
              return;
            }
          }

          await _smsGateway.sendSMS(queuedRequest);
        }
      }

      _smsTimers.remove(requestId);
    });

    return Response(
      statusCode: 202,
      body: 'Request queued with SMS fallback in ${threshold.inMinutes} minutes',
      isFromCache: true,
    );
  }

  /// Try HTTP request
  Future<Response> _tryHTTP(Request request, Duration timeout) async {
    try {
      final uri = Uri.parse(request.url);
      http.Response response;

      // Prepare body for POST/PUT requests
      String? bodyString;
      if (request.body != null) {
        // If body is a Map, convert to JSON string
        bodyString = json.encode(request.body);
      }

      switch (request.method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: request.headers)
              .timeout(timeout);
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: request.headers,
            body: bodyString,
          ).timeout(timeout);
          break;
        case 'PUT':
          response = await http.put(
            uri,
            headers: request.headers,
            body: bodyString,
          ).timeout(timeout);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: request.headers)
              .timeout(timeout);
          break;
        default:
          throw Exception('Unsupported HTTP method: ${request.method}');
      }

      Logger.info('HTTP request successful: ${response.statusCode}');

      // If successful, clear any SMS timers for this request
      _clearSMSTimersForRequest(request);

      return Response(
        statusCode: response.statusCode,
        body: response.body,
        headers: response.headers,
      );
    } on TimeoutException {
      Logger.warning('HTTP request timeout');
      _networkDetector.recordFailure();

      // Queue request if timeout
      await _queueRequest(request);
      return Response(
        statusCode: 408,
        body: 'Request timeout - queued for retry',
        isFromCache: true,
      );
    } catch (e, stackTrace) {
      Logger.error('HTTP request failed', e, stackTrace);
      _networkDetector.recordFailure();

      // Queue request if failed
      await _queueRequest(request);
      return Response(
        statusCode: 500,
        body: 'Request failed - queued for retry',
        isFromCache: true,
      );
    }
  }

  /// Clear SMS timers for a request (called when request succeeds)
  void _clearSMSTimersForRequest(Request request) {
    // Find and cancel timers for this request
    final timersToRemove = <String>[];
    for (final entry in _smsTimers.entries) {
      // Could match by idempotency key or URL
      timersToRemove.add(entry.key);
    }

    for (final key in timersToRemove) {
      _smsTimers[key]?.cancel();
      _smsTimers.remove(key);
    }
  }

  /// Try SMS fallback
  Future<Response> _trySMS(Request request) async {
    Logger.info('Attempting SMS fallback');

    if (!_enableSMS) {
      return Response(
        statusCode: 503,
        body: 'SMS fallback disabled',
      );
    }

    // Check if request is SMS eligible
    if (!request.smsEligible) {
      Logger.warning('Request not eligible for SMS');
      await _queueRequest(request);
      return Response(
        statusCode: 503,
        body: 'SMS not available for this request',
      );
    }

    // Queue and send via SMS
    await _queueManager.enqueue(request);
    final queuedRequest = await _queueManager.getPendingRequests(1);

    if (queuedRequest.isNotEmpty) {
      final success = await _smsGateway.sendSMS(queuedRequest.first);

      if (success) {
        return Response(
          statusCode: 200,
          body: 'Request sent via SMS',
          isFromSMS: true,
        );
      }
    }

    return Response(
      statusCode: 503,
      body: 'SMS send failed',
    );
  }

  /// Queue a request
  Future<void> _queueRequest(Request request) async {
    final queueCount = await _queueManager.getQueueCount();

    if (queueCount >= _maxQueueSize) {
      Logger.warning('Queue is full: $queueCount/$_maxQueueSize');
      throw Exception('Queue is full');
    }

    await _queueManager.enqueue(request);
    Logger.info('Request queued successfully');
  }

  /// Configure resilient middleware with advanced options
  static void configure({
    ResilienceStrategy? strategy,
    Duration? smsTimeout,
    bool? smsCostWarning,
    bool? batchSMS,
    int? maxQueueSize,
    SMSCostProvider? smsCostProvider,
    SMSCostWarningCallback? smsCostWarningCallback,
  }) {
    final instance = ResilientMiddleware();

    if (!instance._initialized) {
      throw Exception('ResilientMiddleware not initialized. Call initialize() first.');
    }

    if (strategy != null) {
      instance.setStrategy(strategy);
    }

    if (smsTimeout != null) {
      instance.setSMSThreshold(smsTimeout);
    }

    if (maxQueueSize != null) {
      instance.setMaxQueueSize(maxQueueSize);
    }

    if (smsCostWarning != null) {
      instance._smsCostWarning = smsCostWarning;
    }

    if (smsCostProvider != null) {
      instance._smsCostProvider = smsCostProvider;
    }

    if (smsCostWarningCallback != null) {
      instance._smsCostWarningCallback = smsCostWarningCallback;
    }

    if (batchSMS != null) {
      instance._batchSMS = batchSMS;
    }

    Logger.info('ResilientMiddleware configuration updated');
  }

  /// Set resilience strategy
  void setStrategy(ResilienceStrategy strategy) {
    _strategy = strategy;
    _smsThreshold = _getSMSThresholdForStrategy(strategy);
    Logger.info('Resilience strategy set to: ${strategy.name}');
  }

  /// Set SMS threshold
  void setSMSThreshold(Duration duration) {
    _smsThreshold = duration;
    Logger.info('SMS threshold set to: ${duration.inMinutes} minutes');
  }

  /// Set max queue size
  void setMaxQueueSize(int size) {
    _maxQueueSize = size;
    Logger.info('Max queue size set to: $size');
  }

  /// Enable or disable SMS fallback
  void enableSMS(bool enable) {
    _enableSMS = enable;
    Logger.info('SMS fallback ${enable ? "enabled" : "disabled"}');
  }

  /// Get current network score
  Future<double> getNetworkScore() async {
    return await _networkDetector.getNetworkScore();
  }

  /// Get network status
  Future<NetworkStatus> getNetworkStatus() async {
    final type = await _networkDetector.getNetworkType();
    final score = await _networkDetector.getNetworkScore();
    final latency = await _networkDetector.measureLatency();
    final stable = await _networkDetector.isStable();

    return NetworkStatus(
      type: type,
      qualityScore: score,
      latency: latency,
      isStable: stable,
    );
  }

  /// Get queue count
  Future<int> getQueueCount() async {
    return await _queueManager.getQueueCount();
  }

  /// Get pending requests from queue
  Future<List<QueuedRequest>> getPendingRequests({int limit = 10}) async {
    return await _queueManager.getPendingRequests(limit);
  }

  /// Manually process queue (useful for testing or manual triggers)
  Future<void> processQueue() async {
    await _queueManager.processQueue();
  }

  /// Clear all queued requests
  Future<int> clearQueue() async {
    final count = await _queueManager.clearAll();
    Logger.info('Queue cleared: $count requests removed');
    return count;
  }

  /// Get SMS gateway number
  String getSMSGatewayNumber() {
    return _smsGateway.getGatewayNumber();
  }

  /// Check if SMS permissions are granted
  Future<bool> hasSMSPermissions() async {
    return await _smsGateway.hasPermissions();
  }

  /// Request SMS permissions
  Future<bool> requestSMSPermissions() async {
    return await _smsGateway.requestPermissions();
  }

  /// Get current configuration
  Map<String, dynamic> getConfiguration() {
    return {
      'initialized': _initialized,
      'enableSMS': _enableSMS,
      'strategy': _strategy.name,
      'smsThreshold': _smsThreshold.inMinutes,
      'timeout': _timeout.inSeconds,
      'maxQueueSize': _maxQueueSize,
      'smsCostWarning': _smsCostWarning,
      'batchSMS': _batchSMS,
      'smsGateway': _smsGateway.getGatewayNumber(),
    };
  }

  /// Check if initialized
  bool get isInitialized => _initialized;

  /// Dispose resources
  void dispose() {
    // Cancel all SMS timers
    for (final timer in _smsTimers.values) {
      timer.cancel();
    }
    _smsTimers.clear();

    // Cancel network subscription
    _networkSubscription?.cancel();
    _networkSubscription = null;

    // Dispose components
    _networkDetector.dispose();
    _queueManager.dispose();
    _smsGateway.dispose();

    _initialized = false;
    Logger.info('ResilientMiddleware disposed');
  }
}
