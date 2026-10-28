/// Append a saved fragment without rewriting its tags, weights or line breaks.
/// Only the joining commas/whitespace are normalized.
String appendPromptFragment(String current, String fragment) {
  final next = fragment
      .replaceFirst(RegExp(r'^[\s,，]+'), '')
      .replaceFirst(RegExp(r'[\s,，]+$'), '');
  if (next.isEmpty) return current;
  final previous = current.replaceFirst(RegExp(r'[\s,，]+$'), '');
  if (previous.trim().isEmpty) return next;
  return '$previous, $next';
}
