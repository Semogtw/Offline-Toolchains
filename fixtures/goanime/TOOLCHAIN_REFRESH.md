# GoAnime offline toolchain refresh

This marker keeps rebuild requests explicit and auditable without changing the dependency fixture.

Requested for exact validation of `Semogtw/goanime-mobile` snapshot:

```text
3010d3d633fa2beab00ecc5f76c755e5c5cf281b
```

Requested on 2026-08-02 after the previous one-day Flutter/Android/Pub artifacts expired.

Required bundle contents and validation:

- Flutter 3.44.1;
- Dart 3.12.1;
- portable Pub cache from `fixtures/goanime/pubspec.yaml`;
- portable Gradle/Android cache defined by `build-goanime.yml`;
- PowerShell runtime used by repository release guards;
- offline `flutter pub get`, analyzer, Flutter tests and debug APK proof inside the producer workflow.

The consumer must still verify part checksums, activate the copied bundle and rerun the GoAnime-Mobile gates locally. Producer success is not a substitute for validating the target source snapshot.

Update this marker only after the resulting one-day artifact expires and another fresh exact bundle is required.
