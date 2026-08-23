#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'{label} not found in {path}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


def remove_if_present(path: Path, text_to_remove: str) -> None:
    text = path.read_text(encoding='utf-8')
    if text_to_remove in text:
        path.write_text(text.replace(text_to_remove, '', 1), encoding='utf-8')


def main() -> int:
    service = Path('lib/services/mal_provider_availability_service.dart')
    replace_once(
        service,
        """  static const String configuredUrl = String.fromEnvironment(
    'MAL_PROVIDER_AVAILABILITY_URL',
    defaultValue: '',
  );
""",
        """  static const String configuredUrl = String.fromEnvironment(
    'MAL_PROVIDER_AVAILABILITY_URL',
    defaultValue: '',
  );
  static const String _updateManifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue: '',
  );
""",
        'configured URL block',
    )
    replace_once(
        service,
        """  static Future<MalProviderAvailabilityRefreshResult>
  refreshConfiguredFromNetwork() {
    if (configuredUrl.trim().isEmpty) {
      return Future.value(MalProviderAvailabilityRefreshResult.skipped);
    }
    return refreshFromNetwork(url: configuredUrl);
  }
""",
        """  static Future<MalProviderAvailabilityRefreshResult>
  refreshConfiguredFromNetwork() {
    final url = resolvedConfiguredUrl();
    if (url.isEmpty) {
      return Future.value(MalProviderAvailabilityRefreshResult.skipped);
    }
    return refreshFromNetwork(url: url);
  }

  /// Resolves the provider map from its explicit define first. Release builds
  /// that already know only the update Worker URL can use the sibling
  /// `/latest/mal_provider_availability_map.json` route without another define.
  /// Query parameters (for private release channels) are preserved.
  static String resolvedConfiguredUrl({
    String? configuredUrlOverride,
    String? updateManifestUrlOverride,
  }) {
    final explicit = (configuredUrlOverride ?? configuredUrl).trim();
    if (explicit.isNotEmpty) return explicit;

    final update = (updateManifestUrlOverride ?? _updateManifestUrl).trim();
    final uri = Uri.tryParse(update);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        !uri.path.endsWith('/latest/update.json')) {
      return '';
    }
    final basePath = uri.path.substring(
      0,
      uri.path.length - 'update.json'.length,
    );
    final nextPath = '${basePath}mal_provider_availability_map.json';
    return uri.replace(path: nextPath).removeFragment().toString();
  }
""",
        'configured refresh block',
    )

    test = Path('test/services/mal_provider_availability_service_test.dart')
    marker = """  test('reads provider ownership, modes, status, and counts by MAL ID', () {
"""
    extra = """  test('derives provider map URL from update Worker URL', () {
    expect(
      MalProviderAvailabilityService.resolvedConfiguredUrl(
        configuredUrlOverride: '',
        updateManifestUrlOverride:
            'https://updates.example.dev/latest/update.json?token=private',
      ),
      'https://updates.example.dev/latest/mal_provider_availability_map.json?token=private',
    );
  });

  test('explicit provider map URL wins over derived Worker URL', () {
    expect(
      MalProviderAvailabilityService.resolvedConfiguredUrl(
        configuredUrlOverride: 'https://cache.example/provider-map.json',
        updateManifestUrlOverride:
            'https://updates.example.dev/latest/update.json',
      ),
      'https://cache.example/provider-map.json',
    );
  });

  test('does not derive provider map from an unrelated URL', () {
    expect(
      MalProviderAvailabilityService.resolvedConfiguredUrl(
        configuredUrlOverride: '',
        updateManifestUrlOverride: 'https://example.dev/not-an-update.json',
      ),
      isEmpty,
    );
  });

"""
    replace_once(test, marker, extra + marker, 'provider-map test marker')

    worker = Path('cloudflare/updates-worker/src/index.js')
    worker_marker = '''  if (path === "latest/runtime_database_manifest.json") {
    return "latest/runtime_database_manifest.json";
  }
'''
    replace_once(
        worker,
        worker_marker,
        worker_marker
        + '''  if (path === "latest/mal_provider_availability_map.json") {
    return "latest/mal_provider_availability_map.json";
  }
''',
        'Worker runtime route',
    )

    # These imports were already removed by the startup-fix PR on newer bases.
    # Keep this patch source-compatible with both pre- and post-#209 revisions.
    remove_if_present(
        Path('lib/widgets/goanime_opening.dart'),
        "import 'package:flutter/foundation.dart';\n",
    )
    remove_if_present(
        Path('test/widgets/goanime_opening_test.dart'),
        "import 'package:flutter/painting.dart';\n",
    )

    doc = Path('docs/global_catalog_refresh_and_discovery_plan.md')
    text = doc.read_text(encoding='utf-8')
    if '## Runtime provider provenance propagation' not in text:
        text = text.rstrip() + '''

## Runtime provider provenance propagation

The global finalizer publishes `mal_provider_availability_map.json` beside the
runtime SQLite artifacts. The update Worker exposes it as a read-only `/latest`
object. `MalProviderAvailabilityService` prefers an explicit
`MAL_PROVIDER_AVAILABILITY_URL`, but otherwise derives the sibling map URL from
`UPDATE_MANIFEST_URL`, preserving private-channel query parameters. This keeps
provider-specific MAL/title provenance fresh on installed clients without a new
APK release.

SUB and DUB are promoted independently: each mode requires the configured
reporter quorum. Total candidate quorum alone cannot promote either mode.
'''
        doc.write_text(text.rstrip() + '\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
