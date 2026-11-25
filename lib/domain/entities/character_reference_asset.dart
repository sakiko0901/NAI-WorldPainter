class CharacterReferenceAsset {
  final String id;
  final String game;
  final String category;
  final String name;
  final String variant;
  final int width;
  final int height;
  final int bytes;
  final List<String> thumbnailUrls;
  final List<String> downloadUrls;
  final List<String> aliases;

  /// SHA-256 of the expected or imported image bytes.
  final String? checksum;

  const CharacterReferenceAsset({
    required this.id,
    required this.game,
    required this.category,
    required this.name,
    required this.variant,
    required this.width,
    required this.height,
    required this.bytes,
    required this.thumbnailUrls,
    required this.downloadUrls,
    this.aliases = const [],
    this.checksum,
  });

  bool matches(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;
    final searchable =
        [name, game, category, variant, ...aliases].join(' ').toLowerCase();
    return normalizedQuery.split(RegExp(r'\s+')).every(searchable.contains);
  }
}

class SavedCharacterReference {
  final CharacterReferenceAsset asset;
  final String path;

  const SavedCharacterReference({required this.asset, required this.path});
}
