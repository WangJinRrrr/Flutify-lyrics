import 'package:flutter/material.dart';

class SpotifyCategory {
  final String id;
  final String name;
  final String iconUrl;
  final Color color;

  const SpotifyCategory({
    required this.id,
    required this.name,
    required this.iconUrl,
    required this.color,
  });

  factory SpotifyCategory.fromJson(Map<String, dynamic> json, [Color defaultColor = const Color(0xFF1DB954)]) {
    String icon = '';
    if (json['icons'] is List && (json['icons'] as List).isNotEmpty) {
      icon = json['icons'][0]['url'] as String? ?? '';
    } else if (json['icon_url'] is String) {
      icon = json['icon_url'] as String;
    }

    return SpotifyCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      iconUrl: icon,
      color: defaultColor,
    );
  }
}
