import 'package:flutter/material.dart';
import 'package:resilient_middleware_flutter/resilient_middleware.dart';
import '../models/transaction.dart';
import 'dart:math';

class TransferScreen extends StatefulWidget {
  final double currentBalance;
  final Function(Transaction) onTransferComplete;

  const TransferScreen({
    super.key,
    required this.currentBalance,
    required this.onTransferComplete,
  });

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _recipientController = TextEditingController();

  Priority _priority = Priority.normal;
  bool _smsEligible = true;
  bool _isLoading = false;
  String? _statusMessage;

  @override
  void dispose() {
    _amountController.dispose();
    _recipientController.dispose();
    super.dispose();
  }

  Future<void> _sendTransfer() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text);
    if (amount > widget.currentBalance) {
      _showError('Insufficient balance');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Processing transfer...';
    });

    try {
      // Demo API endpoint
      final response = await ResilientHttp.post(
        'https://jsonplaceholder.typicode.com/posts', // Demo API
        body: {
          'amount': amount,
          'recipient': _recipientController.text,
          'timestamp': DateTime.now().toIso8601String(),
        },
        priority: _priority,
        smsEligible: _smsEligible,
      );

      // Create transaction
      final transaction = Transaction(
        id: Random().nextInt(10000).toString(),
        type: 'sent',
        amount: amount,
        recipient: _recipientController.text,
        timestamp: DateTime.now(),
        status: response.isFromCache
            ? 'queued'
            : response.isFromSMS
                ? 'sms'
                : 'completed',
        isFromSMS: response.isFromSMS,
      );

      setState(() {
        _isLoading = false;
        if (response.isFromSMS) {
          _statusMessage = '✅ Transfer sent via SMS!';
        } else if (response.isFromCache) {
          _statusMessage = '📦 Transfer queued - will process when online';
        } else {
          _statusMessage = '✅ Transfer completed successfully!';
        }
      });

      widget.onTransferComplete(transaction);

      // Show result dialog
      await _showResultDialog(transaction);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '❌ Transfer failed: $e';
      });
    }
  }

  Future<void> _showResultDialog(Transaction transaction) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(
          transaction.status == 'completed'
              ? Icons.check_circle
              : transaction.status == 'sms'
                  ? Icons.sms
                  : Icons.schedule,
          size: 48,
          color: transaction.status == 'completed'
              ? Colors.green
              : Colors.orange,
        ),
        title: Text(transaction.statusDisplay),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount: ${transaction.amount.toStringAsFixed(0)} XOF'),
            Text('Recipient: ${transaction.recipient}'),
            const SizedBox(height: 8),
            if (transaction.isFromSMS)
              const Text(
                'Your transaction was sent via SMS because internet connection was unavailable.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            if (transaction.status == 'queued')
              const Text(
                'Your transaction is queued and will be processed when internet becomes available.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Money'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Balance Display
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Available Balance:',
                        style: TextStyle(fontSize: 16),
                      ),
                      Text(
                        '${widget.currentBalance.toStringAsFixed(0)} XOF',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Recipient Input
              TextFormField(
                controller: _recipientController,
                decoration: const InputDecoration(
                  labelText: 'Recipient',
                  hintText: 'Enter recipient name or phone',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter recipient';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Amount Input
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  hintText: 'Enter amount',
                  prefixIcon: Icon(Icons.money),
                  suffixText: 'XOF',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter amount';
                  }
                  final amount = double.tryParse(value);
                  if (amount == null || amount <= 0) {
                    return 'Please enter valid amount';
                  }
                  if (amount > widget.currentBalance) {
                    return 'Insufficient balance';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Priority Selection
              const Text(
                'Priority',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<Priority>(
                segments: const [
                  ButtonSegment(
                    value: Priority.normal,
                    label: Text('Normal'),
                    icon: Icon(Icons.check),
                  ),
                  ButtonSegment(
                    value: Priority.high,
                    label: Text('High'),
                    icon: Icon(Icons.priority_high),
                  ),
                  ButtonSegment(
                    value: Priority.critical,
                    label: Text('Critical'),
                    icon: Icon(Icons.warning),
                  ),
                ],
                selected: {_priority},
                onSelectionChanged: (Set<Priority> newSelection) {
                  setState(() {
                    _priority = newSelection.first;
                  });
                },
              ),
              const SizedBox(height: 16),

              // SMS Eligible Checkbox
              CheckboxListTile(
                title: const Text('Enable SMS fallback'),
                subtitle: const Text(
                  'Send via SMS if internet is unavailable',
                  style: TextStyle(fontSize: 12),
                ),
                value: _smsEligible,
                onChanged: (value) {
                  setState(() {
                    _smsEligible = value ?? true;
                  });
                },
              ),
              const SizedBox(height: 24),

              // Status Message
              if (_statusMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      if (_isLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.info, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // Send Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendTransfer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Send Money',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
