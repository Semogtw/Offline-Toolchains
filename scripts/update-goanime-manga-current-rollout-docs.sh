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
text = receipt.read_text(encoding='utf-8')


def metric(label: str) -> int:
    match = re.search(rf'^- {re.escape(label)}: \*\*(\d+)\*\*$', text, flags=re.MULTILINE)
    if not match:
        raise SystemExit(f'missing receipt metric: {label}')
    return int(match.group(1))


def provider(source_id: str) -> tuple[str, int, str]:
    match = re.search(
        rf'^\| `{re.escape(source_id)}` \| ([^|]+) \|\s*(\d+) \| `([^`]+)` \|$',
        text,
        flags=re.MULTILINE,
    )
    if not match:
        raise SystemExit(f'missing receipt provider row: {source_id}')
    return match.group(1).strip(), int(match.group(2)), match.group(3)

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
    raise SystemExit(f'target providers are not exhaustive: mangadex={mangadex} manhastro={manhastro}')

head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
branch = 'feat/manga-sources-mangadex-taimu-manhastro-20260828'
fresh_probe_run = '33341458888'
fresh_probe_sha = 'cd5158b55e075504dfbaefa4760c21428f5b3134'

rollout = f'''# Manga provider rollout status

> **Status: atual para desenvolvimento.** Este documento é a fonte operacional compacta da branch MangaDex / Taimu / Manhastro. Receipts são evidência do SHA em que foram materializados; probes live são evidência do SHA em que foram executados.

**Atualizado em:** 2026-08-30  
**Branch:** `{branch}`  
**Checkpoint observado antes deste commit documental:** `{head}`  
**Último receipt global:** `docs/{receipt.name}`  
**Último probe live dos três candidates:** Offline-Toolchains run `{fresh_probe_run}` sobre `{fresh_probe_sha}`

## Resumo executivo

- O runtime padrão autoriza **{metrics['enabled']} providers**.
- `ptbr.mangadex` e `ptbr.manhastro` estão habilitados.
- `ptbr.taimumangas` continua **planned** e fora de `defaultEnabledMangaSourceIds`.
- O receipt atual contém **{metrics['works']:,} obras canônicas**, **{metrics['links']:,} ocorrências de fonte**, **{metrics['readable']:,} links com readability comprovada** e **{metrics['listed']:,} links listed-only**.
- A rodada materializada refreshou exatamente **{metrics['refreshed']} providers** e carregou **{metrics['carried']}** partições conhecidas anteriores.
- MangaDex foi enumerado como `exhausted` com **{mangadex[1]:,} ocorrências únicas**.
- Manhastro foi enumerado como `exhausted` com **{manhastro[1]:,} ocorrências únicas**.
- No probe live `{fresh_probe_run}`, MangaDex e Manhastro completaram search → details → chapters → content → transporte de bytes e terminaram `terminal=readable`.
- No mesmo probe, Taimu falhou **3/3 tentativas de search** com HTTP **523** em `apiv2.taimumangas.com`, terminando `terminal=no_search_result`. O bloqueio observado é upstream/live, não falha dos testes determinísticos do adapter.

## Autorização runtime

`defaultEnabledMangaSourceIds` autoriza atualmente **18** fontes:

1. `ptbr.arthurscan`
2. `ptbr.astratoons`
3. `ptbr.capitoons`
4. `ptbr.hqnow`
5. `ptbr.hipertoon`
6. `ptbr.kamisamaexplorer`
7. `ptbr.kivaratoons`
8. `ptbr.leituramanga`
9. `ptbr.ler999`
10. `ptbr.littletyrant`
11. `ptbr.maidscan`
12. `ptbr.mangadash`
13. `ptbr.mangadex`
14. `ptbr.mangaflix`
15. `ptbr.mangalivreblog`
16. `ptbr.mangalivreorg`
17. `ptbr.manhastro`
18. `ptbr.ninjascan`

`ptbr.taimumangas` permanece `planned`. O baseline histórico PT-BR continua **114 inventariadas / 98 permitidas / 16 excluídas**; MangaDex é externo ao snapshot `src/pt` e não altera esse accounting.

## Estado do catálogo global materializado

Receipt: `docs/{receipt.name}`.

```text
enabledProviders={metrics['enabled']}
refreshedProviders={metrics['refreshed']}
carriedForwardProviders={metrics['carried']}
canonicalWorks={metrics['works']}
sourceOccurrences={metrics['links']}
readableProvenLinks={metrics['readable']}
listedOnlyLinks={metrics['listed']}
```

Refresh exaustivo observado:

```text
ptbr.mangadex  exhausted  {mangadex[1]}  {mangadex[2]}
ptbr.manhastro exhausted  {manhastro[1]}  {manhastro[2]}
```

A política do bundle continua fail-safe: partição `exhausted` substitui sua versão anterior; provider `partial`, `failed`, `blocked`, não selecionado ou não enumerável preserva a partição conhecida anterior em vez de apagar catálogo válido.

**Listed availability e readability são garantias diferentes.** Listing confirmado pode alimentar inventário/browse interno, mas o Reader continua exigindo resolução legível/prova compatível.

## Hardening atual — MangaDex

O adapter/inventário MangaDex está fail-closed nos principais contratos de paginação e conteúdo:

- inventário separado por `safe` e `suggestive` em páginas de 100;
- page tokens precisam ser offsets inteiros não-negativos;
- `limit`, `offset` e `total` da resposta são validados;
- `total` ausente/malformado não é reinterpretado como fim de paginação;
- recursos malformados em search/chapters/AtHome falham a operação em vez de produzir coleção parcial;
- chapters rejeita linguagem inesperada;
- metadata numérica fracionária não é truncada silenciosamente;
- paginação de capítulos possui cap explícito;
- retry especial de HTTP 400 é restrito a MangaDex **e** `api.mangadex.org`;
- hosts `*.mangadex.network` são aceitos somente pela suffix policy com boundary de label.

## Hardening atual — Manhastro

A API live atual de Manhastro é paginada e o provider acompanha esse contrato diretamente:

- search envia `page`, `per_page=100` e filtro server-side `nome` quando há query;
- details resolve por `manga_id` e exige cardinalidade/identidade coerentes;
- cache é por consulta/página e itens validados podem ser reutilizados no details;
- o único registro live observado com ID válido mas nenhum título textual utilizável é explicitamente não catalogável; outros itens estruturalmente inválidos continuam fail-closed;
- `meta.current_page/per_page/total/last_page/has_more` é validado estritamente;
- a página terminal pode conter overlap real do upstream, mas nunca pode ficar abaixo do mínimo implicado por `total`;
- IDs numéricos fracionários são rejeitados;
- envelopes exigem `success == true`;
- capítulos/páginas inválidos não geram listas/manifests parciais;
- capas de search/details, inclusive fallback legado, só sobrevivem quando o host passa por `MangaProviderPolicy.allowsContentHost`.

No inventário certificado, os 3 itens extras observados na última página são overlap do upstream e são deduplicados por `(sourceId, mangaId)`; a partição ainda termina `exhausted`.

## Hardening atual — Taimu

Taimu continua implementado porém `planned`:

- page token e identidade da página de resposta são validados;
- continuation metadata precisa existir e ser coerente;
- páginas vazias que afirmam continuação falham fechado;
- metadata de paginação fracionária é rejeitada;
- search/details/chapters/pages rejeitam itens malformados;
- `adult=true` é rejeitado e a busca usa `adult=false`;
- paginação de capítulos possui cap de 100 requests;
- capas de search/details e fallback legado obedecem à content-host policy.

A evidência live mais recente não autoriza promoção: run `{fresh_probe_run}` recebeu HTTP 523 em todas as três tentativas de search antes de qualquer resultado. Uma promoção futura exige nova prova reproduzível até bytes.

## Transporte e segurança compartilhados

- `MangaRemoteContentProbe` valida o host inicial pela policy antes de I/O;
- o Reader respeita hosts exatos e `allowedContentHostSuffixes`;
- redirects continuam sob `MangaHttpClient` e headers sensíveis não atravessam hosts não confiáveis;
- HTTP 200 com HTML/challenge não conta como imagem/PDF;
- URLs assinadas, cookies, tokens e headers efêmeros não entram no estado durável;
- o materializador executa formatter, diff guard, analyzer e testes dos providers/readability antes de inventário/build/publicação.

## Evidência live fresca — 2026-08-30

Offline-Toolchains run `{fresh_probe_run}`, SHA `{fresh_probe_sha}`:

```text
ptbr.mangadex:
  search=24 resultados
  details=success
  chapters=success (26)
  content=imageSequence
  transport=success
  verifier=success
  terminal=readable

ptbr.taimumangas:
  search attempt 1 = HTTP 523
  search attempt 2 = HTTP 523
  search attempt 3 = HTTP 523
  host=apiv2.taimumangas.com
  terminal=no_search_result

ptbr.manhastro:
  search=99 resultados
  details=success
  chapters=success (143)
  content=imageSequence
  transport=success
  verifier=success
  terminal=readable
```

A auditoria de segurança Manhastro da mesma rodada completou 4/4 queries e 12 details; a amostra teve 1 ocorrência com marcador explícito e a primeira página do catálogo teve 2/100 ocorrências com marcador explícito. Isso não altera a classificação atual de não adult-primary.

## Gates e afirmações permitidas

### Pode ser afirmado

- MangaDex e Manhastro estão habilitados no runtime padrão;
- ambos têm partições atuais `exhausted` no receipt mais recente;
- ambos possuem prova live fresh até bytes em 2026-08-30;
- Taimu possui implementação/testes determinísticos, mas continua `planned` por HTTP 523 live;
- o materializador preserva partições degradadas e não converte listing em readability automaticamente.

### Não pode ser afirmado

- que Taimu é live/readable ou pronto para promoção;
- que todos os {metrics['links']:,} links do bundle são readable;
- que um receipt antigo certifica código posterior que altera MangaDex/Manhastro ou o pipeline de materialização.

## Próxima sequência operacional

1. Manter Taimu fora do runtime padrão até nova prova live reproduzível search → details → chapters → bytes.
2. Continuar hardening fail-closed apenas quando houver contrato real/teste que o justifique.
3. Após mudanças em providers materializados, rodar novamente o materializador exact-SHA com CAS.
4. Antes de merge, rodar o verifier final de rollout exact-SHA, incluindo docs/manifest/registry, provider tests, analyzer, receipt, drift e fresh byte probes de MangaDex + Manhastro.

## Referências

- `docs/{receipt.name}` — bundle global atual;
- `docs/manga_ptbr_provider_audit.md` — auditoria PT-BR e histórico de rollout;
- `docs/manga_source_aggregation.md` — agregação/canonicalização;
- `docs/manga_sources_ptbr.md` / `docs/manga_sources_ptbr.json` — baseline de policy/inventory;
- `tools/manga/inventory_manga_catalog.dart` — inventário runtime;
- `tools/manga/materialize_global_manga_availability_ci.sh` — materializador/gate global.

Detalhes históricos continuam recuperáveis no Git e nos receipts datados. Estado operacional deve ser interpretado pelo SHA e pelo run explicitamente citados, não apenas pela data do arquivo.
'''
rollout = rollout.replace(',', '.')
(root / 'docs/manga_provider_rollout_status.md').write_text(rollout, encoding='utf-8')

# Prepend/replace a compact current checkpoint in the deeper audit while keeping history.
audit_path = root / 'docs/manga_ptbr_provider_audit.md'
audit = audit_path.read_text(encoding='utf-8')
current = f'''<!-- current-2026-08-30:start -->
## Checkpoint atual — 2026-08-30

- Branch: `{branch}`.
- Checkpoint observado antes deste commit documental: `{head}`.
- Receipt atual: `docs/{receipt.name}` com **{metrics['works']:,} obras**, **{metrics['links']:,} ocorrências**, **{metrics['readable']:,} readable-proven** e **{metrics['listed']:,} listed-only**.
- `ptbr.mangadex`: enabled, `exhausted` com **{mangadex[1]:,} ocorrências únicas; fresh probe `{fresh_probe_run}` terminou `terminal=readable` até bytes.
- `ptbr.manhastro`: enabled, `exhausted` com **{manhastro[1]:,} ocorrências únicas; fresh probe `{fresh_probe_run}` terminou `terminal=readable` até bytes.
- `ptbr.taimumangas`: `planned`; no fresh probe `{fresh_probe_run}`, 3/3 buscas retornaram HTTP **523** de `apiv2.taimumangas.com`, antes de qualquer resultado.
- Manhastro agora segue paginação live server-side, details por `manga_id`, tolera apenas overlap terminal seguro, rejeita underfill terminal e filtra capas pela content-host policy.
- Taimu/Manhastro filtram capas de search/details e fallbacks legados pela `MangaProviderPolicy`; Reader/readability probe também validam content hosts antes de I/O.

Este checkpoint substitui os números operacionais antigos abaixo; as seções históricas permanecem como evidência datada e não como garantia do HEAD atual.
<!-- current-2026-08-30:end -->
'''.replace(',', '.')
pattern = re.compile(r'<!-- current-2026-08-30:start -->.*?<!-- current-2026-08-30:end -->\n?', re.S)
if pattern.search(audit):
    audit = pattern.sub(current + '\n', audit, count=1)
else:
    marker = '**Checkpoint de promoção:** `39993790a0f4ab99c2937ffca6ecb62d87ff1925`\n'
    if marker not in audit:
        raise SystemExit('audit insertion marker not found')
    audit = audit.replace(marker, marker + '\n' + current + '\n', 1)
audit_path.write_text(audit, encoding='utf-8')

# Keep compact entrypoints current without turning them into historical ledgers.
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
aggregation = aggregation.replace(
    '> **Status: Atual — implementado.** O modelo multi-source, registry, busca, matching, merge, ranking e roteamento existem no runtime de `codex/manga-parity-20260823`.',
    f'> **Status: Atual — implementado.** O modelo multi-source, registry, busca, matching, merge, ranking e roteamento existem no runtime; o checkpoint operacional de providers está na branch `{branch}`.',
    1,
)
aggregation = aggregation.replace('**Última atualização:** 2026-08-28', '**Última atualização:** 2026-08-30', 1)
old = 'Atualmente existem **18 sources habilitadas** no manifest/registry. MangaDex PT-BR e Manhastro foram promovidas no exact-SHA `39993790a0f4ab99c2937ffca6ecb62d87ff1925` após fixtures, accounting/registry, drift e byte probes verdes; Taimu permanece `planned` por HTTP 522/523 upstream. Status/planned/blocked ficam em `manga_provider_rollout_status.md`.'
new = f'Atualmente existem **18 sources habilitadas** no manifest/registry. O receipt `docs/{receipt.name}` mantém MangaDex PT-BR e Manhastro `exhausted`; o fresh probe `{fresh_probe_run}` confirmou ambos `terminal=readable` até bytes. Taimu permanece `planned` após três HTTP 523 consecutivos no search live. Status/planned/blocked ficam em `manga_provider_rollout_status.md`.'
if old not in aggregation:
    raise SystemExit('aggregation registry paragraph not found')
aggregation = aggregation.replace(old, new, 1)
aggregation_path.write_text(aggregation, encoding='utf-8')
PY

git diff --check
