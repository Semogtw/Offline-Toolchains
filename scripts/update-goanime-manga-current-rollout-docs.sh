#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import subprocess

root = Path('.')
receipts = sorted((root / 'docs').glob('manga_global_availability_receipt_*.md'))
if not receipts:
    raise SystemExit('no manga global availability receipt found')
receipt = receipts[-1]
receipt_text = receipt.read_text(encoding='utf-8')


def metric(label: str) -> int:
    match = re.search(
        rf'^- {re.escape(label)}: \*\*(\d+)\*\*$',
        receipt_text,
        flags=re.MULTILINE,
    )
    if not match:
        raise SystemExit(f'missing receipt metric: {label}')
    return int(match.group(1))


def provider(source_id: str) -> tuple[str, int, str]:
    match = re.search(
        rf'^\| `{re.escape(source_id)}` \| ([^|]+) \|\s*(\d+) \| `([^`]+)` \|$',
        receipt_text,
        flags=re.MULTILINE,
    )
    if not match:
        raise SystemExit(f'missing receipt provider row: {source_id}')
    return match.group(1).strip(), int(match.group(2)), match.group(3)


def br(value: int) -> str:
    return f'{value:,}'.replace(',', '.')


metrics = {
    'enabled': metric('Enabled providers'),
    'refreshed': metric('Providers refreshed exhaustively'),
    'carried': metric('Providers carried forward'),
    'works': metric('Canonical works bundled'),
    'links': metric('Source occurrences bundled'),
    'readable': metric('Readable-proven links'),
    'listed': metric('Listed-only links'),
}
if metrics['enabled'] != 18 or metrics['refreshed'] != 2 or metrics['carried'] != 16:
    raise SystemExit(f'unexpected rollout receipt counts: {metrics}')

mangadex = provider('ptbr.mangadex')
manhastro = provider('ptbr.manhastro')
if mangadex[0] != 'exhausted' or manhastro[0] != 'exhausted':
    raise SystemExit(f'target provider receipt is not exhaustive: {mangadex=} {manhastro=}')

head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
branch = 'feat/manga-sources-mangadex-taimu-manhastro-20260828'
fresh_probe_run = '33341458888'
fresh_probe_sha = 'cd5158b55e075504dfbaefa4760c21428f5b3134'

enabled_ids = [
    'ptbr.arthurscan',
    'ptbr.astratoons',
    'ptbr.capitoons',
    'ptbr.hqnow',
    'ptbr.hipertoon',
    'ptbr.kamisamaexplorer',
    'ptbr.kivaratoons',
    'ptbr.leituramanga',
    'ptbr.ler999',
    'ptbr.littletyrant',
    'ptbr.maidscan',
    'ptbr.mangadash',
    'ptbr.mangadex',
    'ptbr.mangaflix',
    'ptbr.mangalivreblog',
    'ptbr.mangalivreorg',
    'ptbr.manhastro',
    'ptbr.ninjascan',
]
numbered_sources = '\n'.join(
    f'{index}. `{source_id}`' for index, source_id in enumerate(enabled_ids, start=1)
)

rollout = f'''# Manga provider rollout status

> **Status: atual para desenvolvimento.** Esta é a fonte operacional compacta da branch MangaDex / Taimu / Manhastro. Receipts certificam o SHA materializado; probes live certificam o SHA explicitamente citado.

**Atualizado em:** 2026-08-30
**Branch:** `{branch}`
**Checkpoint observado antes deste commit documental:** `{head}`
**Último receipt global:** `docs/{receipt.name}`
**Fresh candidate probe:** Offline-Toolchains run `{fresh_probe_run}` sobre `{fresh_probe_sha}`

## Estado atual

- Runtime padrão: **{metrics['enabled']} providers habilitados**.
- `ptbr.mangadex`: enabled, `exhausted`, **{br(mangadex[1])} ocorrências únicas** no receipt atual.
- `ptbr.manhastro`: enabled, `exhausted`, **{br(manhastro[1])} ocorrências únicas** no receipt atual.
- `ptbr.taimumangas`: **planned**, fora de `defaultEnabledMangaSourceIds`.
- Bundle: **{br(metrics['works'])} obras canônicas**, **{br(metrics['links'])} ocorrências**, **{br(metrics['readable'])} readable-proven**, **{br(metrics['listed'])} listed-only**.
- Materialização alvo: **{metrics['refreshed']} refreshes exaustivos / {metrics['carried']} partições carried-forward**.

## Autorização runtime

`defaultEnabledMangaSourceIds` contém:

{numbered_sources}

O baseline histórico PT-BR continua **114 inventariadas / 98 permitidas / 16 excluídas**. MangaDex é externo ao snapshot Keiyoushi `src/pt` e não altera esse accounting. Taimu permanece `planned` mesmo possuindo adapter/fixtures.

## Evidência live fresca — 2026-08-30

Run `{fresh_probe_run}`, exact SHA `{fresh_probe_sha}`:

```text
ptbr.mangadex
  search=24 resultados
  details=success
  chapters=success (26)
  content=imageSequence
  transport=success
  verifier=success
  terminal=readable

ptbr.taimumangas
  search attempt 1 = HTTP 523
  search attempt 2 = HTTP 523
  search attempt 3 = HTTP 523
  host=apiv2.taimumangas.com
  terminal=no_search_result

ptbr.manhastro
  search=99 resultados
  details=success
  chapters=success (143)
  content=imageSequence
  transport=success
  verifier=success
  terminal=readable
```

A falha do Taimu ocorre antes de qualquer resultado de search e continua sendo um bloqueio live/upstream, não uma autorização para promover o provider. Nova promoção exige search → details → chapters → content → bytes reproduzível.

A auditoria Manhastro da mesma rodada completou 4/4 queries e 12 details. Houve 1 ocorrência explícita na amostra e 2/100 na primeira página do catálogo; a evidência continua compatível com a política atual de não adult-primary.

## Catálogo global materializado

Receipt: `docs/{receipt.name}`.

```text
enabledProviders={metrics['enabled']}
refreshedProviders={metrics['refreshed']}
carriedForwardProviders={metrics['carried']}
canonicalWorks={metrics['works']}
sourceOccurrences={metrics['links']}
readableProvenLinks={metrics['readable']}
listedOnlyLinks={metrics['listed']}
ptbr.mangadex=exhausted:{mangadex[1]}:{mangadex[2]}
ptbr.manhastro=exhausted:{manhastro[1]}:{manhastro[2]}
```

Partição `exhausted` substitui sua versão anterior. Provider `partial`, `failed`, `blocked`, não selecionado ou não enumerável preserva a partição conhecida anterior. Listing e readability continuam garantias diferentes.

## Hardening atual

### MangaDex

- safe/suggestive inventariados em partições próprias;
- page tokens, `limit`, `offset` e `total` validados fail-closed;
- metadata fracionária não é truncada silenciosamente;
- recursos malformados em search/chapters/AtHome falham a operação;
- capítulos rejeitam linguagem inesperada e possuem cap de paginação;
- retry especial de HTTP 400 é restrito a `api.mangadex.org`;
- `mangadex.network` depende de suffix policy com boundary de label.

### Manhastro

- search usa paginação server-side e filtro `nome`;
- details resolve por `manga_id` com cardinalidade/identidade estritas;
- cache é por consulta/página e details reutiliza item validado;
- registro com ID válido sem título textual é explicitamente não catalogável;
- `current_page/per_page/total/last_page/has_more` são validados;
- overlap terminal observado live é aceito, mas terminal underfill é rejeitado;
- IDs numéricos fracionários são rejeitados;
- capítulos/páginas inválidos não produzem coleção parcial;
- capas de search/details, inclusive fallback legado, obedecem à `MangaProviderPolicy`.

O upstream apresenta 3 ocorrências sobrepostas na página terminal; o inventário deduplica por `(sourceId, mangaId)` e a partição termina `exhausted`.

### Taimu

- page token, page identity e continuation metadata são validados;
- página vazia que afirma continuação falha fechado;
- metadata de paginação fracionária é rejeitada;
- search/details/chapters/pages rejeitam itens malformados;
- `adult=true` é rejeitado; search usa `adult=false`;
- capítulos têm cap de 100 requests;
- capas de search/details, inclusive fallback legado, obedecem à content-host policy;
- permanece `planned` por HTTP 523 live.

### Transporte compartilhado

- `MangaRemoteContentProbe` valida o host inicial antes de I/O;
- Reader respeita hosts exatos e `allowedContentHostSuffixes`;
- redirects ficam sob `MangaHttpClient`;
- HTTP 200 com HTML/challenge não é readability;
- headers/cookies/tokens/URLs efêmeras não são persistidos;
- materializador cobre formatter, diff guard, analyzer e testes dos providers/readability.

## Afirmações permitidas

Pode ser afirmado que MangaDex e Manhastro estão enabled, possuem partição `exhausted` no receipt atual e terminaram fresh probe live até bytes em 2026-08-30. Pode ser afirmado que Taimu possui implementação determinística, mas continua `planned` por HTTP 523.

Não pode ser afirmado que Taimu é live/readable, que todos os {br(metrics['links'])} links do bundle são readable, ou que receipt antigo certifica código posterior que altere providers materializados/pipeline.

## Próximos gates

1. Manter Taimu fora do runtime até nova prova live completa.
2. Materializar novamente após alterações em MangaDex/Manhastro ou pipeline global.
3. Antes de merge, executar verifier final exact-SHA de docs/manifest/registry/receipt/drift/bytes e o gate complementar de strict-items/paginação/host-policy.

## Referências

- `docs/{receipt.name}`
- `docs/manga_ptbr_provider_audit.md`
- `docs/manga_source_aggregation.md`
- `docs/manga_sources_ptbr.md`
- `docs/manga_sources_ptbr.json`
- `tools/manga/inventory_manga_catalog.dart`
- `tools/manga/materialize_global_manga_availability_ci.sh`

Detalhes históricos permanecem no Git e nos receipts datados; o estado operacional deve ser interpretado pelo SHA/run citado.
'''
(root / 'docs/manga_provider_rollout_status.md').write_text(rollout, encoding='utf-8')

# Preserve the detailed historical audit, but make the current checkpoint explicit.
audit_path = root / 'docs/manga_ptbr_provider_audit.md'
audit = audit_path.read_text(encoding='utf-8')
current = f'''<!-- current-2026-08-30:start -->
## Checkpoint atual — 2026-08-30

- Branch: `{branch}`.
- Checkpoint observado antes deste commit documental: `{head}`.
- Receipt atual: `docs/{receipt.name}` com **{br(metrics['works'])} obras**, **{br(metrics['links'])} ocorrências**, **{br(metrics['readable'])} readable-proven** e **{br(metrics['listed'])} listed-only**.
- `ptbr.mangadex`: enabled, `exhausted` com **{br(mangadex[1])} ocorrências únicas**; fresh probe `{fresh_probe_run}` terminou `terminal=readable` até bytes.
- `ptbr.manhastro`: enabled, `exhausted` com **{br(manhastro[1])} ocorrências únicas**; fresh probe `{fresh_probe_run}` terminou `terminal=readable` até bytes.
- `ptbr.taimumangas`: `planned`; no fresh probe `{fresh_probe_run}`, 3/3 buscas retornaram HTTP **523** de `apiv2.taimumangas.com` antes de qualquer resultado.
- Manhastro segue paginação server-side, details por `manga_id`, aceita apenas overlap terminal seguro, rejeita underfill e filtra capas pela content-host policy.
- Taimu/Manhastro filtram capas de search/details e fallbacks legados pela `MangaProviderPolicy`; Reader/readability probe também validam content hosts antes de I/O.

Este checkpoint substitui números operacionais antigos abaixo. As seções históricas permanecem como evidência datada, não como garantia do HEAD atual.
<!-- current-2026-08-30:end -->
'''
pattern = re.compile(
    r'<!-- current-2026-08-30:start -->.*?<!-- current-2026-08-30:end -->\n?',
    re.S,
)
if pattern.search(audit):
    audit = pattern.sub(current + '\n', audit, count=1)
else:
    marker = '**Checkpoint de promoção:** `39993790a0f4ab99c2937ffca6ecb62d87ff1925`\n'
    if marker not in audit:
        raise SystemExit('audit insertion marker not found')
    audit = audit.replace(marker, marker + '\n' + current + '\n', 1)
audit_path.write_text(audit, encoding='utf-8')

readme_path = root / 'README_AI.md'
readme = readme_path.read_text(encoding='utf-8')
old = 'O estado documentado de Mangá inclui a promoção de providers no checkpoint `39993790a0f4ab99c2937ffca6ecb62d87ff1925` da branch `feat/manga-sources-mangadex-taimu-manhastro-20260828`. A branch efetivamente em checkout continua sendo a autoridade para qualquer tarefa; um commit mais novo em outra branch nunca deve ser atribuído automaticamente ao checkout atual.'
new = f'O estado operacional atual de MangaDex / Taimu / Manhastro pertence a `docs/manga_provider_rollout_status.md` na branch `{branch}`. O receipt global atual é `docs/{receipt.name}`; MangaDex e Manhastro estão enabled/exhaustive, enquanto Taimu permanece `planned` após 3/3 HTTP 523 no fresh probe `{fresh_probe_run}`. A branch efetivamente em checkout continua sendo a autoridade para qualquer tarefa.'
if old not in readme:
    raise SystemExit('README_AI branch-state paragraph not found')
readme = readme.replace(old, new, 1)
old = 'O cohort runtime documentado autoriza **18 providers de Mangá**. O checkpoint de promoção `39993790a0f4ab99c2937ffca6ecb62d87ff1925` revalidou MangaDex PT-BR e Manhastro até bytes reais; Taimu permanece `planned` por indisponibilidade HTTP 522/523 upstream. A fonte de verdade continua sendo `defaultEnabledMangaSourceIds`, não esta contagem textual.'
new = f'O cohort runtime documentado autoriza **18 providers de Mangá**. No fresh probe `{fresh_probe_run}`, MangaDex PT-BR e Manhastro terminaram `terminal=readable` até bytes; Taimu permanece `planned` após três HTTP 523 consecutivos em `apiv2.taimumangas.com`. A fonte de verdade continua sendo `defaultEnabledMangaSourceIds`, não esta contagem textual.'
if old not in readme:
    raise SystemExit('README_AI cohort paragraph not found')
readme = readme.replace(old, new, 1)
readme_path.write_text(readme, encoding='utf-8')

aggregation_path = root / 'docs/manga_source_aggregation.md'
aggregation = aggregation_path.read_text(encoding='utf-8')
old = '> **Status: Atual — implementado.** O modelo multi-source, registry, busca, matching, merge, ranking e roteamento existem no runtime de `codex/manga-parity-20260823`.'
new = f'> **Status: Atual — implementado.** O modelo multi-source, registry, busca, matching, merge, ranking e roteamento existem no runtime; o checkpoint operacional de providers está na branch `{branch}`.'
if old not in aggregation:
    raise SystemExit('aggregation status line not found')
aggregation = aggregation.replace(old, new, 1)
aggregation = aggregation.replace('**Última atualização:** 2026-08-28', '**Última atualização:** 2026-08-30', 1)
old = 'Atualmente existem **18 sources habilitadas** no manifest/registry. MangaDex PT-BR e Manhastro foram promovidas no exact-SHA `39993790a0f4ab99c2937ffca6ecb62d87ff1925` após fixtures, accounting/registry, drift e byte probes verdes; Taimu permanece `planned` por HTTP 522/523 upstream. Status/planned/blocked ficam em `manga_provider_rollout_status.md`.'
new = f'Atualmente existem **18 sources habilitadas** no manifest/registry. O receipt `docs/{receipt.name}` mantém MangaDex PT-BR e Manhastro `exhausted`; o fresh probe `{fresh_probe_run}` confirmou ambos `terminal=readable` até bytes. Taimu permanece `planned` após três HTTP 523 consecutivos no search live. Status/planned/blocked ficam em `manga_provider_rollout_status.md`.'
if old not in aggregation:
    raise SystemExit('aggregation registry paragraph not found')
aggregation = aggregation.replace(old, new, 1)
aggregation_path.write_text(aggregation, encoding='utf-8')
PY

git diff --check
