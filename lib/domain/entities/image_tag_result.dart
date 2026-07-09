import 'package:equatable/equatable.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';

/// 标签来源
enum TagSource { naiMetadata, wdTagger }

/// 单个标签条目
class TagEntry extends Equatable {
  final String tag;
  final double confidence; // 0~1，wd-tagger 有值；NAI 元数据默认 1.0
  final bool selected;

  const TagEntry({
    required this.tag,
    this.confidence = 1.0,
    this.selected = true,
  });

  TagEntry copyWith({bool? selected}) => TagEntry(
        tag: tag,
        confidence: confidence,
        selected: selected ?? this.selected,
      );

  @override
  List<Object?> get props => [tag, confidence, selected];
}

/// 图片解析结果
class ImageTagResult extends Equatable {
  final TagSource source;
  final List<TagEntry> general;
  final List<TagEntry> character;
  final String? negativePrompt;
  final List<TagEntry> negativeEntries;
  final List<CharacterSpec>? characters;
  final Map<String, dynamic>? metadata;

  const ImageTagResult({
    required this.source,
    this.general = const [],
    this.character = const [],
    this.negativePrompt,
    this.negativeEntries = const [],
    this.characters,
    this.metadata,
  });

  /// 将选中标签拼接为逗号分隔字符串
  String get selectedGeneralTags =>
      general.where((e) => e.selected).map((e) => e.tag).join(', ');

  String get selectedCharacterTags =>
      character.where((e) => e.selected).map((e) => e.tag).join(', ');

  String get selectedNegativeTags =>
      negativeEntries.where((e) => e.selected).map((e) => e.tag).join(', ');

  ImageTagResult copyWithTagSelections({
    List<TagEntry>? general,
    List<TagEntry>? character,
    List<TagEntry>? negativeEntries,
  }) =>
      ImageTagResult(
        source: source,
        general: general ?? this.general,
        character: character ?? this.character,
        negativePrompt: negativePrompt,
        negativeEntries: negativeEntries ?? this.negativeEntries,
        characters: characters,
        metadata: metadata,
      );

  /// JSON 序列化（用于缓存）
  Map<String, dynamic> toJson() => {
        'source': source.index,
        'general': general.map((e) => e.toJson()).toList(),
        'character': character.map((e) => e.toJson()).toList(),
        'negativePrompt': negativePrompt,
        'negativeEntries': negativeEntries.map((e) => e.toJson()).toList(),
        'characters': characters?.map((e) => e.toJson()).toList(),
        'metadata': metadata,
      };

  factory ImageTagResult.fromJson(Map<String, dynamic> json) {
    List<TagEntry> parseList(List<dynamic>? list) =>
        list?.map((e) => TagEntryJson.fromJson(e as Map<String, dynamic>)).toList() ?? [];

    return ImageTagResult(
      source: TagSource.values[json['source'] as int? ?? 0],
      general: parseList(json['general'] as List<dynamic>?),
      character: parseList(json['character'] as List<dynamic>?),
      negativePrompt: json['negativePrompt'] as String?,
      negativeEntries: parseList(json['negativeEntries'] as List<dynamic>?),
      characters: (json['characters'] as List<dynamic>?)
          ?.map((e) => CharacterSpec.fromJson(e as Map<String, dynamic>))
          .toList(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  List<Object?> get props => [source, general, character, negativePrompt, negativeEntries, characters, metadata];
}

extension TagEntryJson on TagEntry {
  Map<String, dynamic> toJson() => {
        'tag': tag,
        'confidence': confidence,
        'selected': selected,
      };

  static TagEntry fromJson(Map<String, dynamic> json) => TagEntry(
        tag: json['tag'] as String,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
        selected: json['selected'] as bool? ?? true,
      );
}
