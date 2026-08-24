import 'package:goanime_core/goanime_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'MediaLibraryDataSource exposes a neutral refresh-aware list contract',
    () async {
      final source = _FakeLibraryDataSource();

      expect(await source.load(forceRefresh: false), ['cached']);
      expect(await source.load(forceRefresh: true), ['fresh']);
      expect(source.refreshIntents, [false, true]);
    },
  );
}

final class _FakeLibraryDataSource implements MediaLibraryDataSource<String> {
  final List<bool> refreshIntents = <bool>[];

  @override
  Future<List<String>> load({required bool forceRefresh}) async {
    refreshIntents.add(forceRefresh);
    return forceRefresh ? <String>['fresh'] : <String>['cached'];
  }
}
