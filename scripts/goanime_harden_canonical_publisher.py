#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

OLD = '''      - name: Commit validated external cache\n        if: steps.diff.outputs.changed == 'true' && steps.credentials.outputs.publish == 'true'\n        id: commit\n        working-directory: private-source\n        shell: bash\n        env:\n          WRITE_TOKEN: ${{ secrets.GOANIME_CATALOG_WRITE_TOKEN }}\n          EXPECTED_SHA: ${{ steps.source.outputs.sha }}\n          TARGET_BRANCH: ${{ steps.request.outputs.target_branch }}\n        run: |\n          set -euo pipefail\n          git config user.name 'github-actions[bot]'\n          git config user.email '4189828+github-actions[bot]@users.noreply.github.com'\n          git add \\\n            assets/data/anime_provider_catalogs.json \\\n            assets/data/anime_provider_catalog_manifest.json \\\n            assets/data/available_animes.json \\\n            assets/data/available_anime_modes.json \\\n            assets/data/mal_provider_availability_map.json \\\n            assets/data/provider_scrape_evidence.json \\\n            tools/scrapling_provider_pipeline/provider_source_hints.json\n          git diff --cached --check\n          git commit -m 'chore(cache): refresh providers with Scrapling'\n          auth="$(printf 'x-access-token:%s' "$WRITE_TOKEN" | base64 -w0)"\n          extraheader="AUTHORIZATION: basic $auth"\n          git -c http.https://github.com/.extraheader="$extraheader" fetch origin "$TARGET_BRANCH"\n          test "$(git rev-parse FETCH_HEAD)" = "$EXPECTED_SHA"\n          git -c http.https://github.com/.extraheader="$extraheader" push origin "HEAD:$TARGET_BRANCH"\n          echo "sha=$(git rev-parse HEAD)" >> "$GITHUB_OUTPUT"\n          unset auth extraheader WRITE_TOKEN\n'''

NEW = '''      - name: Verify source branch before publication\n        if: steps.diff.outputs.changed == 'true' && steps.credentials.outputs.publish == 'true'\n        id: publish_race\n        working-directory: private-source\n        shell: bash\n        env:\n          READ_TOKEN: ${{ secrets.PRIVATE_REPOSITORIES_TOKEN }}\n          EXPECTED_SHA: ${{ steps.source.outputs.sha }}\n          TARGET_BRANCH: ${{ steps.request.outputs.target_branch }}\n        run: |\n          set -euo pipefail\n          remote_head="$(git ls-remote "https://x-access-token:${READ_TOKEN}@github.com/Semogtw/goanime-mobile.git" "refs/heads/${TARGET_BRANCH}" | awk '{print $1}')"\n          test -n "$remote_head"\n          test "$remote_head" = "$EXPECTED_SHA" || {\n            echo 'Target branch moved; refusing stale cache publication.' >&2\n            exit 1\n          }\n          unset remote_head READ_TOKEN\n\n      - name: Commit validated external cache\n        if: steps.diff.outputs.changed == 'true' && steps.credentials.outputs.publish == 'true' && steps.publish_race.outcome == 'success'\n        id: commit\n        working-directory: private-source\n        shell: bash\n        run: |\n          set -euo pipefail\n          git config user.name 'github-actions[bot]'\n          git config user.email '41898282+github-actions[bot]@users.noreply.github.com'\n          git add \\\n            assets/data/anime_provider_catalogs.json \\\n            assets/data/anime_provider_catalog_manifest.json \\\n            assets/data/available_animes.json \\\n            assets/data/available_anime_modes.json \\\n            assets/data/mal_provider_availability_map.json \\\n            assets/data/provider_scrape_evidence.json \\\n            tools/scrapling_provider_pipeline/provider_source_hints.json\n          git diff --cached --check\n          git commit -m 'chore(cache): refresh providers with Scrapling'\n          echo "sha=$(git rev-parse HEAD)" >> "$GITHUB_OUTPUT"\n\n      - name: Publish validated external cache\n        if: steps.commit.outcome == 'success'\n        id: publish_cache\n        working-directory: private-source\n        shell: bash\n        env:\n          WRITE_TOKEN: ${{ secrets.GOANIME_CATALOG_WRITE_TOKEN }}\n          TARGET_BRANCH: ${{ steps.request.outputs.target_branch }}\n        run: |\n          set -euo pipefail\n          test -n "$WRITE_TOKEN"\n          git remote set-url origin "https://x-access-token:${WRITE_TOKEN}@github.com/Semogtw/goanime-mobile.git"\n          git push origin "HEAD:refs/heads/${TARGET_BRANCH}"\n          git remote set-url origin 'https://github.com/Semogtw/goanime-mobile.git'\n          unset WRITE_TOKEN\n'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workflow", type=Path, required=True)
    args = parser.parse_args()
    path = args.workflow.resolve()
    text = path.read_text(encoding="utf-8")
    if text.count(OLD) != 1:
        raise SystemExit(f"expected exactly one canonical publisher block, found {text.count(OLD)}")
    text = text.replace(OLD, NEW, 1)
    path.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
