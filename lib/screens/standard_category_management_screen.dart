// lib/screens/standard_category_management_screen.dart

import 'package:flutter/material.dart';
import '../models/standard_category.dart';
import '../services/local_storage_service.dart';

class StandardCategoryManagementScreen extends StatefulWidget {
  const StandardCategoryManagementScreen({super.key});

  @override
  State<StandardCategoryManagementScreen> createState() => _StandardCategoryManagementScreenState();
}

class _StandardCategoryManagementScreenState extends State<StandardCategoryManagementScreen> {
  List<StandardCategory> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final categories = await LocalStorageService.getAllStandardCategories();
      setState(() {
        _categories = categories;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load categories: $e')),
        );
      }
    }
  }

  Future<void> _toggleCategoryStatus(StandardCategory category) async {
    try {
      await LocalStorageService.updateStandardCategoryStatus(
        category.id,
        !category.isActive,
      );
      await _loadCategories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update category: $e')),
        );
      }
    }
  }

  Future<void> _deleteCategory(StandardCategory category) async {
    if (category.isDefault) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete default categories. Disable them instead.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${category.displayName}'),
        content: const Text(
          'Are you sure you want to delete this category? '
          'Transactions using this category will be moved to "Uncategorized".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await LocalStorageService.deleteStandardCategory(category.id);
        await _loadCategories();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${category.displayName} deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete category: $e')),
          );
        }
      }
    }
  }

  Future<void> _addOrEditCategory([StandardCategory? category]) async {
    final result = await showDialog<StandardCategory>(
      context: context,
      builder: (context) => _CategoryEditDialog(category: category),
    );

    if (result != null) {
      try {
        await LocalStorageService.saveStandardCategory(result);
        await _loadCategories();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                category == null
                  ? '${result.displayName} created'
                  : '${result.displayName} updated',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save category: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Standard Categories'),
        actions: [
          IconButton(
            onPressed: () => _addOrEditCategory(),
            icon: const Icon(Icons.add),
            tooltip: 'Add Category',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _categories.isEmpty
              ? const Center(
                  child: Text('No categories found'),
                )
              : ListView.builder(
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 4.0,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: category.color.withValues(alpha: 0.2),
                          child: Text(
                            category.emoji,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                        title: Text(category.displayName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (category.isDefault)
                              const Text(
                                'Default Category',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontSize: 12,
                                ),
                              ),
                            Text(
                              category.isActive ? 'Active' : 'Disabled',
                              style: TextStyle(
                                color: category.isActive
                                    ? Colors.green
                                    : Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: category.isActive,
                              onChanged: (_) => _toggleCategoryStatus(category),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (action) {
                                switch (action) {
                                  case 'edit':
                                    _addOrEditCategory(category);
                                    break;
                                  case 'delete':
                                    _deleteCategory(category);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    leading: Icon(Icons.edit),
                                    title: Text('Edit'),
                                  ),
                                ),
                                if (!category.isDefault)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      leading: Icon(Icons.delete, color: Colors.red),
                                      title: Text('Delete'),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _CategoryEditDialog extends StatefulWidget {
  final StandardCategory? category;

  const _CategoryEditDialog({this.category});

  @override
  State<_CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<_CategoryEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _emojiController;
  late Color _selectedColor;
  final _formKey = GlobalKey<FormState>();

  // Common emojis for categories
  static const _commonEmojis = [
    '🍕', '🚗', '🛍️', '🏠', '💳', '🎬', '💡', '🏥', '📚', '💰',
    '🔄', '🎁', '📈', '📌', '❓', '💼', '🛒', '☕', '🎵', '🎮',
    '📱', '✈️', '🚌', '⛽', '🎯', '🔧', '💻', '👕', '🍷', '🏋️',
    '🐾', '🌳', '⚡', '🚨', '🎨', '🍔', '📦', '🎪', '🏆', '🎂',
  ];

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _nameController = TextEditingController(text: category?.name ?? '');
    _displayNameController = TextEditingController(text: category?.displayName ?? '');
    _emojiController = TextEditingController(text: category?.emoji ?? '🏷️');
    _selectedColor = category?.color ?? Colors.teal;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  void _selectEmoji(String emoji) {
    setState(() {
      _emojiController.text = emoji;
    });
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Color'),
        content: SizedBox(
          width: 300,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 6,
            children: [
              Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
              Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
              Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
              Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
              Colors.brown, Colors.grey, Colors.blueGrey, Colors.black,
            ].map((color) => GestureDetector(
              onTap: () {
                setState(() {
                  _selectedColor = color;
                });
                Navigator.of(context).pop();
              },
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: _selectedColor == color
                    ? Border.all(color: Colors.white, width: 3)
                    : null,
                ),
              ),
            )).toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.category != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Category' : 'Add Category'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name (used internally)',
                  hintText: 'e.g., foodDining, customCategory1',
                ),
                validator: (value) {
                  if (value?.trim().isEmpty == true) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  hintText: 'e.g., Food & Dining, Custom Category',
                ),
                validator: (value) {
                  if (value?.trim().isEmpty == true) {
                    return 'Display name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _emojiController,
                      decoration: const InputDecoration(
                        labelText: 'Emoji',
                        hintText: '🏷️',
                      ),
                      validator: (value) {
                        if (value?.trim().isEmpty == true) {
                          return 'Emoji is required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _selectedColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        _emojiController.text.isNotEmpty ? _emojiController.text : '🏷️',
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Common Emojis:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _commonEmojis.map((emoji) => GestureDetector(
                  onTap: () => _selectEmoji(emoji),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 20)),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Color: '),
                  GestureDetector(
                    onTap: _showColorPicker,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _selectedColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _showColorPicker,
                    child: const Text('Change'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState?.validate() == true) {
              final category = StandardCategory(
                id: widget.category?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
                name: _nameController.text.trim(),
                displayName: _displayNameController.text.trim(),
                emoji: _emojiController.text.trim(),
                colorValue: _selectedColor.toARGB32(),
                isDefault: widget.category?.isDefault ?? false,
                isActive: widget.category?.isActive ?? true,
                sortOrder: widget.category?.sortOrder ?? DateTime.now().millisecondsSinceEpoch,
                createdAt: widget.category?.createdAt ?? DateTime.now(),
              );
              Navigator.of(context).pop(category);
            }
          },
          child: Text(isEditing ? 'Update' : 'Create'),
        ),
      ],
    );
  }
}