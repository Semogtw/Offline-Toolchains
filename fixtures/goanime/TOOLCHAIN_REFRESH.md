# GoAnime offline toolchain refresh

This marker keeps rebuild requests explicit and auditable without changing the dependency fixture.

Requested for validation of the current non-Jikan `Semogtw/goanime-mobile` development line, based on the exact functional snapshot:

```text
10d6b6fed2a9b83e008d82f59a193e879de9604e
```

A fresh build was requested on 2026-08-04 UTC because the previous one-day artifact had expired before this validation session began.

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
