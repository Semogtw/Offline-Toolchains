import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:goanime_core/goanime_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DynamicAvailabilityMode { any, sub, dub }

class DynamicAvailabilityEntry {
  static const Duration verifiedEntryTtl = Duration(days: 14);
  static const Duration maxFutureSkew = Duration(minutes: 5);

  const DynamicAvailabilityEntry({
    required this.title,
    required this.normalizedTitle,
    required this.keys,
    required this.hasSub,
    required this.hasDub,
    required this.verifiedAt,
    this.malId,
    this.providerId,
    this.providerName,
    this.providerTitle,
  });

  final String title;
  final String normalizedTitle;
  final List<String> keys;
  final bool hasSub;
  final bool hasDub;
  final DateTime verifiedAt;
  final int? malId;
  final String? providerId;
  final String? providerName;
  final String? providerTitle;

  factory DynamicAvailabilityEntry.create({
    required String title,
    required Iterable<String> keys,
    required bool hasSub,
    required bool hasDub,
    DateTime? verifiedAt,
    int? malId,
    String? providerId,
    String? providerName,
    String? providerTitle,
  }) {
    final normalizedTitle = TitleNormalizer.normalize(title);
    return DynamicAvailabilityEntry(
      title: title,
      normalizedTitle: normalizedTitle,
      keys: keys.toSet().toList()..sort(),
      hasSub: hasSub,
      hasDub: hasDub,
      verifiedAt: verifiedAt ?? DateTime.now().toUtc(),
      malId: malId,
      providerId: _normalizeProviderId(providerId),
      providerName: providerName,
      providerTitle: providerTitle,
    );
  }

  factory DynamicAvailabilityEntry.fromJson(Map<String, dynamic> json) {
    final title = json['title']?.toString() ?? '';
    final normalizedTitle =
        json['normalizedTitle']?.toString() ?? TitleNormalizer.normalize(title);
    return DynamicAvailabilityEntry(
      title: title,
      normalizedTitle: normalizedTitle,
      keys:
          (json['keys'] as List<dynamic>?)
              ?.map((key) => key.toString())
              .where((key) => key.isNotEmpty)
              .toSet()
              .toList() ??
          TitleNormalizer.keysForTitle(normalizedTitle).toList(),
      hasSub: json['hasSub'] == true,
      hasDub: json['hasDub'] == true,
      verifiedAt:
          DateTime.tryParse(json['verifiedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      malId: json['malId'] is int ? json['malId'] as int : null,
      providerId: _normalizeProviderId(json['providerId']?.toString()),
      providerName: json['providerName']?.toString(),
      providerTitle: json['providerTitle']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'normalizedTitle': normalizedTitle,
    'keys': keys,
    'hasSub': hasSub,
    'hasDub': hasDub,
    'verifiedAt': verifiedAt.toUtc().toIso8601String(),
    if (malId != null) 'malId': malId,
    if (providerId != null) 'providerId': providerId,
    if (providerName != null) 'providerName': providerName,
    if (providerTitle != null) 'providerTitle': providerTitle,
  };

  DynamicAvailabilityEntry merge(DynamicAvailabilityEntry other) {
    final mergedKeys = {...keys, ...other.keys}.toList()..sort();
    return DynamicAvailabilityEntry(
      title: other.title.isNotEmpty ? other.title : title,
      normalizedTitle: other.normalizedTitle.isNotEmpty
          ? other.normalizedTitle
          : normalizedTitle,
      keys: mergedKeys,
      hasSub: hasSub || other.hasSub,
      hasDub: hasDub || other.hasDub,
      verifiedAt: other.verifiedAt.isAfter(verifiedAt)
          ? other.verifiedAt
          : verifiedAt,
      malId: other.malId ?? malId,
      providerId: other.providerId ?? providerId,
      providerName: other.providerName ?? providerName,
      providerTitle: other.providerTitle ?? providerTitle,
    );
  }

  bool isFreshAt(DateTime now) {
    final current = now.toUtc();
    final verified = verifiedAt.toUtc();
    if (verified.year == 1970 || verified.isAfter(current.add(maxFutureSkew))) {
      return false;
    }
    final age = current.difference(verified);
    return age <= verifiedEntryTtl;
  }

  bool get isFresh => isFreshAt(DateTime.now().toUtc());

  static String? _normalizeProviderId(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class DynamicAvailabilityCache {
  static const String _legacyStorageKey = 'dynamic_availability_keys';
  static const String _entriesStorageKey = 'dynamic_availability_entries_v1';
  static Set<String> _cachedKeys = {};
  static final Map<String, DynamicAvailabilityEntry> _entriesByTitle = {};
  static bool _initialized = false;
  static final ValueNotifier<int> updateNotifier = ValueNotifier(0);

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final keysList = prefs.getStringList(_legacyStorageKey) ?? [];
      _cachedKeys = keysList.toSet();
      _entriesByTitle.clear();
      for (final entry in _readEntries(prefs)) {
        if (!entry.isFresh) continue;
        _cachedKeys.addAll(entry.keys);
        final identity = _identityFor(entry);
        final previous = _entriesByTitle[identity];
        _entriesByTitle[identity] = previous == null
            ? entry
            : previous.merge(entry);
      }
      _initialized = true;
    } catch (e) {
      // Falha silenciosa: se o cache local falhar, começa vazio
      _initialized = true;
    }
  }

  static Set<String> get keys => _cachedKeys;
  static Set<String> get freshKeys => _entriesByTitle.values
      .where((entry) => entry.isFresh)
      .expand((entry) => entry.keys)
      .toSet();
  static List<DynamicAvailabilityEntry> get entries => _entriesByTitle.values
      .where((entry) => entry.isFresh)
      .toList(growable: false);

  static bool isTitleAvailable(
    Iterable<String> titles, {
    String? providerId,
    DynamicAvailabilityMode mode = DynamicAvailabilityMode.any,
  }) {
    final normalizedProvider = _normalizeProviderId(providerId);
    final freshEntries = entries;
    if (freshEntries.isEmpty) return false;
    for (final title in titles) {
      for (final key in TitleNormalizer.keysForTitle(title)) {
        for (final entry in freshEntries) {
          if (!entry.keys.contains(key) ||
              (normalizedProvider != null &&
                  entry.providerId != normalizedProvider)) {
            continue;
          }
          final matches = switch (mode) {
            DynamicAvailabilityMode.any => entry.hasSub || entry.hasDub,
            DynamicAvailabilityMode.sub => entry.hasSub,
            DynamicAvailabilityMode.dub => entry.hasDub,
          };
          if (matches) return true;
        }
      }
    }
    return false;
  }

  static int countForProvider(String providerId) {
    final normalizedProvider = _normalizeProviderId(providerId);
    if (normalizedProvider == null) return 0;
    return entries
        .where((entry) => entry.providerId == normalizedProvider)
        .length;
  }

  static Future<void> addKey(String key) async {
    if (!_initialized) await initialize();
    if (_cachedKeys.contains(key)) return;

    _cachedKeys.add(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_legacyStorageKey, _cachedKeys.toList());
    } catch (e) {
      // Ignora falhas de escrita
    }
  }

  static Future<void> addKeys(Iterable<String> keysToAdd) async {
    if (!_initialized) await initialize();
    final initialLength = _cachedKeys.length;
    _cachedKeys.addAll(keysToAdd);

    if (_cachedKeys.length > initialLength) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_legacyStorageKey, _cachedKeys.toList());
      } catch (e) {
        // Ignora falhas de escrita
      }
    }
  }

  static Future<void> addEntry(DynamicAvailabilityEntry entry) async {
    if (!_initialized) await initialize();
    if (entry.normalizedTitle.isEmpty || entry.keys.isEmpty || !entry.isFresh) {
      return;
    }

    final previous = _entriesByTitle[_identityFor(entry)];
    final next = previous == null ? entry : previous.merge(entry);
    _entriesByTitle[_identityFor(next)] = next;
    _cachedKeys.addAll(next.keys);
    await _persist();
    updateNotifier.value++;
  }

  static List<Map<String, dynamic>> exportVerifiedEntries() =>
      entries.map((entry) => entry.toJson()).toList(growable: false);

  static String exportVerifiedEntriesJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return '${encoder.convert({'schemaVersion': 1, 'generatedAt': DateTime.now().toUtc().toIso8601String(), 'entries': exportVerifiedEntries()})}\n';
  }

  static List<DynamicAvailabilityEntry> _readEntries(SharedPreferences prefs) {
    final raw = prefs.getString(_entriesStorageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map(
            (json) =>
                DynamicAvailabilityEntry.fromJson(json.cast<String, dynamic>()),
          )
          .where((entry) => entry.normalizedTitle.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_legacyStorageKey, _cachedKeys.toList());
      await prefs.setString(
        _entriesStorageKey,
        jsonEncode(exportVerifiedEntries()),
      );
    } catch (e) {
      // Ignora falhas de escrita
    }
  }

  static String _identityFor(DynamicAvailabilityEntry entry) {
    return '${entry.providerId ?? ''}|${entry.normalizedTitle}';
  }

  static String? _normalizeProviderId(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  @visibleForTesting
  static Future<void> debugResetForTesting({bool clearPersisted = true}) async {
    _cachedKeys = {};
    _entriesByTitle.clear();
    _initialized = false;
    if (!clearPersisted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyStorageKey);
      await prefs.remove(_entriesStorageKey);
    } catch (_) {}
  }
}
