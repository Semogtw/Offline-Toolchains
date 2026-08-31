#!/usr/bin/env bash
set -euo pipefail

repo="${1:-.}"
cd "$repo"

python3 - <<'PY'
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, found {count}: {old[:100]!r}")
    p.write_text(text.replace(old, new, 1))

# The current desktop shader implementation intentionally needs the GLSL files in
# Flutter's asset bundle for direct desktop builds. Keep the platform boundary on
# usage/registration, not on whether an inert data asset exists in the bundle.
replace_once(
    'test/architecture/platform_boundaries_test.dart',
    "  test('mobile package excludes desktop discord and upscaling assets', () {\n",
    "  test('desktop-only integrations stay isolated while shaders remain bundled', () {\n",
)
replace_once(
    'test/architecture/platform_boundaries_test.dart',
    "    expect(\n      pubspec,\n      isNot(contains('assets/shaders/')),\n      reason: 'Anime4K/ArtCNN shaders must not be global mobile assets.',\n    );\n",
    "    expect(\n      pubspec,\n      contains('assets/shaders/'),\n      reason:\n          'Desktop Flutter builds resolve Anime4K/ArtCNN from the application asset bundle.',\n    );\n\n    for (final file in _dartFilesUnder('lib/platform/mobile')) {\n      final source = file.readAsStringSync();\n      expect(\n        source,\n        isNot(contains('assets/shaders/')),\n        reason:\n            '${_normalizedPath(file.path)} must not load desktop shader assets on mobile.',\n      );\n      expect(\n        source,\n        isNot(contains('glsl-shaders')),\n        reason:\n            '${_normalizedPath(file.path)} must not issue desktop mpv GLSL commands.',\n      );\n    }\n",
)

# Replace the branch-hardcoded AI guard with durable checkout/status ownership.
p = Path('test/architecture/active_parity_documentation_guard_test.dart')
text = p.read_text()
start = text.index("  test('active AI entrypoints track parity branch and dynamic providers', () {")
end = text.index("\n  test('current manga owner docs do not claim the legacy branch'", start)
new_block = r'''  test('active AI entrypoints use checkout authority and dynamic providers', () {
    const staleActiveBranches = <String>[
      'codex/manga-parity-20260823',
      'feature/manga-platform',
      'fix/catalog-search-manga-regressions-20260826',
      'feat/manga-sources-mangadex-taimu-manhastro-20260828',
    ];
    const sharedStatus = 'shared_media_infrastructure_status_2026-08-24.md';
    const rolloutStatus = 'manga_provider_rollout_status.md';
    const entrypoints = <String>[
      'README_AI.md',
      'docs/ai/README.md',
      'docs/ai/repository_map.md',
      'docs/ai/change_impact_matrix.md',
      'docs/ai/sources_of_truth.md',
      'NEXT_AGENT.md',
    ];

    for (final path in entrypoints) {
      final content = _readText(path);
      for (final staleBranch in staleActiveBranches) {
        expect(
          content,
          isNot(contains(staleBranch)),
          reason: '$path must not advertise stale branch $staleBranch as active.',
        );
      }
      expect(content, contains('checkout'));
      expect(content, contains(rolloutStatus));
    }

    final readmeAi = _readText('README_AI.md');
    final router = _readText('docs/ai/README.md');
    final matrix = _readText('docs/ai/change_impact_matrix.md');

    expect(readmeAi, contains(sharedStatus));
    expect(router, contains(sharedStatus));
    expect(matrix, contains(sharedStatus));
    expect(readmeAi, contains('defaultEnabledMangaSourceIds'));
    expect(router, contains('defaultEnabledMangaSourceIds'));
    expect(readmeAi, isNot(contains('17 fontes PT-BR')));
    expect(router, isNot(contains('16 IDs em `defaultEnabledMangaSourceIds`')));
    expect(matrix, isNot(contains('16 enabled atuais')));
  });
'''
p.write_text(text[:start] + new_block + text[end:])

# README_AI: keep rollout ownership but make it valid on main and any future branch.
replace_once(
    'README_AI.md',
    "O estado operacional atual de MangaDex / Taimu / Manhastro pertence a `docs/manga_provider_rollout_status.md` na branch `feat/manga-sources-mangadex-taimu-manhastro-20260828`. O receipt global atual é `docs/manga_global_availability_receipt_2026-08-30.md`; MangaDex e Manhastro estão enabled/exhaustive, enquanto Taimu permanece `planned` após 3/3 HTTP 523 no fresh probe `33341458888`. A branch efetivamente em checkout continua sendo a autoridade para qualquer tarefa.",
    "O estado operacional atual de MangaDex / Taimu / Manhastro pertence a `docs/manga_provider_rollout_status.md` no checkout versionado atual. O receipt global atual é `docs/manga_global_availability_receipt_2026-08-30.md`; MangaDex e Manhastro estão enabled/exhaustive, enquanto Taimu permanece `planned` após 3/3 HTTP 523 no fresh probe `33341458888`. A branch efetivamente em checkout continua sendo a autoridade para qualquer tarefa; nomes de branches históricas não definem o runtime atual.",
)

replace_once(
    'docs/ai/README.md',
    "A linha ativa é `codex/manga-parity-20260823`. Ela contém o runtime funcional de Mangá e o trabalho de paridade/infraestrutura compartilhada Anime ↔ Mangá. A `main` permanece um alvo de integração separado até merge explícito; nunca atribua automaticamente ao checkout atual um commit presente somente em outra branch.\n\nEstado das fases shared-media: `docs/shared_media_infrastructure_status_2026-08-24.md`.",
    "O checkout versionado atual é a autoridade para código e testes. O estado operacional de providers de Mangá pertence a `docs/manga_provider_rollout_status.md`; não use um nome de branch histórico como fonte de verdade. Depois de merge/rebase, reconcilie docs com o SHA realmente em checkout.\n\nEstado das fases shared-media: `docs/shared_media_infrastructure_status_2026-08-24.md`.",
)

replace_once(
    'docs/ai/repository_map.md',
    "Este mapa descreve ownership e direção de dependência no estado atual de `codex/manga-parity-20260823`. Para política normativa, leia `AGENTS.md`; para status funcional de Mangá, `docs/manga_product_parity.md`; para a consolidação Anime ↔ Mangá, `docs/shared_media_infrastructure_status_2026-08-24.md`.\n\nA `main` é um alvo de integração separado até merge explícito. Um mapa de outra branch não substitui código/testes do checkout atual.",
    "Este mapa descreve ownership e direção de dependência do checkout versionado atual. Para política normativa, leia `AGENTS.md`; para status funcional de Mangá, `docs/manga_product_parity.md`; para rollout de providers, `docs/manga_provider_rollout_status.md`; para a consolidação Anime ↔ Mangá, `docs/shared_media_infrastructure_status_2026-08-24.md`.\n\nCódigo e testes do checkout atual são a autoridade. Um mapa ou commit de outra branch não substitui o estado realmente em checkout; depois de merge/rebase, reconcilie este documento com o novo SHA.",
)

replace_once(
    'docs/ai/change_impact_matrix.md',
    "Linha ativa: `codex/manga-parity-20260823`. Estado shared-media: `docs/shared_media_infrastructure_status_2026-08-24.md`.",
    "Autoridade: checkout versionado atual. Rollout de Mangá: `docs/manga_provider_rollout_status.md`. Estado shared-media: `docs/shared_media_infrastructure_status_2026-08-24.md`.",
)
replace_once(
    'docs/ai/change_impact_matrix.md',
    "## Regras especiais da linha de paridade\n\n### Não misturar status de branches\n\n`codex/manga-parity-20260823` é a linha ativa desta documentação. A `main` e outras branches só passam a descrever este runtime depois de merge/rebase explícito e reconciliação de docs. Um commit mais recente fora do checkout não sobrepõe o código atual.",
    "## Regras especiais do runtime atual\n\n### Não misturar status de branches\n\nO checkout versionado atual é a linha ativa desta documentação. `docs/manga_provider_rollout_status.md` registra o estado operacional dos providers; outra branch só altera esse estado depois de merge/rebase explícito e reconciliação de docs. Um commit mais recente fora do checkout não sobrepõe o código atual.",
)

replace_once(
    'docs/ai/sources_of_truth.md',
    "Há duas referências diferentes que não devem ser confundidas:\n\n- `main`: runtime integrado oficial;\n- `codex/manga-parity-20260823`: linha ativa de paridade/unificação Anime ↔ Mangá e evolução atual do runtime de Mangá.\n\nA antiga `feature/manga-platform` é ancestral/histórico dessa linha e não deve mais ser usada como branch ativa por agentes trabalhando no programa atual.\n\nPara a unificação shared-media, o checkpoint operacional atual é [`../shared_media_infrastructure_status_2026-08-24.md`](../shared_media_infrastructure_status_2026-08-24.md).\n\nUm commit mais novo em outra branch não sobrepõe automaticamente o código do checkout atual. Depois de merge/rebase, a documentação deve ser reconciliada junto com o código.",
    "A referência ativa é sempre o checkout versionado sobre o qual a tarefa está sendo executada. `main` representa o runtime integrado oficial quando ela própria está em checkout, mas um nome de branch não substitui código/testes do SHA observado.\n\nO estado operacional dos providers de Mangá pertence a [`../manga_provider_rollout_status.md`](../manga_provider_rollout_status.md). Para a unificação shared-media, o checkpoint operacional atual é [`../shared_media_infrastructure_status_2026-08-24.md`](../shared_media_infrastructure_status_2026-08-24.md).\n\nUm commit mais novo em outra branch não sobrepõe automaticamente o código do checkout atual. Depois de merge/rebase, a documentação deve ser reconciliada junto com o código.",
)

replace_once(
    'docs/manga_availability_policy.md',
    "> **Status: Atual — implementado no runtime.** Readability é gate de produto; o catálogo bundled, overlay runtime, registry e providers habilitados já participam do fluxo normal de `codex/manga-parity-20260823`.",
    "> **Status: Atual — implementado no runtime.** Readability é gate de produto; o catálogo bundled, overlay runtime, registry e providers habilitados participam do fluxo normal do checkout atual. O rollout operacional pertence a `manga_provider_rollout_status.md`.",
)
replace_once(
    'docs/manga_availability_policy.md',
    "- `ptbr.mangalivreorg`;\n- `ptbr.ninjascan`.",
    "- `ptbr.mangalivreorg`;\n- `ptbr.mangadex`;\n- `ptbr.manhastro`;\n- `ptbr.ninjascan`.",
)

Path('NEXT_AGENT.md').write_text('''# Handoff para o próximo agente\n\n**Atualizado em:** 2026-08-30  \n**Repositório:** `Semogtw/goanime-mobile` — GoAnime-Mobile.\n\n## Autoridade do checkout\n\nO checkout versionado atual é a autoridade. Não trate nomes de branches históricas como linha ativa e não atribua ao checkout commits presentes somente em outra branch. Depois de merge/rebase, confirme o SHA e reconcilie docs antes de afirmar estado.\n\n## Leia primeiro\n\n1. `AGENTS.md`;\n2. `README_AI.md`;\n3. `docs/ai/README.md`;\n4. `docs/ai/sources_of_truth.md`;\n5. `docs/manga_provider_rollout_status.md` para providers de Mangá;\n6. `docs/manga_global_availability_receipt_2026-08-30.md` para o bundle materializado;\n7. `docs/shared_media_infrastructure_status_2026-08-24.md` para infraestrutura compartilhada.\n\n## Estado operacional de Mangá\n\n- `defaultEnabledMangaSourceIds` é a autorização runtime; não copie contagens antigas para novos docs.\n- MangaDex e Manhastro estão habilitados e possuem partições exaustivas no receipt atual.\n- Taimu possui adapter/fixtures endurecidos, mas permanece `planned`: a última evidência live falhou antes de search com 3/3 HTTP 523. Promoção exige novamente search → details → chapters → content → bytes reproduzível.\n- Listing e readability são garantias diferentes; carry-forward não deve ressuscitar proof expirada.\n\n## Validação\n\nUse testes e gates proporcionais ao SHA exato. Focused gates não substituem full CI quando a integração toca áreas amplas. Se os runners privados falharem antes do step 1, reproduza os mesmos comandos em runner funcional e registre a evidência em vez de classificar provisioning como regressão de código.\n\nPara checkout privado e toolchains auxiliares use `Semogtw/Offline-Toolchains`. Não registre tokens, cookies, URLs assinadas ou payloads sensíveis.\n\n## Próxima decisão\n\nAntes de qualquer merge, confirme que a branch alvo não avançou desde a reconciliação e rode novamente os gates do merge resultante. Depois do merge, a `main` integrada passa a ser a autoridade somente após o SHA remoto e os checks aplicáveis serem confirmados.\n''')
PY

dart format \
  test/architecture/platform_boundaries_test.dart \
  test/architecture/active_parity_documentation_guard_test.dart

git diff --check
