# GoAnime desktop smoke on the public runner hub

The Windows and Linux desktop smoke builds for the private GoAnime repository live in `Offline-Toolchains` so their expensive hosted-runner work uses the public workflow hub instead of the private project.

`Run private GoAnime desktop smoke` runs every Monday at `09:00 UTC` and can also be dispatched manually for an allowlisted exact branch, tag, or commit. The repository identity is fixed to `Semogtw/goanime-mobile`; only the validated ref is variable.

Security properties:

- `PRIVATE_REPOSITORIES_TOKEN` needs only read access to GoAnime.
- Private checkout credentials are not persisted.
- Flutter's persistent Actions cache is disabled for the private checkout.
- Windows and Linux build outputs are verification-only and are never uploaded.
- Each job removes the private checkout in an `always()` cleanup step.
- No release, signing, Shorebird, deployment, or production credential is moved into this smoke workflow.

The former private-repository `desktop_smoke.yml` can therefore be removed without losing its weekly Windows/Linux coverage. The former manual `android_debug_build.yml` is superseded by the central encrypted APK handoff and the GoAnime Android build gate in `Run private project CI`.
