from pathlib import Path
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


builder_path = root / "tools/manga/manga_availability_v3_builder.dart"
text = builder_path.read_text()
text = replace_once(
    text,
    "static const int builderVersion = 4;",
    "static const int builderVersion = 5;",
    "builder version",
)
text = replace_once(
    text,
    "    'genres',\n    'format',",
    "    'genres',\n    'synopsis',\n    'score',\n    'format',",
    "builder work keys",
)
text = replace_once(
    text,
    "            'genresJson': jsonEncode(_strings(work['genres'])),\n            'format': work['format'],",
    "            'genresJson': jsonEncode(_strings(work['genres'])),\n            'synopsis': work['synopsis'],\n            'score': work['score'],\n            'format': work['format'],",
    "builder insert",
)
text = replace_once(
    text,
    "      _stringList(work['genres'], '$context.genres');\n      _safeCover(work['coverReference'], '$context.coverReference');",
    "      _stringList(work['genres'], '$context.genres');\n      if (work['synopsis'] != null) {\n        _text(work['synopsis'], '$context.synopsis');\n      }\n      _score(work['score'], '$context.score');\n      _safeCover(work['coverReference'], '$context.coverReference');",
    "builder validation",
)
text = replace_once(
    text,
    "        genresJson TEXT NOT NULL,\n        format TEXT NOT NULL,",
    "        genresJson TEXT NOT NULL,\n        synopsis TEXT,\n        score REAL,\n        format TEXT NOT NULL,",
    "builder schema",
)
text = replace_once(
    text,
    "  static String _utc(Object? raw, [String context = 'timestamp']) {",
    "  static double? _score(Object? raw, String context) {\n    if (raw == null) return null;\n    if (raw is! num) {\n      throw FormatException('$context must be numeric or null.');\n    }\n    final value = raw.toDouble();\n    if (!value.isFinite || value <= 0 || value > 10) {\n      throw FormatException('$context must be greater than 0 and at most 10.');\n    }\n    return value;\n  }\n\n  static String _utc(Object? raw, [String context = 'timestamp']) {",
    "builder score helper",
)
builder_path.write_text(text)

test_path = root / "test/tools/manga_availability_v3_builder_test.dart"
text = test_path.read_text()
text = replace_once(
    text,
    "expect(metadata['builderVersion'], '4');",
    "expect(metadata['builderVersion'], '5');",
    "builder test version",
)
test_path.write_text(text)

source_path = root / "lib/services/manga/manga_bundled_catalog_source.dart"
text = source_path.read_text()
text = replace_once(
    text,
    "  static const int builderVersion = 4;\n  static const int legacySchemaVersion = 2;",
    "  static const int builderVersion = 5;\n  static const int previousBuilderVersion = 4;\n  static const int legacySchemaVersion = 2;",
    "source versions",
)
text = replace_once(
    text,
    "  int? _openedSchemaVersion;\n  DateTime? _generatedAt;",
    "  int? _openedSchemaVersion;\n  int? _openedBuilderVersion;\n  DateTime? _generatedAt;",
    "source builder state",
)
text = replace_once(
    text,
    "    final metadata = <String, MangaBrowseMetadata>{};\n    try {\n      for (final chunk in _chunks(ids)) {\n        final rows = await database.query(\n          'works',\n          columns: [\n            'workId',\n            'artistsJson',\n            'genresJson',\n            'format',\n            'status',\n            'countryOfOrigin',\n          ],",
    "    final metadata = <String, MangaBrowseMetadata>{};\n    final richMetadata =\n        _openedSchemaVersion == schemaVersion &&\n        _openedBuilderVersion == builderVersion;\n    try {\n      for (final chunk in _chunks(ids)) {\n        final rows = await database.query(\n          'works',\n          columns: [\n            'workId',\n            'artistsJson',\n            'genresJson',\n            if (richMetadata) 'synopsis',\n            if (richMetadata) 'score',\n            'format',\n            'status',\n            'countryOfOrigin',\n          ],",
    "source metadata columns",
)
text = replace_once(
    text,
    "    _openedSchemaVersion = null;\n    _generatedAt = null;",
    "    _openedSchemaVersion = null;\n    _openedBuilderVersion = null;\n    _generatedAt = null;",
    "source close reset",
)
text = replace_once(
    text,
    "        _openedSchemaVersion = validation.schemaVersion;\n        _generatedAt = validation.generatedAt;",
    "        _openedSchemaVersion = validation.schemaVersion;\n        _openedBuilderVersion = validation.builderVersion;\n        _generatedAt = validation.generatedAt;",
    "source init state",
)
text = replace_once(
    text,
    "      _openedSchemaVersion = null;\n      _generatedAt = null;",
    "      _openedSchemaVersion = null;\n      _openedBuilderVersion = null;\n      _generatedAt = null;",
    "source failure reset",
)
text = replace_once(
    text,
    "  static Future<({int schemaVersion, DateTime generatedAt})> _validate(",
    "  static Future<({int schemaVersion, int builderVersion, DateTime generatedAt})> _validate(",
    "source validation signature",
)
text = replace_once(
    text,
    "    final isLegacy =\n        schema == legacySchemaVersion && builder == legacyBuilderVersion;\n    final isCurrent = schema == schemaVersion && builder == builderVersion;\n    if (!isLegacy && !isCurrent) {",
    "    final isLegacy =\n        schema == legacySchemaVersion && builder == legacyBuilderVersion;\n    final isPreviousCurrent =\n        schema == schemaVersion && builder == previousBuilderVersion;\n    final isCurrent = schema == schemaVersion && builder == builderVersion;\n    if (!isLegacy && !isPreviousCurrent && !isCurrent) {",
    "source compatibility",
)
text = replace_once(
    text,
    "    if (isLegacy) {\n      await _requireColumns(database, 'source_links', const {",
    "    if (isCurrent) {\n      await _requireColumns(database, 'works', const {'synopsis', 'score'});\n    }\n\n    if (isLegacy) {\n      await _requireColumns(database, 'source_links', const {",
    "source rich columns",
)
text = replace_once(
    text,
    "    final expectedReadable = isCurrent\n        ? int.tryParse(metadata['readableLinksCount'] ?? '')\n        : expectedLinks;",
    "    final expectedReadable = isLegacy\n        ? expectedLinks\n        : int.tryParse(metadata['readableLinksCount'] ?? '');",
    "source readable compatibility",
)
text = replace_once(
    text,
    "    final workRows = await database.query(\n      'works',\n      columns: [\n        'workId',\n        'canonicalTitle',\n        'alternativeTitlesJson',\n        'authorsJson',\n        'artistsJson',\n        'genresJson',\n        'format',\n        'status',\n        'coverReference',\n      ],\n    );",
    "    final workRows = await database.query(\n      'works',\n      columns: [\n        'workId',\n        'canonicalTitle',\n        'alternativeTitlesJson',\n        'authorsJson',\n        'artistsJson',\n        'genresJson',\n        if (isCurrent) 'synopsis',\n        if (isCurrent) 'score',\n        'format',\n        'status',\n        'coverReference',\n      ],\n    );",
    "source validation columns",
)
text = replace_once(
    text,
    "          !_isEnumName(MangaFormat.values, row['format']) ||\n          !_isEnumName(MangaPublicationStatus.values, row['status'])) {",
    "          !_isEnumName(MangaFormat.values, row['format']) ||\n          !_isEnumName(MangaPublicationStatus.values, row['status']) ||\n          (isCurrent && !_isOptionalText(row['synopsis'])) ||\n          (isCurrent && !_isOptionalScore(row['score']))) {",
    "source work validation",
)
text = replace_once(
    text,
    "    return (schemaVersion: schema!, generatedAt: generatedAt);",
    "    return (\n      schemaVersion: schema!,\n      builderVersion: builder!,\n      generatedAt: generatedAt,\n    );",
    "source validation return",
)
text = replace_once(
    text,
    "    return MangaBrowseMetadata(\n      artists: _decodeStringList(row['artistsJson']),\n      genres: _decodeStringList(row['genresJson']),\n      format:",
    "    return MangaBrowseMetadata(\n      artists: _decodeStringList(row['artistsJson']),\n      genres: _decodeStringList(row['genresJson']),\n      synopsis: _requiredString(row['synopsis']),\n      score: _scoreFromRow(row['score']),\n      format:",
    "source metadata mapping",
)
text = replace_once(
    text,
    "  static String? _requiredString(Object? value) {\n    final text = value?.toString().trim();\n    return text == null || text.isEmpty ? null : text;\n  }",
    "  static String? _requiredString(Object? value) {\n    final text = value?.toString().trim();\n    return text == null || text.isEmpty ? null : text;\n  }\n\n  static bool _isOptionalText(Object? value) =>\n      value == null || _requiredString(value) != null;\n\n  static bool _isOptionalScore(Object? value) {\n    if (value == null) return true;\n    if (value is! num) return false;\n    final score = value.toDouble();\n    return score.isFinite && score > 0 && score <= 10;\n  }\n\n  static double? _scoreFromRow(Object? value) {\n    if (!_isOptionalScore(value) || value == null) return null;\n    return (value as num).toDouble();\n  }",
    "source metadata helpers",
)
source_path.write_text(text)
