/// Queue manager for offline request handling
library;

import 'dart:async';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/queue_item.dart';
import '../models/request_model.dart';
import '../database/offline_database.dart';
import '../utils/logger.dart';

/// Queue manager for handling offline requests
class QueueManager {
  static final QueueManager _instance = QueueManager._internal();
  factory QueueManager() => _instance;
  QueueManager._internal();

  final OfflineDatabase _database = OfflineDatabase();
  Timer? _processTimer;

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

      Logger.debug('Processing queued request: ${queuedRequest.id}');

      // This will be called by ResilientMiddleware when network is available
      // For now, we just update the status and wait for the API to retry

      // Check if max retries reached
      if (queuedRequest.hasReachedMaxRetries) {
        Logger.warning('Request ${queuedRequest.id} reached max retries');
        await updateStatus(queuedRequest.id, QueueStatus.failed);
        return;
      }

      // Check if expired
      if (queuedRequest.isExpired) {
        Logger.warning('Request ${queuedRequest.id} has expired');
        await updateStatus(queuedRequest.id, QueueStatus.expired);
        await delete(queuedRequest.id);
        return;
      }

      // Reset to pending for retry
      await updateStatus(queuedRequest.id, QueueStatus.pending);

    } catch (e, stackTrace) {
      Logger.error('Failed to process queued request ${queuedRequest.id}', e, stackTrace);
      await incrementRetryCount(queuedRequest.id);
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
