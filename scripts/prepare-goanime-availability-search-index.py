#!/usr/bin/env python3
from pathlib import Path

path = Path('lib/services/availability_service.dart')
text = path.read_text()

def replace_once(old, new):
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'expected one target, got {count}: {old[:80]!r}')
    text = text.replace(old, new, 1)

replace_once(
    '  static final Map<String, AnimeModeAvailability> _modeKeys = {};\n',
    '  static final Map<String, AnimeModeAvailability> _modeKeys = {};\n'
    '  static final Map<String, Set<String>> _titleKeysByTitle = {};\n',
)

text = text.replace(
    '    _availableTitles.clear();\n    _availableKeys.clear();\n    _modeKeys.clear();\n',
    '    _availableTitles.clear();\n    _availableKeys.clear();\n    _modeKeys.clear();\n    _titleKeysByTitle.clear();\n',
)

replace_once(
    "      if (title.isNotEmpty) _availableTitles.add(title);\n      final modes = AnimeModeAvailability(\n",
    "      if (title.isNotEmpty) {\n        _availableTitles.add(title);\n        _titleKeysByTitle.putIfAbsent(title, () => <String>{}).addAll(entry.keys);\n      }\n      final modes = AnimeModeAvailability(\n",
)

replace_once(
    '    _availableTitles.add(normalizedTitle);\n    _availableKeys.addAll(keys);\n',
    '    _availableTitles.add(normalizedTitle);\n'
    '    _titleKeysByTitle.update(\n'
    '      normalizedTitle,\n'
    '      (existing) => <String>{...existing, ...keys},\n'
    '      ifAbsent: () => keys.toSet(),\n'
    '    );\n'
    '    _availableKeys.addAll(keys);\n',
)

replace_once(
    '    for (final title in _availableTitles) {\n      if (!_matchesConfirmed(title, mode: mode)) continue;\n      final score = _scoreLocalTitleMatch(title, normalizedQuery, queryTokens);\n',
    '    for (final title in _availableTitles) {\n'
    '      final keys =\n'
    '          _titleKeysByTitle[title] ?? TitleNormalizer.keysForTitle(title);\n'
    '      if (!_matchesConfirmedKeys(keys, mode: mode)) continue;\n'
    '      final score = _scoreLocalTitleMatch(title, normalizedQuery, queryTokens);\n',
)

old_matches = '''  static bool _matchesConfirmed(
    String title, {
    required AnimeAvailabilityMode mode,
  }) {
    final keys = TitleNormalizer.keysForTitle(title);
    if (mode == AnimeAvailabilityMode.any) {
      return keys.any(_availableKeys.contains) ||
          keys.any((key) => _availableKeys.contains('$key classico')) ||
          keys.any((key) => _availableKeys.contains('$key classic'));
    }

    final hasModeMatch = keys.any(
      (key) => _modeKeys[key]?.matches(mode) ?? false,
    );
    if (hasModeMatch) return true;

    final hasModeMetadata = keys.any(_modeKeys.containsKey);
    if (mode == AnimeAvailabilityMode.sub && !hasModeMetadata) {
      return keys.any(_availableKeys.contains);
    }
    return false;
  }
'''
new_matches = '''  static bool _matchesConfirmed(
    String title, {
    required AnimeAvailabilityMode mode,
  }) {
    return _matchesConfirmedKeys(
      TitleNormalizer.keysForTitle(title),
      mode: mode,
    );
  }

  static bool _matchesConfirmedKeys(
    Iterable<String> keys, {
    required AnimeAvailabilityMode mode,
  }) {
    if (mode == AnimeAvailabilityMode.any) {
      return keys.any(_availableKeys.contains) ||
          keys.any((key) => _availableKeys.contains('$key classico')) ||
          keys.any((key) => _availableKeys.contains('$key classic'));
    }

    final hasModeMatch = keys.any(
      (key) => _modeKeys[key]?.matches(mode) ?? false,
    );
    if (hasModeMatch) return true;

    final hasModeMetadata = keys.any(_modeKeys.containsKey);
    if (mode == AnimeAvailabilityMode.sub && !hasModeMetadata) {
      return keys.any(_availableKeys.contains);
    }
    return false;
  }
'''
replace_once(old_matches, new_matches)

old_replace = '''  static void _replaceCache(Iterable<String> titles) {
    _availableTitles
      ..clear()
      ..addAll(
        titles
            .map(TitleNormalizer.normalize)
            .where((title) => title.isNotEmpty),
      );
    _availableKeys
      ..clear()
      ..addAll(_availableTitles.expand(TitleNormalizer.keysForTitle));
  }
'''
new_replace = '''  static void _replaceCache(Iterable<String> titles) {
    _availableTitles.clear();
    _availableKeys.clear();
    _titleKeysByTitle.clear();
    for (final rawTitle in titles) {
      final title = TitleNormalizer.normalize(rawTitle);
      if (title.isEmpty || !_availableTitles.add(title)) continue;
      final keys = TitleNormalizer.keysForTitle(title);
      _titleKeysByTitle[title] = keys;
      _availableKeys.addAll(keys);
    }
  }
'''
replace_once(old_replace, new_replace)

replace_once(
    '      _availableTitles.add(title);\n      for (final key in TitleNormalizer.keysForTitle(title)) {\n',
    '      _availableTitles.add(title);\n'
    '      final keys = TitleNormalizer.keysForTitle(title);\n'
    '      _titleKeysByTitle[title] = keys;\n'
    '      for (final key in keys) {\n',
)

path.write_text(text)
