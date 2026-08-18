# Retired GoAnime Scrapling catalog trigger path

The legacy `Refresh GoAnime catalog with Scrapling` workflow was retired on 2026-08-18 after its functionality was consolidated into the source-bound provider-cache workflow.

Do not add new `.request` files here. Historical files are retained only as provenance.

Use:

```text
triggers/goanime-scrapling-provider-cache/<identifier>.request
```

with:

```text
target_branch=feat/scrapling-provider-pipeline
source_hint=<full 40-character GoAnime commit SHA>
reason=<short human-readable reason>
```

The authoritative workflow is:

```text
.github/workflows/goanime-scrapling-provider-cache.yml
```
