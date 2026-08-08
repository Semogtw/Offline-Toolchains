# GoAnime CI migration to the public runner hub

`Run private GoAnime full CI` replaces the general-purpose `ci.yml` that previously ran inside the private `goanime-mobile` repository.

The private workflow could no longer start hosted jobs because the account was blocked by billing/spending-limit state. Moving the compute to the public `Offline-Toolchains` repository both avoids that private-runner blockage and keeps the expensive verification in the shared hub.

Coverage migrated from the private workflow:

- app and `goanime_core` dependency resolution;
- project health validation;
- Python tooling unit tests;
- repository guards;
- Dart formatting;
- Flutter analysis;
- Flutter app tests;
- `goanime_core` tests;
- release-workflow invariant validation.

The public-runner profile additionally builds an Android debug APK as a verification gate and discards it. Downloadable APKs use the separate OpenPGP encrypted handoff workflow instead.

The workflow runs daily at `08:30 UTC` against `main` and can be dispatched manually for another validated ref. It does not try to emulate a private pull-request event; when PR-specific automatic checks are needed later, use a narrowly scoped cross-repository dispatch credential rather than reintroducing the heavy private workflow.

Security remains the same as the rest of the hub: fixed repository mapping, read-only checkout token, no persisted credentials, no persistent Actions cache derived from private source, no raw log artifact, no APK upload and `always()` cleanup.
