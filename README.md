# Offline Toolchains

Fábrica pública de workspaces Linux x86_64 para sessões que acessam o GitHub somente pelo conector e não conseguem executar `git clone` ou baixar SDKs/dependências diretamente.

O repositório possui três superfícies independentes:

1. **source bundles privados cifrados** — exportam o histórico Git do GoAnime Mobile ou ZapZap sem publicar plaintext;
2. **toolchains públicas sintéticas** — bootstrap rápido a partir de fixtures públicas;
3. **toolchains exatas** — leem locks dos dois repositórios privados com PAT somente leitura, provam resolução offline e publicam apenas SDKs/caches públicos.

## Artifact Platform v2

Todo pacote novo usa:

- manifest schema v2;
- artifacts segmentados em até 400 MiB;
- retenção de um dia;
- SHA-256 por parte e archive final;
- SPDX 2.3 JSON;
- doctor legível por máquina;
- fingerprints de lock e builder;
- reutilização de conjuntos equivalentes ainda vivos;
- limpeza conservadora de conjuntos antigos/orfãos;
- compatibilidade explícita para Linux x86_64.

Documentação:

- [Contrato de artifacts](docs/ARTIFACT_CONTRACT.md)
- [Registro de perfis](docs/PROFILE_REGISTRY.md)
- [Restaurar workspace em um comando](docs/RESTORE_WORKSPACE.md)
- [Design aprovado](docs/superpowers/specs/2026-07-31-artifact-platform-v2-design.md)
- [Plano de implementação](docs/superpowers/plans/2026-07-31-artifact-platform-v2.md)

## Perfis

| Perfil | Conteúdo principal |
| --- | --- |
| `android-base` | JDK 17, Android SDK 35/36, build-tools, NDK 27/28, CMake e platform-tools |
| `jdk21` | Temurin JDK 21 |
| `goanime-analysis` | Flutter 3.44.1, Dart, Pub cache e PowerShell |
| `goanime-android` | cache Gradle/AGP/Kotlin para build Android |
| `zapzap-pure` | cache Gradle/JVM para módulos puros |
| `zapzap-android` | cache Android/Compose/Gradle |
| `goanime-full` | agregado sem mega-archive: Android base + análise + Android |
| `zapzap-full` | agregado sem mega-archive: Android base + JDK 21 + pure + Android |

Agregados apenas expandem dependências em ordem; o restaurador baixa/extrai pacotes concretos.

## Pedir toolchain exata pelo conector

Atualize:

```text
Branch: build/toolchains
Path: triggers/toolchain-build.json
```

Exemplo:

```json
{
  "profile": "goanime-full",
  "force_rebuild": false
}
```

O request workflow não recebe secrets. Depois de validado, o workflow privilegiado carregado da `main` mapeia internamente somente:

```text
goanime → Semogtw/goanime-mobile
zapzap  → Semogtw/Zapzap
```

O resultado aparece no issue **#8 — Toolchain artifact catalog**, com run, build/reuse, fingerprints, IDs, tamanhos e expiração.

## Restaurar tudo

Depois de baixar pelo conector o source bundle cifrado e os artifacts dos perfis:

```bash
bash scripts/restore-workspace.sh \
  --project goanime \
  --downloads /mnt/data/downloads \
  --private-key /mnt/data/offline-toolchains-source-bundles-private.asc \
  --destination /mnt/data/goanime-mobile-offline \
  --profile goanime-full \
  --require-exact-lock \
  --report /mnt/data/restore-report.json
```

O restaurador valida transporte, chave OpenPGP, Git bundle, lock fingerprints, plataforma, arquitetura e doctors; produz `activate-workspace.sh`, executa `git fsck` e remove temporários por padrão.

A chave privada correspondente ao fingerprint abaixo **não fica no GitHub**:

```text
2DE29DC31427CF0A911AB96175679291435059B0
```

## Source bundles privados

O workflow `Build encrypted private source bundle` exporta apenas:

| Projeto | Repositório |
| --- | --- |
| `goanime` | `Semogtw/goanime-mobile` |
| `zapzap` | `Semogtw/Zapzap` |

Modos:

- `full` — branches/tags buscadas e histórico alcançável;
- `ref` — branch, tag ou SHA exato;
- `snapshot` — arquivos rastreados, sem `.git`.

O export não inclui LFS, submódulos, arquivos não rastreados, stash ou commits sem push.

Pelo conector, altere na branch `build/source-bundles`:

```text
triggers/private-source-bundle.json
```

Resultados são registrados no issue **#4 — Encrypted source bundle runs**.

O único secret exigido é:

```text
PRIVATE_REPOSITORIES_TOKEN
```

Ele deve ser fine-grained, `Contents: Read-only`, limitado aos dois repositórios privados e nunca é colocado em artifacts.

## Exato versus sintético

- `private-exact`: fingerprint derivado dos locks privados; resolução online seguida do mesmo gate offline no checkout exato.
- `synthetic`: fixture pública compatível; útil para bootstrap, não prova o lock privado atual.
- `not-applicable`: pacote compartilhado independente de projeto.

Use `--require-exact-lock` quando o resultado será tratado como ambiente determinístico para testes do checkout restaurado.

## Validação

```bash
python3 -m unittest discover -s tests -v
bash -n scripts/*.sh
python3 scripts/validate-workflows.py .github/workflows
bash scripts/validate-private-source-workflows.sh
```

Um workflow público verde prova fabricação/transporte da toolchain. Ele não substitui `flutter analyze`, `flutter test`, Gradle, Android, JNI, emulador ou aparelho no SHA privado restaurado.

## Segurança

- nunca versione a chave privada OpenPGP;
- nunca amplie o PAT para escrita ou repositórios arbitrários;
- trate artifacts como executáveis e use somente runs de commits confiáveis;
- verifique manifestos e checksums antes de extrair;
- não publique signing, Firebase config, TURN credentials, `local.properties` ou código privado;
- source bundles `private-source-*` são excluídos da limpeza automática;
- falhas de catálogo/limpeza não apagam conjuntos cuja identidade não seja comprovada.
