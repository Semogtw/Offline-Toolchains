import 'dart:convert';

enum MangaSyncRecordKind {
  library,
  progress,
  readerPreference,
  sourcePreference,
  globalPreference,
}

final class MangaSyncRecord {
  MangaSyncRecord({
    required this.recordKey,
    required this.kind,
    this.workId,
    this.canonicalChapterId,
    required DateTime updatedAt,
    required this.tombstone,
    required Map<String, dynamic> payload,
  }) : updatedAt = updatedAt.toUtc(),
       payload = Map<String, dynamic>.unmodifiable(payload) {
    if (recordKey.trim().isEmpty) {
      throw ArgumentError.value(recordKey, 'recordKey', 'Must not be empty.');
    }
    if (kind != MangaSyncRecordKind.globalPreference &&
        (workId == null || workId!.trim().isEmpty)) {
      throw ArgumentError.value(workId, 'workId', 'Must not be empty.');
    }
    if (kind == MangaSyncRecordKind.progress &&
        (canonicalChapterId == null || canonicalChapterId!.trim().isEmpty)) {
      throw ArgumentError.value(
        canonicalChapterId,
        'canonicalChapterId',
        'Must not be empty for progress records.',
      );
    }
  }

  final String recordKey;
  final MangaSyncRecordKind kind;
  final String? workId;
  final String? canonicalChapterId;
  final DateTime updatedAt;
  final bool tombstone;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'recordKey': recordKey,
      'kind': kind.name,
      'workId': workId,
      'canonicalChapterId': canonicalChapterId,
      'updatedAt': updatedAt.toIso8601String(),
      'tombstone': tombstone,
      'payload': payload,
    };
  }

  factory MangaSyncRecord.fromJson(Map<String, dynamic> json) {
    final rawKind = json['kind']?.toString();
    final kind = MangaSyncRecordKind.values.where((value) {
      return value.name == rawKind;
    }).firstOrNull;
    if (kind == null) {
      throw FormatException('Unknown Manga sync record kind: $rawKind');
    }
    final payload = json['payload'];
    return MangaSyncRecord(
      recordKey: json['recordKey']?.toString() ?? '',
      kind: kind,
      workId: _nullableString(json['workId']),
      canonicalChapterId: _nullableString(json['canonicalChapterId']),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      tombstone: json['tombstone'] == true,
      payload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : const <String, dynamic>{},
    );
  }

  static MangaSyncRecord latest(MangaSyncRecord left, MangaSyncRecord right) {
    if (left.recordKey != right.recordKey) {
      throw ArgumentError(
        'Cannot merge Manga sync records with different keys.',
      );
    }
    if (left.updatedAt.isAfter(right.updatedAt)) return left;
    if (right.updatedAt.isAfter(left.updatedAt)) return right;
    if (left.tombstone != right.tombstone) {
      return left.tombstone ? left : right;
    }

    // Equal clocks can happen when two domain events are materialized from the
    // same SQLite row. Resolve the remaining tie without depending on argument
    // order so queue compaction and pull reconciliation are deterministic.
    final leftEncoded = jsonEncode(left.toJson());
    final rightEncoded = jsonEncode(right.toJson());
    return leftEncoded.compareTo(rightEncoded) >= 0 ? left : right;
  }

  bool syncContentEquals(MangaSyncRecord other) {
    return recordKey == other.recordKey &&
        updatedAt == other.updatedAt &&
        tombstone == other.tombstone &&
        jsonEncode(toJson()) == jsonEncode(other.toJson());
  }
}

abstract final class MangaSyncRecordKeys {
  static String library(String workId) => 'library:$workId';

  static String progress(String workId, String canonicalChapterId) =>
      'progress:$workId:$canonicalChapterId';

  static String readerPreference(String workId) => 'reader:$workId';

  static String sourcePreference(String workId) => 'source:$workId';

  static String globalPreference(String preferenceKey) =>
      'global:$preferenceKey';
}

String? _nullableString(Object? value) {
  final encoded = value?.toString();
  if (encoded == null || encoded.trim().isEmpty) return null;
  return encoded;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
