import 'package:flutter/material.dart';
import 'package:resilient_middleware_flutter/resilient_middleware.dart';
import '../widgets/network_indicator.dart';
import '../models/transaction.dart';
import 'transfer_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _balance = 50000.0; // Demo balance
  final List<Transaction> _recentTransactions = [];

  @override
  void initState() {
    super.initState();
    _loadDemoData();
    _setupQueueListener();
  }

  @override
  void dispose() {
    // Remove the callbacks when disposing
    QueueManager().onRequestCompleted = null;
    super.dispose();
  }

  /// Setup listener for queue completion events
  void _setupQueueListener() {
    final queueManager = QueueManager();

    // Listen for successful queue completions
    queueManager.onRequestCompleted = (requestId, statusCode, body) {
      Logger.info('Queue request completed: $requestId with status $statusCode');

      // Find the queued transaction and update its status
      setState(() {
        for (int i = 0; i < _recentTransactions.length; i++) {
          final tx = _recentTransactions[i];
          // Match by ID (transaction ID now equals request ID for queued items)
          if (tx.id == requestId && tx.status == 'queued') {
            _recentTransactions[i] = Transaction(
              id: tx.id,
              type: tx.type,
              amount: tx.amount,
              recipient: tx.recipient,
              timestamp: tx.timestamp,
              status: 'completed',
              isFromSMS: tx.isFromSMS,
            );
            // Deduct balance for newly completed transaction
            _balance -= tx.amount;
            Logger.info('Transaction ${tx.id} updated to completed');
            break;
          }
        }
      });
    };

    // Listen for failed queue requests
    queueManager.onRequestFailed = (requestId, error) {
      Logger.warning('Queue request failed: $requestId - $error');

      setState(() {
        for (int i = 0; i < _recentTransactions.length; i++) {
          final tx = _recentTransactions[i];
          if (tx.id == requestId && tx.status == 'queued') {
            // Keep as queued if it will retry, or mark as failed if max retries reached
            if (error == 'Max retries reached') {
              _recentTransactions[i] = Transaction(
                id: tx.id,
                type: tx.type,
                amount: tx.amount,
                recipient: tx.recipient,
                timestamp: tx.timestamp,
                status: 'failed',
                isFromSMS: tx.isFromSMS,
              );
            }
            break;
          }
        }
      });
    };
  }

  void _loadDemoData() {
    // Add some demo transactions
    _recentTransactions.addAll([
      Transaction(
        id: '001',
        type: 'received',
        amount: 15000,
        recipient: 'John Doe',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        status: 'completed',
      ),
      Transaction(
        id: '002',
        type: 'sent',
        amount: 5000,
        recipient: 'Jane Smith',
        timestamp: DateTime.now().subtract(const Duration(hours: 5)),
        status: 'completed',
      ),
      Transaction(
        id: '003',
        type: 'sent',
        amount: 2500,
        recipient: 'Bob Johnson',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        status: 'completed',
      ),
    ]);
  }

  void _onTransferComplete(Transaction transaction) {
    setState(() {
      _recentTransactions.insert(0, transaction);
      if (transaction.status == 'completed') {
        _balance -= transaction.amount;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Resilient Banking',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: const NetworkIndicator(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Balance Card
              _buildBalanceCard(),
              const SizedBox(height: 24),

              // Quick Actions
              _buildQuickActions(),
              const SizedBox(height: 24),

              // Recent Transactions
              _buildRecentTransactions(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TransferScreen(
                currentBalance: _balance,
                onTransferComplete: _onTransferComplete,
              ),
            ),
          );
        },
        icon: const Icon(Icons.send),
        label: const Text('Transfer Money'),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade700, Colors.blue.shade500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Available Balance',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'XOF ${_balance.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.security, color: Colors.white70, size: 16),
                SizedBox(width: 4),
                Text(
                  'Works offline with SMS fallback',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.send,
                label: 'Send Money',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TransferScreen(
                        currentBalance: _balance,
                        onTransferComplete: _onTransferComplete,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.history,
                label: 'History',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HistoryScreen(
                        transactions: _recentTransactions,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 32, color: Colors.blue.shade700),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentTransactions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Transactions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HistoryScreen(
                      transactions: _recentTransactions,
                    ),
                  ),
                );
              },
              child: const Text('See All'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_recentTransactions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No transactions yet',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          )
        else
          ...(_recentTransactions.take(3).map((transaction) {
            return _buildTransactionItem(transaction);
          })),
      ],
    );
  }

  Widget _buildTransactionItem(Transaction transaction) {
    final isReceived = transaction.type == 'received';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isReceived
                ? Colors.green.withOpacity(0.1)
                : Colors.red.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isReceived ? Icons.arrow_downward : Icons.arrow_upward,
            color: isReceived ? Colors.green : Colors.red,
          ),
        ),
        title: Text(
          isReceived ? 'From ${transaction.recipient}' : 'To ${transaction.recipient}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          transaction.statusDisplay,
          style: TextStyle(
            fontSize: 12,
            color: transaction.status == 'completed'
                ? Colors.green
                : transaction.status == 'failed'
                    ? Colors.red
                    : Colors.orange,
          ),
        ),
        trailing: Text(
          '${isReceived ? '+' : '-'}${transaction.amount.toStringAsFixed(0)} XOF',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isReceived ? Colors.green : Colors.black87,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
