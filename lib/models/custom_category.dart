// lib/models/custom_category.dart

import 'package:flutter/material.dart';

/// A user-created category (Feature 3)
class CustomCategory {
  final String id;
  final String name;
  final String emoji; // e.g. '🏋️', '🐾'
  final int colorValue; // Color stored as int (Color.value)
  final DateTime createdAt;

  CustomCategory({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorValue,
    required this.createdAt,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'color_value': colorValue,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory CustomCategory.fromMap(Map<String, dynamic> map) => CustomCategory(
        id: map['id'] as String,
        name: map['name'] as String,
        emoji: map['emoji'] as String? ?? '🏷️',
        colorValue: map['color_value'] as int? ?? Colors.teal.toARGB32(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );

  CustomCategory copyWith({
    String? name,
    String? emoji,
    int? colorValue,
  }) =>
      CustomCategory(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        colorValue: colorValue ?? this.colorValue,
        createdAt: createdAt,
      );
}
