class PubPackage {
  final String name;
  final String version;
  final String description;
  final int likes;
  final int pubPoints;
  final double popularity;
  final List<String> platforms;

  PubPackage({
    required this.name,
    required this.version,
    required this.description,
    required this.likes,
    required this.pubPoints,
    required this.popularity,
    required this.platforms,
  });

  factory PubPackage.fromJson(Map<String, dynamic> json) {
    return PubPackage(
      name: json['name'] ?? '',
      version: json['latest']?['version'] ?? '',
      description: json['latest']?['pubspec']?['description'] ?? '',
      likes: json['likes'] ?? 0,
      pubPoints: json['pubPoints'] ?? 0,
      popularity: (json['popularity'] ?? 0).toDouble(),
      platforms: List<String>.from(json['platforms'] ?? []),
    );
  }
}
