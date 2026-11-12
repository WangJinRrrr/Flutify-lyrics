import 'image.dart';

class SpotifyUser {
  final String id;
  final String displayName;
  final String email;
  final String product; // 'premium' or 'free'
  final String country;
  final List<SpotifyImage> images;

  const SpotifyUser({
    required this.id,
    required this.displayName,
    this.email = '',
    this.product = 'premium',
    this.country = 'US',
    this.images = const [],
  });

  /// 未登录时的占位用户（无昵称、无头像）。
  static const SpotifyUser guest = SpotifyUser(id: '', displayName: '', product: 'free', country: '');

  String get avatarUrl => images.isNotEmpty ? images.first.url : '';
  bool get isPremium => product.toLowerCase() == 'premium';

  factory SpotifyUser.fromJson(Map<String, dynamic> json) {
    return SpotifyUser(
      id: json['id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? 'Spotify User',
      email: json['email'] as String? ?? '',
      product: json['product'] as String? ?? 'premium',
      country: json['country'] as String? ?? 'US',
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => SpotifyImage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'display_name': displayName,
    'email': email,
    'product': product,
    'country': country,
    'images': images.map((e) => e.toJson()).toList(),
  };
}
