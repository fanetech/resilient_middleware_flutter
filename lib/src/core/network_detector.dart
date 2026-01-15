/// Network detection and quality assessment
///
/// Monitors real-time connectivity and provides network quality scoring
library;

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Network status types
enum NetworkType {
  wifi,
  mobile4g,
  mobile3g,
  mobile2g,
  none,
  unknown,
}

/// Network status with quality score
class NetworkStatus {
  final NetworkType type;
  final double qualityScore;
  final int latency;
  final bool isStable;

  NetworkStatus({
    required this.type,
    required this.qualityScore,
    required this.latency,
    required this.isStable,
  });
}

/// Network detection and monitoring service
class NetworkDetector {
  static final NetworkDetector _instance = NetworkDetector._internal();
  factory NetworkDetector() => _instance;
  NetworkDetector._internal();

  final Connectivity _connectivity = Connectivity();
  final StreamController<NetworkStatus> _networkStreamController =
      StreamController<NetworkStatus>.broadcast();

  // Recent failures tracking for quality scoring
  final List<DateTime> _recentFailures = [];
  static const int _failureTrackingWindow = 5; // minutes

  /// Stream of network status changes
  Stream<NetworkStatus> get networkStream => _networkStreamController.stream;

  /// Initialize network monitoring
  Future<void> initialize() async {
    // Listen to connectivity changes
    _connectivity.onConnectivityChanged.listen((result) {
      _onConnectivityChanged([result]);
    });

    // Initial status check
    final result = await _connectivity.checkConnectivity();
    await _onConnectivityChanged([result]);
  }

  /// Handle connectivity changes
  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    final networkType = await getNetworkType();
    final score = await getNetworkScore();
    final latency = await measureLatency();
    final stable = await isStable();

    _networkStreamController.add(NetworkStatus(
      type: networkType,
      qualityScore: score,
      latency: latency,
      isStable: stable,
    ));
  }

  /// Get current network type
  Future<NetworkType> getNetworkType() async {
    final connectivityResult = await _connectivity.checkConnectivity();

    if (connectivityResult == ConnectivityResult.wifi) {
      return NetworkType.wifi;
    } else if (connectivityResult == ConnectivityResult.mobile) {
      // TODO: Implement detailed mobile network type detection (4G/3G/2G)
      return NetworkType.mobile4g;
    } else if (connectivityResult == ConnectivityResult.none) {
      return NetworkType.none;
    }

    return NetworkType.unknown;
  }

  /// Calculate network quality score (0-1)
  ///
  /// Scoring algorithm:
  /// - WiFi: Base score 1.0
  /// - Mobile 4G: Base score 0.8
  /// - Mobile 3G: Base score 0.5
  /// - Mobile 2G: Base score 0.3
  /// - Adjust based on latency: <100ms (+0.1), >1000ms (-0.2)
  /// - Factor in recent failures: Each failure in last 5 min reduces score by 0.1
  Future<double> getNetworkScore() async {
    final networkType = await getNetworkType();
    double score = 0.0;

    // Base score by network type
    switch (networkType) {
      case NetworkType.wifi:
        score = 1.0;
        break;
      case NetworkType.mobile4g:
        score = 0.8;
        break;
      case NetworkType.mobile3g:
        score = 0.5;
        break;
      case NetworkType.mobile2g:
        score = 0.3;
        break;
      case NetworkType.none:
      case NetworkType.unknown:
        score = 0.0;
        break;
    }

    // Adjust based on latency
    if (score > 0) {
      final latency = await measureLatency();
      if (latency < 100) {
        score = (score + 0.1).clamp(0.0, 1.0);
      } else if (latency > 1000) {
        score = (score - 0.2).clamp(0.0, 1.0);
      }
    }

    // Factor in recent failures
    _cleanOldFailures();
    final failurePenalty = _recentFailures.length * 0.1;
    score = (score - failurePenalty).clamp(0.0, 1.0);

    return score;
  }

  /// Measure network latency in milliseconds
  Future<int> measureLatency() async {
    // TODO: Implement actual latency measurement by pinging a reliable server
    // For now, return a placeholder value
    return 100;
  }

  /// Check if network connection is stable
  Future<bool> isStable() async {
    final score = await getNetworkScore();
    return score >= 0.5;
  }

  /// Record a network failure for quality scoring
  void recordFailure() {
    _recentFailures.add(DateTime.now());
    _cleanOldFailures();
  }

  /// Remove failures older than tracking window
  void _cleanOldFailures() {
    final cutoff = DateTime.now().subtract(
      const Duration(minutes: _failureTrackingWindow),
    );
    _recentFailures.removeWhere((failure) => failure.isBefore(cutoff));
  }

  /// Dispose resources
  void dispose() {
    _networkStreamController.close();
  }
}
