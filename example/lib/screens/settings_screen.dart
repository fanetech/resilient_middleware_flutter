import 'package:flutter/material.dart';
import 'package:resilient_middleware_flutter/resilient_middleware.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _config;
  NetworkStatus? _networkStatus;
  int _queueCount = 0;

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  Future<void> _loadConfiguration() async {
    try {
      final config = ResilientMiddleware().getConfiguration();
      final status = await ResilientMiddleware().getNetworkStatus();
      final count = await ResilientMiddleware().getQueueCount();

      setState(() {
        _config = config;
        _networkStatus = status;
        _queueCount = count;
      });
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _processQueue() async {
    try {
      await ResilientMiddleware().processQueue();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Queue processing triggered')),
      );
      await _loadConfiguration();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _clearQueue() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Queue'),
        content: const Text('Are you sure you want to clear all queued requests?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final count = await ResilientMiddleware().clearQueue();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cleared $count queued requests')),
          );
          await _loadConfiguration();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _config == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadConfiguration,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Network Status Section
                  _buildSection(
                    title: 'Network Status',
                    children: [
                      _buildInfoRow(
                        'Status',
                        _getNetworkStatusText(),
                        icon: Icons.wifi,
                      ),
                      _buildInfoRow(
                        'Quality Score',
                        '${(_networkStatus?.qualityScore ?? 0).toStringAsFixed(2)}/1.0',
                        icon: Icons.speed,
                      ),
                      _buildInfoRow(
                        'Network Type',
                        _networkStatus?.type.name ?? 'Unknown',
                        icon: Icons.network_check,
                      ),
                      _buildInfoRow(
                        'Latency',
                        '${_networkStatus?.latency ?? 0}ms',
                        icon: Icons.timer,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Configuration Section
                  _buildSection(
                    title: 'Configuration',
                    children: [
                      _buildInfoRow(
                        'Strategy',
                        _config!['strategy'] ?? 'Unknown',
                        icon: Icons.settings,
                      ),
                      _buildInfoRow(
                        'SMS Enabled',
                        _config!['enableSMS'].toString(),
                        icon: Icons.sms,
                      ),
                      _buildInfoRow(
                        'SMS Gateway',
                        _config!['smsGateway'] ?? 'Not set',
                        icon: Icons.phone,
                      ),
                      _buildInfoRow(
                        'SMS Threshold',
                        '${_config!['smsThreshold']} minutes',
                        icon: Icons.schedule,
                      ),
                      _buildInfoRow(
                        'Timeout',
                        '${_config!['timeout']} seconds',
                        icon: Icons.timelapse,
                      ),
                      _buildInfoRow(
                        'Max Queue Size',
                        _config!['maxQueueSize'].toString(),
                        icon: Icons.storage,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Queue Management Section
                  _buildSection(
                    title: 'Queue Management',
                    children: [
                      _buildInfoRow(
                        'Queued Requests',
                        _queueCount.toString(),
                        icon: Icons.queue,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _processQueue,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Process Queue'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _clearQueue,
                              icon: const Icon(Icons.delete),
                              label: const Text('Clear Queue'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade100,
                                foregroundColor: Colors.red.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // About Section
                  _buildSection(
                    title: 'About',
                    children: [
                      const Text(
                        'Resilient Middleware Demo',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This demo app showcases the Resilient Middleware plugin with automatic network failure handling and SMS fallback.',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Features:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text('• Automatic network detection'),
                      const Text('• Local queue for offline requests'),
                      const Text('• SMS fallback for critical transactions'),
                      const Text('• Automatic retry with exponential backoff'),
                      const Text('• Real-time network status updates'),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: Colors.blue),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _getNetworkStatusText() {
    if (_networkStatus == null) return 'Unknown';

    final score = _networkStatus!.qualityScore;
    if (score > 0.7) return 'Online (Excellent)';
    if (score > 0.3) return 'Online (Poor)';
    if (score > 0) return 'Online (Very Poor)';
    return 'Offline';
  }
}
