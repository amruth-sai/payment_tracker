// lib/screens/custom_categories_screen.dart
// Feature 3: Manage user-created custom categories

import 'package:flutter/material.dart';
import '../models/custom_category.dart';
import '../services/local_storage_service.dart';

class CustomCategoriesScreen extends StatefulWidget {
  const CustomCategoriesScreen({super.key});

  @override
  State<CustomCategoriesScreen> createState() => _CustomCategoriesScreenState();
}

class _CustomCategoriesScreenState extends State<CustomCategoriesScreen> {
  List<CustomCategory> _categories = [];
  bool _loading = true;

  // Predefined emoji options for quick pick
  static const _emojiOptions = [
    '🏷️', '🏋️', '🐾', '🎮', '🎸', '🌿', '🧘', '✈️', '👔', '🔧',
    '🎨', '📷', '🍺', '☕', '💇', '🛒', '🚴', '🧹', '🧳', '💒',
    '🐶', '🌮', '🏊', '🎭', '🧩', '💡', '📦', '🛠️', '🎁', '🏡',
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
    _load();
  }

  Future<void> _load() async {
    final cats = await LocalStorageService.getAllCustomCategories();
    setState(() {
      _categories = cats;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Categories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Category',
            onPressed: () => _showEditor(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _categories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🏷️',
                          style: theme.textTheme.displayMedium),
                      const SizedBox(height: 12),
                      Text('No custom categories yet',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                        'Tap + to create one',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => _showEditor(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Category'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    return _CategoryTile(
                      category: cat,
                      onEdit: () => _showEditor(context, existing: cat),
                      onDelete: () => _delete(cat),
                    );
                  },
                ),
      floatingActionButton: _categories.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: () => _showEditor(context),
              child: const Icon(Icons.add),
            ),
    );
  }

  Future<void> _delete(CustomCategory cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
            'Delete "${cat.name}"? Any transactions using this category will be unlinked.'),
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
    }
  }

  Future<void> _showEditor(BuildContext context,
      {CustomCategory? existing}) async {
    final result = await showModalBottomSheet<CustomCategory>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _CategoryEditor(
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

class _CategoryTile extends StatelessWidget {
  final CustomCategory category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryTile({
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = category.color;
    return Card(
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
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: onEdit),
            IconButton(
                icon:
                    const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

class _CategoryEditor extends StatefulWidget {
  final CustomCategory? existing;
  final List<String> emojiOptions;
  final List<MaterialColor> colorOptions;

  const _CategoryEditor({
    required this.existing,
    required this.emojiOptions,
    required this.colorOptions,
  });

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final TextEditingController _nameController;
  late String _selectedEmoji;
  late int _selectedColorValue;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.existing?.name ?? '');
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
          Text(isEdit ? 'Edit Category' : 'New Category',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          // Preview
          Center(
            child: CircleAvatar(
              radius: 32,
              backgroundColor:
                  Color(_selectedColorValue).withValues(alpha: 0.25),
              child: Text(_selectedEmoji,
                  style: const TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(height: 20),

          // Name field
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Category Name',
              hintText: 'e.g. Gym, Pets, Music...',
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
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 18)
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
