// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai_sms_parser.dart';
import '../services/local_storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  bool _isLoading = false;
  bool _obscureKey = true;
  bool _aiEnabled = false;
  Map<String, int> _cacheStats = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCacheStats();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('gemini_api_key') ?? '';
    setState(() {
      _apiKeyController.text = savedKey;
      _aiEnabled = savedKey.isNotEmpty && AiSmsParser.isInitialized;
    });
  }

  Future<void> _loadCacheStats() async {
    final stats = await LocalStorageService.getStats();
    setState(() => _cacheStats = stats);
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an API key')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await AiSmsParser.initialize(key);
      setState(() => _aiEnabled = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ AI Parser enabled successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize AI: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('gemini_api_key');
    setState(() {
      _apiKeyController.clear();
      _aiEnabled = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key removed')),
      );
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // AI Parser Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: _aiEnabled ? Colors.amber : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI-Powered Parsing',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Chip(
                        label: Text(
                          _aiEnabled ? 'Enabled' : 'Disabled',
                          style: TextStyle(
                            color: _aiEnabled ? Colors.green : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        backgroundColor: _aiEnabled
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enable AI to automatically parse SMS from ANY bank or payment service, '
                    'including Airtel, Jio, and new services.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: 'Google Gemini API Key',
                      hintText: 'Enter your API key',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.key),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureKey ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() => _obscureKey = !_obscureKey);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      // Open link to get API key
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Get your free API key at: aistudio.google.com/app/apikey',
                          ),
                          duration: Duration(seconds: 5),
                        ),
                      );
                    },
                    child: Text(
                      'Get free API key from Google AI Studio →',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _saveApiKey,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: const Text('Save & Enable AI'),
                        ),
                      ),
                      if (_aiEnabled) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _clearApiKey,
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove API key',
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Info Card
          Card(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'How AI Parsing Works',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Automatically detects transactions from ANY bank\n'
                    '• Understands Airtel, Jio, and all payment apps\n'
                    '• Extracts amount, merchant, reference IDs\n'
                    '• Falls back to rule-based parsing if AI unavailable\n'
                    '• Your SMS data is processed securely',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Cache Stats Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.storage, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Local Cache',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Parsed transactions are cached locally to avoid re-processing.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow('Cached Transactions',
                      '${_cacheStats['transactions'] ?? 0}'),
                  _buildStatRow(
                      'Processed SMS', '${_cacheStats['processed_sms'] ?? 0}'),
                  _buildStatRow(
                      'AI-Parsed', '${_cacheStats['ai_parsed'] ?? 0}'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _clearCache,
                      icon: const Icon(Icons.delete_sweep),
                      label: const Text('Clear Cache & Re-parse All'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Supported Banks Info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rule-Based Parser (No AI)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Without AI, the app recognizes these senders:',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      'HDFC',
                      'SBI',
                      'ICICI',
                      'Axis',
                      'Kotak',
                      'Airtel',
                      'Jio',
                      'Paytm',
                      'GPay',
                      'PhonePe',
                      'Amazon',
                      'CRED',
                      'Slice',
                      'Jupiter',
                    ]
                        .map((bank) => Chip(
                              label: Text(bank,
                                  style: const TextStyle(fontSize: 11)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache?'),
        content: const Text(
          'This will delete all cached transactions and re-parse all SMS messages. '
          'This may use AI API calls if enabled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await LocalStorageService.clearAll();
      await _loadCacheStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Cache cleared. Pull to refresh on home screen.')),
        );
      }
    }
  }
}
