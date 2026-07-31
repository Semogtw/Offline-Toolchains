# GoAnime deterministic offline cache design

## Goal

Make the public GoAnime toolchain artifact portable after extraction and capable of satisfying the private repository's hosted `pubspec.lock` entries exactly without publishing private source, paths, URLs, tokens, or Git dependencies.

## Design

A sanitized JSON manifest stores only hosted package names and exact versions plus the pinned Flutter/Dart versions. A standard-library Python helper extracts this manifest from a private lock, validates it, generates a synthetic Flutter pubspec that references every hosted package exactly, and verifies that a Pub cache contains every requested directory.

The workflow hydrates this exact synthetic graph before the existing fixture build. The bundle includes the manifest and verifier. Its activation script repairs `flutter_tools/.dart_tool` with bundled Dart and `--offline` whenever the extraction path changes, then records that path in a local stamp.

Validation sets `PUB_HOSTED_URL` and `FLUTTER_STORAGE_BASE_URL` to an unreachable loopback endpoint, removes generated project state, and requires `flutter pub get --offline --enforce-lockfile` to succeed for the exact fixture. This catches both missing package versions and hidden network dependence.

## Security

The public manifest contains no descriptions from `pubspec.lock`, no hosted URLs, no path dependencies, no Git dependencies, no repository ref, and no private commit identifier. Package names and versions are restricted to conservative alphabets before being written into YAML or filesystem paths.

## Testing

Python unit tests cover sanitization, exact pubspec generation, and missing-cache reporting. A shell test proves repair occurs once per extraction path and repeats after relocation. A static validation script enforces workflow integration and shell syntax.
