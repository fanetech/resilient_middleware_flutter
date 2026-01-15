import 'package:flutter/material.dart';
import 'package:resilient_middleware_flutter/resilient_middleware.dart';

/// Network status indicator widget
class NetworkIndicator extends StatefulWidget {
  const NetworkIndicator({super.key});

  @override
  State<NetworkIndicator> createState() => _NetworkIndicatorState();
}

class _NetworkIndicatorState extends State<NetworkIndicator> {
  NetworkStatus? _networkStatus;
  int _queueCount = 0;

  @override
  void initState() {
    super.initState();
    _updateStatus();

    // Update every 3 seconds
    Future.delayed(Duration.zero, () {
      _startPeriodicUpdate();
    });
  }

  void _startPeriodicUpdate() {
    Future.doWhile(() async {
      if (!mounted) return false;
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        await _updateStatus();
      }
      return mounted;
    });
  }

  Future<void> _updateStatus() async {
    try {
      final status = await ResilientMiddleware().getNetworkStatus();
      final count = await ResilientMiddleware().getQueueCount();
      if (mounted) {
        setState(() {
          _networkStatus = status;
          _queueCount = count;
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Color _getStatusColor() {
    if (_networkStatus == null) return Colors.grey;

    final score = _networkStatus!.qualityScore;
    if (score > 0.7) return Colors.green;
    if (score > 0.3) return Colors.orange;
    if (score > 0) return Colors.red;
    return Colors.grey;
  }

  String _getStatusText() {
    if (_networkStatus == null) return 'Checking...';

    final score = _networkStatus!.qualityScore;
    if (score > 0.7) return 'Online (Excellent)';
    if (score > 0.3) return 'Online (Poor)';
    if (score > 0) return 'Online (Very Poor)';
    return 'Offline';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getStatusColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _getStatusColor(),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _getStatusColor(),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _getStatusText(),
            style: TextStyle(
              color: _getStatusColor(),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          if (_queueCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$_queueCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
