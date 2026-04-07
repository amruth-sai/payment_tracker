// lib/screens/category_management_screen.dart

import 'package:flutter/material.dart';
import '../models/standard_category.dart';
import '../models/custom_category.dart';
import '../models/category_preferences.dart';
import '../services/local_storage_service.dart';

class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  CategoryPreferences? _preferences;
  List<StandardCategory> _standardCategories = [];
  List<CustomCategory> _customCategories = [];
  bool _loading = true;

  // Predefined emoji options for custom categories
  static const _emojiOptions = [
    '🏷️',
    '🏋️',
    '🐾',
    '🎮',
    '🎸',
    '🌿',
    '🧘',
    '✈️',
    '👔',
    '🔧',
    '🎨',
    '📷',
    '🍺',
    '☕',
    '💇',
    '🛒',
    '🚴',
    '🧹',
    '🧳',
    '💒',
    '🐶',
    '🌮',
    '🏊',
    '🎭',
    '🧩',
    '💡',
    '📦',
    '🛠️',
    '🎁',
    '🏡',
  ];

  static const _colorOptions = [
    Colors.teal,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.indigo,
    Colors.green,
    Colors.red,
    Colors.blue,
    Colors.amber,
    Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await LocalStorageService.getCategoryPreferences();
    final standards = await LocalStorageService.getAllStandardCategories();
    final customs = await LocalStorageService.getAllCustomCategories();
    setState(() {
      _preferences = prefs;
      _standardCategories = standards;
      _customCategories = customs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Categories'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Standard Categories'),
            Tab(text: 'My Categories'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStandardCategoriesTab(),
                _buildCustomCategoriesTab(),
              ],
            ),
    );
  }

  Widget _buildStandardCategoriesTab() {
    if (_preferences == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final categories =
        _standardCategories.where((cat) => cat.id != 'uncategorized').toList();

    final categoriesById = {
      for (final category in categories) category.id: category
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        'Standard Categories',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Toggle categories on/off to customize which ones appear in your filters and analytics.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        ...StandardCategory.defaultGroups.map((group) {
          final groupedCategories = group.categoryIds
              .map((id) => categoriesById[id])
              .whereType<StandardCategory>()
              .toList();
          if (groupedCategories.isEmpty) {
            return const SizedBox.shrink();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      group.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              ...groupedCategories.map((category) {
                final isEnabled = _preferences!.isEnabled(category.id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: SwitchListTile(
                    value: isEnabled,
                    onChanged: (value) =>
                        _toggleStandardCategory(category, value),
                    title: Row(
                      children: [
                        Text(category.emoji,
                            style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(category.displayName)),
                      ],
                    ),
                    secondary: Icon(
                      isEnabled ? Icons.visibility : Icons.visibility_off,
                      color: isEnabled ? Colors.green : Colors.grey,
                    ),
                  ),
                );
              }),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildCustomCategoriesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.label_outline, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        'My Categories',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create custom labels to organize transactions your way. You can tag transactions with both a standard category and a custom label.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: _customCategories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🏷️', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 16),
                      const Text('No custom categories yet',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to create your first custom category',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => _showCustomCategoryEditor(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Custom Category'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _customCategories.length,
                  itemBuilder: (context, index) {
                    final cat = _customCategories[index];
                    return _CustomCategoryTile(
                      category: cat,
                      onEdit: () =>
                          _showCustomCategoryEditor(context, existing: cat),
                      onDelete: () => _deleteCustomCategory(cat),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _toggleStandardCategory(
      StandardCategory category, bool enabled) async {
    final CategoryPreferences newPrefs;
    if (enabled) {
      newPrefs = _preferences!.enableCategory(category.id);
    } else {
      newPrefs = _preferences!.disableCategory(category.id);
    }

    await LocalStorageService.saveCategoryPreferences(newPrefs);
    setState(() => _preferences = newPrefs);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? '${category.displayName} enabled'
                : '${category.displayName} disabled',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _deleteCustomCategory(CustomCategory cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Custom Category'),
        content: Text(
            'Delete "${cat.name}"? Transactions using this category will be unlinked.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await LocalStorageService.deleteCustomCategory(cat.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${cat.name}" deleted')),
        );
      }
    }
  }

  Future<void> _showCustomCategoryEditor(BuildContext context,
      {CustomCategory? existing}) async {
    final result = await showModalBottomSheet<CustomCategory>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _CustomCategoryEditor(
        existing: existing,
        emojiOptions: _emojiOptions,
        colorOptions: _colorOptions,
      ),
    );
    if (result != null) {
      await LocalStorageService.saveCustomCategory(result);
      await _load();
    }
  }
}

class _CustomCategoryTile extends StatelessWidget {
  final CustomCategory category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CustomCategoryTile({
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = category.color;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.25),
          child: Text(category.emoji, style: const TextStyle(fontSize: 20)),
        ),
        title: Text(category.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: onEdit),
            IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.red),
                onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

class _CustomCategoryEditor extends StatefulWidget {
  final CustomCategory? existing;
  final List<String> emojiOptions;
  final List<MaterialColor> colorOptions;

  const _CustomCategoryEditor({
    required this.existing,
    required this.emojiOptions,
    required this.colorOptions,
  });

  @override
  State<_CustomCategoryEditor> createState() => _CustomCategoryEditorState();
}

class _CustomCategoryEditorState extends State<_CustomCategoryEditor> {
  late final TextEditingController _nameController;
  late String _selectedEmoji;
  late int _selectedColorValue;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _selectedEmoji = widget.existing?.emoji ?? widget.emojiOptions.first;
    _selectedColorValue =
        widget.existing?.colorValue ?? widget.colorOptions.first.toARGB32();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(isEdit ? 'Edit Custom Category' : 'New Custom Category',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          // Preview
          Center(
            child: CircleAvatar(
              radius: 32,
              backgroundColor:
                  Color(_selectedColorValue).withValues(alpha: 0.25),
              child: Text(_selectedEmoji, style: const TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(height: 20),

          // Name field
          TextField(
            controller: _nameController,
            autofocus: !isEdit,
            decoration: const InputDecoration(
              labelText: 'Category Name',
              hintText: 'e.g. Gym, Pets, Music, Projects...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Emoji picker
          Text('Emoji', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.emojiOptions.map((e) {
              final selected = e == _selectedEmoji;
              return GestureDetector(
                onTap: () => setState(() => _selectedEmoji = e),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? Color(_selectedColorValue).withValues(alpha: 0.25)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: selected
                        ? Border.all(
                            color: Color(_selectedColorValue), width: 2)
                        : null,
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 20)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Color picker
          Text('Color', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.colorOptions.map((c) {
              final selected = c.toARGB32() == _selectedColorValue;
              return GestureDetector(
                onTap: () => setState(() => _selectedColorValue = c.toARGB32()),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(
                            color: theme.colorScheme.onSurface, width: 2)
                        : null,
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) return;
                    final cat = CustomCategory(
                      id: widget.existing?.id ??
                          'cat_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      emoji: _selectedEmoji,
                      colorValue: _selectedColorValue,
                      createdAt: widget.existing?.createdAt ?? DateTime.now(),
                    );
                    Navigator.pop(context, cat);
                  },
                  child: Text(isEdit ? 'Save' : 'Create'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
