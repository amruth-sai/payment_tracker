import 'package:flutter/material.dart';

/// A category created and owned by the user. No categories are seeded.
class AppCategory {
  const AppCategory({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorValue,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String emoji;
  final int colorValue;
  final DateTime createdAt;

  Color get color => Color(colorValue);

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name.trim(),
    'emoji': emoji,
    'color_value': colorValue,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory AppCategory.fromMap(Map<String, dynamic> map) => AppCategory(
    id: map['id'] as String,
    name: map['name'] as String,
    emoji: map['emoji'] as String,
    colorValue: map['color_value'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
  );

  AppCategory copyWith({String? name, String? emoji, int? colorValue}) =>
      AppCategory(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        colorValue: colorValue ?? this.colorValue,
        createdAt: createdAt,
      );
}
