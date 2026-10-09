import 'package:equatable/equatable.dart';
import 'package:nai_huishi/domain/entities/nai_prompt_version.dart';

class LlmSession extends Equatable {
  final String id;
  final String title;
  final String scope;
  final String? contextKey;
  final NaiPromptVersion promptVersion;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LlmSession({
    required this.id,
    required this.title,
    this.scope = 'general',
    this.contextKey,
    this.promptVersion = NaiPromptVersion.v45,
    required this.createdAt,
    required this.updatedAt,
  });

  LlmSession copyWith({
    String? title,
    String? scope,
    String? contextKey,
    bool clearContextKey = false,
    NaiPromptVersion? promptVersion,
    DateTime? updatedAt,
  }) {
    return LlmSession(
      id: id,
      title: title ?? this.title,
      scope: scope ?? this.scope,
      contextKey: clearContextKey ? null : (contextKey ?? this.contextKey),
      promptVersion: promptVersion ?? this.promptVersion,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props =>
      [id, title, scope, contextKey, promptVersion, createdAt, updatedAt];
}
