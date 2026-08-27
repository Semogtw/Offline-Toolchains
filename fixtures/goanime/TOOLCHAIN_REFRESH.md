# GoAnime offline toolchain refresh

This marker keeps rebuild requests explicit and auditable without changing the dependency fixture.

Requested for validation of the current reconciled MegaPlay merge candidate, based on the exact private GoAnime-Mobile snapshot:

```text
39a48fcb542fb92b7e93e530e9a1e34fea741c38
```

A fresh build was requested on 2026-08-27 UTC because the previous one-day artifact expired before this validation session could consume it.

Required bundle contents and validation:

- Flutter 3.44.1;
- Dart 3.12.1;
- portable Pub cache from `fixtures/goanime/pubspec.yaml`;
- portable Gradle/Android cache defined by `build-goanime.yml`;
- PowerShell runtime used by repository release guards;
- offline `flutter pub get`, analyzer, Flutter tests and debug APK proof inside the producer workflow;
- versioned metadata in `receipts/goanime-toolchain-latest.json` after successful completion.

The consumer must still verify receipt structure, artifact expiration, part checksums and `MANIFEST.txt`, then activate the copied bundle and rerun the GoAnime-Mobile gates locally. Producer success is not a substitute for validating the current source tree.

Update this marker only after the resulting one-day artifact expires and another fresh exact bundle is required.
