# Offline Toolchains

Repositório público que concentra toolchains reutilizáveis, CI pesado, builds de verificação e transferências cifradas dos projetos em desenvolvimento da conta `Semogtw`.

O objetivo é deslocar para runners públicos o trabalho que pode ser executado com segurança fora dos repositórios privados, preservando uma fronteira rígida para source privado, APKs, credenciais, signing e dados sensíveis.

## Modelo atual

O repositório separa quatro responsabilidades:

1. **toolchains públicos reutilizáveis** — SDKs, runtimes e caches que não contêm source ou segredo privado;
2. **CI de projetos privados em runner público** — checkout efêmero com token read-only, gates reais e descarte dos outputs;
3. **transferências privadas cifradas** — source bundles e APKs são cifrados antes de qualquer `upload-artifact`;
4. **operações privilegiadas isoladas** — release, signing, deploy e escrita em repositórios privados não recebem automaticamente credenciais amplas no hub público.

A política canônica está em [`docs/WORKFLOW_HUB_SECURITY.md`](docs/WORKFLOW_HUB_SECURITY.md). O inventário versionado dos projetos está em [`config/workflow-hub-projects.json`](config/workflow-hub-projects.json).

## Projetos cobertos

| Projeto | Repositório | Cobertura central |
| --- | --- | --- |
| GoAnime | `Semogtw/goanime-mobile` | CI Flutter/Android, APK debug cifrado, source export cifrado, refresh de catálogo e smoke desktop Windows/Linux |
| ZapZap | `Semogtw/Zapzap` | CI Android, APK debug cifrado e source export cifrado |
| SemogSite | `Semogtw/SemogSite` | gates do monorepo, build web, Playwright e source export cifrado |
| Hydra | `Semogtw/HydraPersonalizado` | Node/Yarn, GTK4 Layer Shell, Rust, testes/typechecks/build e source export cifrado |
| Receitas | `Semogtw/Receitas` | guard de fase de planejamento e source export cifrado; o gate falha quando uma stack executável aparecer sem perfil correspondente |
| Fichário Virtual | `Semogtw/FicharioVirtual` | verificação completa token-free por ser source público |
| Codex/Gemini helpers | `Semogtw/codex-desktop-linux-gemini-` e `Semogtw/codex-gemini-agents` | toolchains e verificações públicas |

Detalhes operacionais do CI privado: [`docs/private-project-ci.md`](docs/private-project-ci.md).

## Retenção de artifacts

Retenção segue sensibilidade, não uma regra única para tudo:

- **source privado, APK privado e qualquer transferência sensível:** exatamente `retention-days: 1`;
- **toolchains explicitamente públicos e relatórios públicos sanitizados:** até 7 dias, para permitir reuso sem reconstrução constante;
- todo `actions/upload-artifact` deve declarar a retenção explicitamente.

`Validate workflow hub security` verifica essa política automaticamente.

## Segurança de source privado

Workflows que recebem `PRIVATE_REPOSITORIES_TOKEN` seguem estas regras:

- repositório é mapeado por allowlist; request não fornece owner/repo arbitrário;
- token deve ser fine-grained e `Contents: Read-only`;
- `persist-credentials: false`;
- sem `pull_request_target`, `secrets: inherit`, `write-all` ou shell xtrace;
- sem cache persistente derivado do checkout privado;
- LFS e submódulos ficam desligados salvo revisão explícita;
- checkout e outputs privados são removidos em cleanup `always()`;
- logs são tratados como públicos e não devem despejar source, ambiente ou dados sensíveis.

O secret esperado para checkout é:

```text
PRIVATE_REPOSITORIES_TOKEN
```

Ele deve ter somente `Contents: Read-only` para os privados atualmente servidos pelo hub:

```text
goanime-mobile
Zapzap
SemogSite
HydraPersonalizado
Receitas
```

Não use esse token para escrita.

### Escrita excepcional no GoAnime

O refresh de catálogo precisa publicar caches gerados de volta no GoAnime. Essa capacidade foi separada em outro secret:

```text
GOANIME_CATALOG_WRITE_TOKEN
```

Esse token deve ser fine-grained, restrito **somente** a `Semogtw/goanime-mobile`, com `Contents: Read and write`. Ele entra apenas na etapa de publish por header HTTP efêmero e não é persistido pelo checkout.

## Source bundles privados cifrados

`Build encrypted private source bundle` aceita somente estes projetos fixos:

```text
goanime   -> Semogtw/goanime-mobile
zapzap    -> Semogtw/Zapzap
semogsite -> Semogtw/SemogSite
hydra     -> Semogtw/HydraPersonalizado
receitas  -> Semogtw/Receitas
```

Modos:

- `full`: refs e histórico alcançável pelo checkout completo;
- `ref`: branch, tag ou SHA exato em Git bundle reduzido;
- `snapshot`: arquivos rastreados de um commit, sem `.git`.

O workflow monta o pacote em área temporária, importa **somente** a chave pública OpenPGP, verifica o fingerprint fixo, cifra o archive e remove package plaintext, checkout privado e keyring antes do upload.

Fingerprint esperado:

```text
2DE29DC31427CF0A911AB96175679291435059B0
```

A chave pública fica em `keys/source-bundles-public.asc`. A chave privada correspondente nunca deve entrar no GitHub.

O artifact final contém somente ciphertext particionado quando necessário, `SHA256SUMS.parts` e metadados sanitizados de transporte, com retenção de 1 dia. Repositório/ref/commit detalhados permanecem dentro do conteúdo cifrado.

## APKs privados

GoAnime e ZapZap têm handoff dedicado de APK debug cifrado.

Fluxo obrigatório:

1. resolver ref permitida e fazer checkout read-only;
2. executar os gates/builds necessários;
3. validar integridade/assinatura aplicável do APK;
4. calcular SHA-256 e tamanho para metadados sanitizados;
5. cifrar com a chave pública OpenPGP pinada;
6. apagar checkout e APK plaintext **antes** do upload;
7. subir somente `.gpg` + metadata sanitizada;
8. reter por 1 dia;
9. executar cleanup de fallback com `always()`.

O workflow público não recebe a chave OpenPGP privada nem credenciais de signing de produção.

## GoAnime desktop smoke

`Run private GoAnime desktop smoke` substitui o antigo smoke semanal executado dentro do repositório privado. Ele roda às segundas, `09:00 UTC`, em Windows e Linux, valida playback HLS e constrói os targets desktop sem publicar os outputs.

Mais detalhes: [`docs/GOANIME_DESKTOP_SMOKE.md`](docs/GOANIME_DESKTOP_SMOKE.md).

O antigo `android_debug_build.yml` privado também foi substituído pelo build central e pelo handoff de APK criptografado.

## Toolchains públicos

Os bundles públicos continuam servindo restauração/offline de ambientes sem incluir source privado ou credenciais. Entre os principais perfis estão:

| Prefixo | Conteúdo |
| --- | --- |
| `android-base-linux-x64-*` | JDK/Android SDK/build-tools/NDK/CMake compartilhados |
| `goanime-flutter-cache-linux-x64-*` | Flutter/Dart e base de execução do GoAnime |
| `goanime-lock-delta-linux-x64-*` | delta Pub exato para o lock observado |
| `goanime-gradle-delta-linux-x64-*` | coordenadas Maven pontuais e instalador idempotente |
| `zapzap-gradle-cache-linux-x64-*` | Gradle/AGP/Kotlin/Compose e dependências Android públicas |

Pacotes grandes podem ser divididos em partes de 400 MiB. Sempre valide checksums/manifests antes de executar conteúdo restaurado.

## Fronteira deliberada

Centralizar para aproveitar runners públicos **não** significa mover todo segredo para um repositório público.

Release assinada, Shorebird, Firebase/produção, R2 com escrita, TURN, deploy, bancos de produção e outras operações privilegiadas permanecem fora de um workflow genérico até receberem um threat model e uma credencial mínima dedicada. Quando apenas o compute é pesado, prefira mover o build/teste para o hub e manter a etapa privilegiada pequena e isolada.

No GoAnime, por exemplo, workflows de release/patch/credenciais continuam no projeto privado enquanto smoke desktop e APK debug foram absorvidos pelo hub público.

## Validação

Depois de alterar o hub privado:

```bash
python3 scripts/test_private_ci_request.py
python3 scripts/test-private-ci-toolchain-policy.py
python3 scripts/test-semogsite-install-policy.py
python3 scripts/validate-private-ci-workflows.py
python3 scripts/validate-workflow-hub-security.py
```

Para fluxos de source privado, mantenha também os validadores específicos existentes em `scripts/`.

Os workflows `Validate private CI hub` e `Validate workflow hub security` executam os contratos principais no GitHub Actions.

## Regras para novas integrações

Ao adicionar outro projeto em desenvolvimento:

1. registre repositório/ref/política em `config/workflow-hub-projects.json`;
2. use mapping fixo em código confiável, nunca `repository`/`command` arbitrário vindo de input;
3. prefira `PRIVATE_REPOSITORIES_TOKEN` read-only;
4. descarte outputs privados por padrão;
5. se o usuário precisar baixar algo privado, crie transferência OpenPGP ciphertext-only com 1 dia;
6. use credencial de escrita dedicada por operação/repositório quando escrita for realmente necessária;
7. atualize contratos/testes/documentação junto com o workflow;
8. mantenha release/deploy privilegiado fora do hub genérico até revisão específica.
