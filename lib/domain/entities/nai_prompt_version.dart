import 'package:equatable/equatable.dart';

class NaiPromptVersion extends Equatable {
  static const v45 = NaiPromptVersion._('v4.5', 'V4.5');
  static const v5 = NaiPromptVersion._('v5', 'V5');

  final String value;
  final String label;

  const NaiPromptVersion._(this.value, this.label);

  static NaiPromptVersion fromValue(String? value) =>
      value == v45.value ? v45 : v5;

  @override
  List<Object?> get props => [value];
}
