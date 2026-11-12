class SpotifyDevice {
  final String id;
  final String name;
  final String type; // 'Computer', 'Smartphone', 'Speaker', 'CastVideo'
  final bool isActive;
  final bool isRestricted;
  final int volumePercent;

  const SpotifyDevice({
    required this.id,
    required this.name,
    required this.type,
    this.isActive = false,
    this.isRestricted = false,
    this.volumePercent = 80,
  });

  factory SpotifyDevice.fromJson(Map<String, dynamic> json) {
    return SpotifyDevice(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Device',
      type: json['type'] as String? ?? 'Computer',
      isActive: json['is_active'] as bool? ?? false,
      isRestricted: json['is_restricted'] as bool? ?? false,
      volumePercent: json['volume_percent'] as int? ?? 80,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'is_active': isActive,
    'is_restricted': isRestricted,
    'volume_percent': volumePercent,
  };
}
