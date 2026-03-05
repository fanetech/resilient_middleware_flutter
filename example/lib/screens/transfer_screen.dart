import 'package:flutter/material.dart';
import 'package:resilient_middleware_flutter/resilient_middleware.dart';
import '../config/app_config.dart';

class TransferScreen extends StatefulWidget {
  final String phone;
  final int currentBalance;
  final VoidCallback onTransferComplete;

  const TransferScreen({
    super.key,
    required this.phone,
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
  final _pinController = TextEditingController();

  late ResilientApiService _api;
  bool _smsEligible = true;
  bool _isLoading = false;
  String? _statusMessage;
  bool _obscurePin = true;

  @override
  void initState() {
    super.initState();
    _api = ResilientApiService.getInstance(baseUrl: AppConfig.apiBaseUrl);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _recipientController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _sendTransfer() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = int.parse(_amountController.text);
    if (amount > widget.currentBalance) {
      _showError('Insufficient balance');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Processing transfer...';
    });

    try {
      Logger.info('in_sendTransfer ');
      final result = await _api.transfer(
        from: widget.phone,
        to: _recipientController.text.trim(),
        amount: amount,
        pin: _pinController.text,
        useSMSFallback: _smsEligible,
      );

      if (result.isSuccess) {
        final data = result.data!;
        setState(() {
          _isLoading = false;
          _statusMessage = data.fromSMS
              ? 'Transfer sent via SMS!'
              : 'Transfer completed successfully!';
        });

        await _showResultDialog(
          success: true,
          amount: amount,
          recipient: _recipientController.text,
          newBalance: data.newBalance,
          transactionRef: data.transactionRef,
          fromSMS: data.fromSMS,
        );

        widget.onTransferComplete();

        if (mounted) {
          Navigator.pop(context);
        }
      } else if (result.isQueued) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Transfer queued - will process when online';
        });

        await _showResultDialog(
          success: true,
          amount: amount,
          recipient: _recipientController.text,
          queued: true,
          queueId: result.queuedRequestId,
        );

        widget.onTransferComplete();

        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Transfer failed: ${result.message}';
        });

        _showError(result.message ?? 'Transfer failed');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Transfer failed: $e';
      });
      _showError('Error: $e');
    }
  }

  Future<void> _showResultDialog({
    required bool success,
    required int amount,
    required String recipient,
    int? newBalance,
    String? transactionRef,
    bool fromSMS = false,
    bool queued = false,
    String? queueId,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(
          success
              ? (queued ? Icons.schedule : Icons.check_circle)
              : Icons.error,
          size: 48,
          color: success ? (queued ? Colors.orange : Colors.green) : Colors.red,
        ),
        title: Text(
          success
              ? (queued
                  ? 'Transfer Queued'
                  : (fromSMS ? 'Sent via SMS' : 'Transfer Complete'))
              : 'Transfer Failed',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount: ${_formatAmount(amount)} FCFA'),
            Text('To: $recipient'),
            if (newBalance != null) ...[
              const SizedBox(height: 8),
              Text(
                'New Balance: ${_formatAmount(newBalance)} FCFA',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
            if (transactionRef != null) ...[
              const SizedBox(height: 4),
              Text(
                'Ref: $transactionRef',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 12),
            if (fromSMS)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.sms, size: 16, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sent via SMS fallback (no internet)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (queued)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.cloud_queue, size: 16, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Will process automatically when online',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
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

  String _formatAmount(int amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}K';
    }
    return amount.toString();
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
                        '${_formatAmount(widget.currentBalance)} FCFA',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Recipient Phone Number
              TextFormField(
                controller: _recipientController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Recipient Phone Number',
                  hintText: 'e.g., +22676543211',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter recipient phone number';
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
                  suffixText: 'FCFA',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter amount';
                  }
                  final amount = int.tryParse(value);
                  if (amount == null || amount <= 0) {
                    return 'Please enter valid amount';
                  }
                  if (amount > widget.currentBalance) {
                    return 'Insufficient balance';
                  }
                  if (amount > 1000000) {
                    return 'Max transfer: 1,000,000 FCFA';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // PIN Input
              TextFormField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                maxLength: AppConfig.pinLength,
                obscureText: _obscurePin,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  hintText: '${AppConfig.pinLength} digits',
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePin ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePin = !_obscurePin;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter PIN';
                  }
                  if (value.length != AppConfig.pinLength) {
                    return 'PIN must be ${AppConfig.pinLength} digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // SMS Fallback Option
              Card(
                child: CheckboxListTile(
                  title: const Text('Enable SMS fallback'),
                  subtitle: const Text(
                    'Send via SMS if internet is unavailable',
                    style: TextStyle(fontSize: 12),
                  ),
                  secondary: Icon(
                    Icons.sms,
                    color: _smsEligible ? Colors.blue : Colors.grey,
                  ),
                  value: _smsEligible,
                  onChanged: (value) {
                    setState(() {
                      _smsEligible = value ?? true;
                    });
                  },
                ),
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
