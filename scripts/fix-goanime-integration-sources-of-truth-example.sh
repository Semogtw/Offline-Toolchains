#!/usr/bin/env bash
set -euo pipefail

repo="${1:-.}"
cd "$repo"

python3 - <<'PY'
from pathlib import Path

path = Path('docs/ai/sources_of_truth.md')
text = path.read_text()
old = '''### Documento chama `feature/manga-platform` de branch ativa

A linha atual de paridade/unificação está em `codex/manga-parity-20260823`.

**Decisão:** corrigir entrypoints/owners atuais; manter referências à branch antiga apenas quando forem historicamente necessárias.'''
new = '''### Documento chama uma branch histórica de ativa

Um entrypoint inferior pode ainda nomear uma branch de desenvolvimento já superseded como linha atual.

**Decisão:** corrigir entrypoints/owners atuais; referências históricas pertencem apenas a registros explicitamente classificados como históricos.'''
count = text.count(old)
if count != 1:
    raise SystemExit(f'docs/ai/sources_of_truth.md: expected one stale branch example, found {count}')
path.write_text(text.replace(old, new, 1))
PY

git diff --check
