/// Queue manager for offline request handling
library;

import 'dart:async';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/queue_item.dart';
import '../models/request_model.dart';
import '../database/offline_database.dart';
import '../utils/logger.dart';

/// Callback for when a queued request completes successfully
typedef OnRequestCompleted = void Function(String requestId, int statusCode, String body);

/// Callback for when a queued request fails
typedef OnRequestFailed = void Function(String requestId, String error);

/// Queue manager for handling offline requests
class QueueManager {
  static final QueueManager _instance = QueueManager._internal();
  factory QueueManager() => _instance;
  QueueManager._internal();

  final OfflineDatabase _database = OfflineDatabase();
  Timer? _processTimer;

  /// Callbacks for request completion
  OnRequestCompleted? onRequestCompleted;
  OnRequestFailed? onRequestFailed;

  /// HTTP timeout for retry attempts
  Duration httpTimeout = const Duration(seconds: 30);

  /// Initialize queue manager
  Future<void> initialize() async {
    await _database.database;
    Logger.info('Queue manager initialized');

    // Start periodic queue processing
    _startProcessing();
  }

  /// Enqueue a request
  Future<String> enqueue(Request request) async {
    // Generate unique ID
    final id = _generateId(request);

    final queuedRequest = QueuedRequest(
      id: id,
      request: request,
      createdAt: DateTime.now(),
      maxRetries: request.priority == Priority.critical ? 5 : 3,
    );

    await _database.insert(queuedRequest);
    Logger.info('Request enqueued: $id');

    return id;
  }

  /// Dequeue next request (highest priority)
  Future<QueuedRequest?> dequeue() async {
    final requests = await _database.getPendingRequests(limit: 1);
    if (requests.isEmpty) return null;

    final request = requests.first;
    await _database.updateStatus(request.id, QueueStatus.processing.name);

    return request;
  }

  /// Get pending requests
  Future<List<QueuedRequest>> getPendingRequests(int limit) async {
    return await _database.getPendingRequests(limit: limit);
  }

  /// Update request status
  Future<void> updateStatus(String id, QueueStatus status) async {
    await _database.updateStatus(id, status.name);
    Logger.info('Request $id status updated to ${status.name}');
  }

  /// Increment retry count
  Future<void> incrementRetryCount(String id) async {
    await _database.incrementRetryCount(id);
    await _database.updateStatus(id, QueueStatus.pending.name);
    Logger.info('Request $id retry count incremented');
  }

  /// Process queue
  Future<void> processQueue() async {
    Logger.debug('Processing queue...');

    // Clean expired requests
    await cleanExpiredRequests();

    // Get all pending requests (limit to batch size for efficiency)
    final requests = await _database.getPendingRequests(limit: 10);

    if (requests.isEmpty) {
      Logger.debug('No pending requests in queue');
      return;
    }

    Logger.info('Processing ${requests.length} pending requests from queue');

    // Process each request with retry logic
    for (final queuedRequest in requests) {
      await _processQueuedRequest(queuedRequest);
    }
  }

  /// Process a single queued request
  Future<void> _processQueuedRequest(QueuedRequest queuedRequest) async {
    try {
      // Mark as processing
      await updateStatus(queuedRequest.id, QueueStatus.processing);

      Logger.info('Processing queued request: ${queuedRequest.id} - ${queuedRequest.request.method} ${queuedRequest.request.url}');

      // Check if max retries reached
      if (queuedRequest.hasReachedMaxRetries) {
        Logger.warning('Request ${queuedRequest.id} reached max retries (${queuedRequest.retryCount}/${queuedRequest.maxRetries})');
        await updateStatus(queuedRequest.id, QueueStatus.failed);
        onRequestFailed?.call(queuedRequest.id, 'Max retries reached');
        return;
      }

      // Check if expired
      if (queuedRequest.isExpired) {
        Logger.warning('Request ${queuedRequest.id} has expired');
        await updateStatus(queuedRequest.id, QueueStatus.expired);
        await delete(queuedRequest.id);
        onRequestFailed?.call(queuedRequest.id, 'Request expired');
        return;
      }

      // Actually execute the HTTP request
      final response = await _executeHttpRequest(queuedRequest);

      if (response != null && response.statusCode >= 200 && response.statusCode < 300) {
        // Success - mark as completed and remove from queue
        Logger.info('Queued request ${queuedRequest.id} completed successfully with status ${response.statusCode}');
        await updateStatus(queuedRequest.id, QueueStatus.completed);
        await delete(queuedRequest.id);
        onRequestCompleted?.call(queuedRequest.id, response.statusCode, response.body);
      } else {
        // Failed - increment retry count
        final statusCode = response?.statusCode ?? 0;
        Logger.warning('Queued request ${queuedRequest.id} failed with status $statusCode, will retry');
        await incrementRetryCount(queuedRequest.id);
        onRequestFailed?.call(queuedRequest.id, 'HTTP error: $statusCode');
      }

    } catch (e, stackTrace) {
      Logger.error('Failed to process queued request ${queuedRequest.id}', e, stackTrace);
      await incrementRetryCount(queuedRequest.id);
      onRequestFailed?.call(queuedRequest.id, e.toString());
    }
  }

  /// Execute HTTP request for a queued item
  Future<http.Response?> _executeHttpRequest(QueuedRequest queuedRequest) async {
    try {
      final request = queuedRequest.request;
      final uri = Uri.parse(request.url);

      // Prepare body for POST/PUT requests
      String? bodyString;
      if (request.body != null) {
        bodyString = json.encode(request.body);
      }

      Logger.debug('Executing HTTP ${request.method} to ${request.url}');

      http.Response response;
      switch (request.method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: request.headers)
              .timeout(httpTimeout);
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: request.headers,
            body: bodyString,
          ).timeout(httpTimeout);
          break;
        case 'PUT':
          response = await http.put(
            uri,
            headers: request.headers,
            body: bodyString,
          ).timeout(httpTimeout);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: request.headers)
              .timeout(httpTimeout);
          break;
        default:
          Logger.error('Unsupported HTTP method: ${request.method}');
          return null;
      }

      Logger.debug('HTTP response: ${response.statusCode}');
      return response;

    } on TimeoutException {
      Logger.warning('HTTP request timeout for queued request ${queuedRequest.id}');
      return null;
    } catch (e, stackTrace) {
      Logger.error('HTTP request failed for queued request ${queuedRequest.id}', e, stackTrace);
      return null;
    }
  }

  /// Clean expired requests
  Future<void> cleanExpiredRequests() async {
    final count = await _database.deleteExpired();
    if (count > 0) {
      Logger.info('Cleaned $count expired requests');
    }
  }

  /// Get queue count
  Future<int> getQueueCount() async {
    return await _database.getQueueCount();
  }

  /// Delete request
  Future<void> delete(String id) async {
    await _database.delete(id);
    Logger.info('Request $id deleted');
  }

  /// Clear all requests from queue
  Future<int> clearAll() async {
    final count = await _database.clearAll();
    Logger.info('Cleared all $count requests from queue');
    return count;
  }

  /// Start periodic queue processing
  void _startProcessing() {
    _processTimer?.cancel();
    _processTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => processQueue(),
    );
  }

  /// Stop queue processing
  void stopProcessing() {
    _processTimer?.cancel();
    _processTimer = null;
  }

  /// Generate unique ID for request
  String _generateId(Request request) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final content = '${request.method}${request.url}$timestamp';
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  /// Dispose resources
  void dispose() {
    stopProcessing();
  }
}
