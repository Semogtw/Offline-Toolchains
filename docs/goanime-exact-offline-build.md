# GoAnime Android offline toolchain

This document describes how to compose the public offline toolchain packages used for deterministic Android development and validation.

## Components

The toolchain is split into independent packages so small dependency changes do not require rebuilding the entire environment:

| Package | Purpose |
| --- | --- |
| `android-base-linux-x64-*` | JDK, Android SDK/platforms, build-tools, NDK, CMake, and platform-tools |
| `goanime-flutter-cache-linux-x64-*` | Flutter/Dart, Gradle distribution, and broad dependency caches |
| `goanime-lock-delta-linux-x64-*` | Small Pub cache delta for the dependency lock currently targeted by the toolchain |
| `goanime-gradle-delta-linux-x64-*` | Small Maven/Gradle delta plus local-repository helpers |

Large base packages should remain stable where practical. Dependency-only changes should prefer small deltas.

## Restore

Verify the accompanying checksums/manifests before extracting any bundle.

Typical restore flow:

```bash
tar --zstd -xf android-base-linux-x64.tar.zst
tar --zstd -xf goanime-flutter-cache-linux-x64.tar.zst
tar --zstd -xf goanime-lock-delta-linux-x64.tar.zst
tar --zstd -xf goanime-gradle-delta-linux-x64.tar.zst

bash ./goanime-lock-delta/apply.sh ./goanime-toolchain
bash ./goanime-gradle-delta/apply.sh \
  ./goanime-gradle-delta \
  ./goanime-toolchain/gradle-home

source ./android-base/activate.sh
source ./goanime-toolchain/activate-exact.sh
```

The delta installers are expected to be idempotent and to fail when conflicting files with incompatible hashes would be introduced.

## Validation

In a compatible Flutter project, common offline validation looks like:

```bash
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
```

For Android builds, use Gradle's offline mode when the goal is to prove that the restored environment is self-contained:

```bash
./android/gradlew --offline --no-daemon assembleDebug
```

Exact worker and heap settings depend on the available machine memory and the current Android/Flutter dependency graph.

## Rebuild policy

Regenerate only the component whose inputs changed:

- Android base when SDK/JDK/NDK/build-tools requirements change;
- Flutter base when the Flutter/Gradle foundation changes materially;
- Pub delta when the targeted dependency lock changes;
- Gradle delta when a required Maven coordinate is missing from the restored environment.

## Scope

The toolchain proves environment reproducibility and offline dependency availability. It does not by itself prove production signing, device-specific behavior, deployment, or application release correctness.
