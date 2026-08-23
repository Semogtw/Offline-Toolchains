#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

PATH = Path('.github/workflows/goanime-global-catalog-finalize.yml')


def main() -> int:
    text = PATH.read_text(encoding='utf-8')

    old_policy = '''          if [ -n "$WRITE_TOKEN" ] && [ "$TARGET_REF" = 'main' ] && [ "$GITHUB_EVENT_NAME" = 'workflow_run' ]; then
            echo 'commit=true' >> "$GITHUB_OUTPUT"
          else
            echo 'commit=false' >> "$GITHUB_OUTPUT"
          fi
'''
    new_policy = '''          # Community consensus is a runtime overlay, not crawler truth.
          # The provider-cache workflow alone owns canonical git artifacts.
          echo 'commit=false' >> "$GITHUB_OUTPUT"
'''
    if old_policy in text:
        text = text.replace(old_policy, new_policy, 1)
    elif "echo 'commit=false' >> \"$GITHUB_OUTPUT\"" not in text:
        raise SystemExit('publication commit policy block not found')

    old_uploads = '''          aws s3 cp dist/runtime_database_cache/runtime_database_manifest.json "s3://${R2_BUCKET}/latest/runtime_database_manifest.json" --endpoint-url "$endpoint"
          aws s3 cp dist/runtime_database_cache/franchise_availability.db "s3://${R2_BUCKET}/latest/franchise_availability.db" --endpoint-url "$endpoint"
          aws s3 cp dist/runtime_database_cache/title_availability.db "s3://${R2_BUCKET}/latest/title_availability.db" --endpoint-url "$endpoint"
'''
    old_uploads_with_map = old_uploads + '''          aws s3 cp assets/data/mal_provider_availability_map.json "s3://${R2_BUCKET}/latest/mal_provider_availability_map.json" --endpoint-url "$endpoint"
'''
    new_uploads = '''          # Publish payloads first and the manifest last. Clients only observe a
          # new generation after every referenced database has reached R2.
          aws s3 cp dist/runtime_database_cache/franchise_availability.db "s3://${R2_BUCKET}/latest/franchise_availability.db" --endpoint-url "$endpoint"
          aws s3 cp dist/runtime_database_cache/title_availability.db "s3://${R2_BUCKET}/latest/title_availability.db" --endpoint-url "$endpoint"
          aws s3 cp assets/data/mal_provider_availability_map.json "s3://${R2_BUCKET}/latest/mal_provider_availability_map.json" --endpoint-url "$endpoint"
          aws s3 cp dist/runtime_database_cache/runtime_database_manifest.json "s3://${R2_BUCKET}/latest/runtime_database_manifest.json" --endpoint-url "$endpoint"
'''
    if old_uploads_with_map in text:
        text = text.replace(old_uploads_with_map, new_uploads, 1)
    elif old_uploads in text:
        text = text.replace(old_uploads, new_uploads, 1)
    elif new_uploads not in text:
        raise SystemExit('R2 publication block not found')

    PATH.write_text(text, encoding='utf-8')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
