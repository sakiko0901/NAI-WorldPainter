import 'package:nai_huishi/domain/entities/tag_completion.dart';
import 'package:nai_huishi/domain/entities/tag_search_match.dart';

String normalizeTagSearch(String query) => normalizeCompletionTag(query)
    .replaceAll(r'\(', '(')
    .replaceAll(r'\)', ')')
    .replaceAll(RegExp('_+'), '_');

/// Indexed candidate ranges, not an exhaustive spelling dictionary. Four-letter
/// anchors limit fan-out; short inputs never get spelling expansion.
Set<String> tagSearchPrefixes(String q) {
  final prefixes = <String>{q};
  for (final word in q.split('_').where((word) => word.length >= 3).take(4)) {
    prefixes.add(word);
  }
  if (q.length < 4 ||
      q.length > 64 ||
      !RegExp(r'^[a-z0-9_():.\-]+$').hasMatch(q)) {
    return prefixes;
  }
  final anchor = q.substring(0, 4);
  prefixes.add(anchor);
  const letters = 'abcdefghijklmnopqrstuvwxyz0123456789_';
  // One typo in the anchor: omission, insertion, substitution or transposition.
  for (var i = 0; i < anchor.length; i++) {
    prefixes.add(anchor.substring(0, i) + anchor.substring(i + 1));
    for (final letter in letters.split('')) {
      prefixes.add(anchor.substring(0, i) + letter + anchor.substring(i + 1));
      prefixes.add(anchor.substring(0, i) + letter + anchor.substring(i));
    }
    if (i + 1 < anchor.length) {
      prefixes.add(anchor.substring(0, i) +
          anchor[i + 1] +
          anchor[i] +
          anchor.substring(i + 2));
    }
  }
  return prefixes;
}

/// Bounded optimal-string-alignment distance, including adjacent transpositions.
int tagEditDistance(String a, String b, int maximum) {
  if (a.isEmpty || b.isEmpty)
    return (a.length + b.length).clamp(0, maximum + 1);
  if ((a.length - b.length).abs() > maximum) return maximum + 1;
  var previous = List.generate(b.length + 1, (i) => i);
  List<int>? older;
  for (var i = 1; i <= a.length; i++) {
    final current = List.filled(b.length + 1, maximum + 1)..[0] = i;
    for (var j = (i - maximum).clamp(1, b.length);
        j <= (i + maximum).clamp(0, b.length);
        j++) {
      var best = previous[j] + 1;
      if (current[j - 1] + 1 < best) best = current[j - 1] + 1;
      final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      if (substitution < best) best = substitution;
      if (older != null &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1] &&
          older[j - 2] + 1 < best) {
        best = older[j - 2] + 1;
      }
      current[j] = best;
    }
    older = previous;
    previous = current;
  }
  return previous.last;
}

/// Runs in a worker isolate; all candidates come from catalog records.
List<TagSearchMatch> rankLocalTagCandidates(Map<String, Object> input) {
  final q = input['query'] as String;
  final limit = input['limit'] as int;
  final rows = input['rows'] as List<Map<String, Object?>>;
  final chinese = RegExp(r'[\u3400-\u9fff]').hasMatch(q);
  final words = q.split('_').where((word) => word.isNotEmpty).toList();
  final found = <String, TagSearchMatch>{};
  const ranks = {
    'exact': 0,
    'alias': 1,
    'translation': 2,
    'prefix': 3,
    'words': 4,
    'fuzzy': 5
  };
  int compare(TagSearchMatch a, TagSearchMatch b) {
    var order = ranks[a.kind]!.compareTo(ranks[b.kind]!);
    if (order == 0) order = a.distance.compareTo(b.distance);
    if (order == 0) order = b.tag.count.compareTo(a.tag.count);
    return order == 0 ? a.tag.tag.compareTo(b.tag.tag) : order;
  }

  for (final row in rows) {
    final name = row['name'] as String;
    final term = row['term'] as String? ?? name;
    final translation = row['translation'] as String;
    String? kind;
    var distance = 0;
    if (name == q) {
      kind = 'exact';
    } else if (row['kind'] == 1 && term == q) {
      kind = 'alias';
    } else if (chinese && translation.contains(q.replaceAll('_', ' '))) {
      kind = 'translation';
    } else if (!chinese && term.startsWith(q)) {
      kind = 'prefix';
    } else if (words.length > 1 &&
        words.every((word) => chinese
            ? translation.contains(word)
            : name.split('_').any((part) => part.startsWith(word)))) {
      kind = 'words';
    } else if (!chinese && q.length >= 4 && q.length <= 64) {
      // Character tags often have a copyright qualifier. Correct the short
      // name only when the query did not explicitly specify that qualifier;
      // retain every canonical qualifier in the returned candidates.
      final comparable = !q.contains('_(') && term.contains('_(')
          ? term.substring(0, term.indexOf('_('))
          : term;
      if (comparable.length <= 66) {
        final maximum = q.length >= 8 ? 2 : 1;
        distance = tagEditDistance(q, comparable, maximum);
        if (distance <= maximum) kind = 'fuzzy';
      }
    }
    if (kind == null) continue;
    final match = TagSearchMatch(
        TagCompletion(
            tag: name,
            translation: translation,
            category: row['category'] as int,
            count: row['post_count'] as int,
            alias: row['kind'] == 1 ? term : null),
        kind,
        distance: distance,
        matchedTerm: term);
    if (found[name] == null || compare(match, found[name]!) < 0)
      found[name] = match;
  }
  final results = found.values.toList()..sort(compare);
  return results.take(limit).toList(growable: false);
}
