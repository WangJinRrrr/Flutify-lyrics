class SpotifyImage {
  final String url;
  final int? height;
  final int? width;

  const SpotifyImage({
    required this.url,
    this.height,
    this.width,
  });

  factory SpotifyImage.fromJson(Map<String, dynamic> json) {
    return SpotifyImage(
      url: json['url'] as String? ?? '',
      height: json['height'] as int?,
      width: json['width'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'height': height,
    'width': width,
  };
}
