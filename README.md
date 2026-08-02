# Offline Toolchains

Repositório público para fabricar ambientes Linux x64 reutilizáveis em sessões que acessam o GitHub pelo conector, mas não conseguem baixar diretamente SDKs, dependências ou checkouts privados.

O projeto separa deliberadamente três responsabilidades:

1. **bases públicas grandes e estáveis** — SDKs, runtimes e caches amplos;
2. **deltas públicos pequenos e exatos** — versões Pub ou coordenadas Maven que mudam com mais frequência;
3. **source bundles privados cifrados** — exports Git criptografados antes do upload.

Nenhum artifact público contém source privado, Firebase, Shorebird, signing, tokens ou configuração local dos aplicativos.

## Artifacts públicos

| Prefixo | Conteúdo | Uso |
| --- | --- | --- |
| `android-base-linux-x64-*` | Temurin JDK 17, Android SDK 33/35/36, build-tools, platform-tools, NDK e CMake | Base Android comum para GoAnime-Mobile e ZapZap |
| `goanime-flutter-cache-linux-x64-*` | Flutter 3.44.1, Dart 3.12.1, PowerShell, distribuição/caches Gradle e cache Pub amplo | Base estável do GoAnime-Mobile |
| `goanime-lock-delta-linux-x64-*` | Versões hosted exatas do `pubspec.lock` privado, sem URLs ou entradas privadas | `flutter pub get --offline --enforce-lockfile` |
| `goanime-gradle-delta-linux-x64-*` | Coordenadas Maven pontuais, init script e instalador idempotente | Completar o grafo Gradle sem refabricar o bundle grande |
| `zapzap-gradle-cache-linux-x64-*` | Gradle 8.9 e caches de AGP 8.7.3, Kotlin/Compose 2.0.21 e dependências Android | testes, lint e `assembleDebug` do ZapZap |

Todos os artifacts usam retenção de **1 dia** para minimizar armazenamento.

Pacotes grandes são divididos em partes de **400 MiB**, pois o conector rejeita artifacts individuais acima de 512 MiB. Baixe o manifest e todas as partes, extraia os ZIPs na mesma pasta e valide antes de executar:

```bash
sha256sum -c SHA256SUMS.parts
cat <prefixo>.part-* > <arquivo>.tar.zst
sha256sum <arquivo>.tar.zst
zstd -t <arquivo>.tar.zst
```

`PARTS.txt` informa o nome e o SHA-256 do archive remontado. Artifacts antigos com paths absolutos nos checksums devem ser descartados e regenerados.

## GoAnime-Mobile

Este repositório atende `Semogtw/goanime-mobile`, o **GoAnime-Mobile**, não o projeto GoAnime original.

### Ordem de restauração

```bash
tar --zstd -xf android-base-linux-x64.tar.zst
tar --zstd -xf goanime-flutter-cache-linux-x64.tar.zst
tar --zstd -xf goanime-lock-delta-linux-x64.tar.zst
tar --zstd -xf goanime-gradle-delta-linux-x64.tar.zst

bash ./goanime-lock-delta/apply.sh ./goanime-toolchain
bash ./goanime-gradle-delta/apply.sh \
  ./goanime-gradle-delta \
  ./goanime-toolchain/gradle-home

source ./android-base/activate.sh
source ./goanime-toolchain/activate-exact.sh
```

Os scripts modificam somente o shell atual e os diretórios extraídos. O bundle Flutter fornece `safe.directory` por variáveis de ambiente, sem alterar `~/.gitconfig`.

O instalador Gradle:

- copia o delta Maven para `offline-goanime-maven`;
- instala um init script em `GRADLE_USER_HOME/init.d`;
- respeita `RepositoriesMode.FAIL_ON_PROJECT_REPOS` dos included builds do Flutter;
- injeta repositório por projeto somente quando a política permite;
- converte automaticamente artifacts `io.flutter` já presentes em `caches/modules-2/files-2.1` para layout Maven canônico;
- é idempotente;
- falha se um artifact de mesmo nome tiver bytes divergentes.

### Gates determinísticos

No checkout privado:

```bash
lock_before="$(sha256sum pubspec.lock | cut -d' ' -f1)"

flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --concurrency=1

(
  cd packages/goanime_core
  flutter pub get --offline
  flutter test --no-pub --concurrency=1
)

lock_after="$(sha256sum pubspec.lock | cut -d' ' -f1)"
test "$lock_before" = "$lock_after"
```

O delta Pub atual cobre as 148 entradas hosted do lock observado. Quando `pubspec.lock` mudar, regenere o delta; nunca altere o lock privado para acomodar um cache antigo.

### APK debug offline

Use o flag Gradle real `--offline`. Definir apenas `-Dorg.gradle.offline=true` não substitui esse flag.

```bash
export GRADLE_OPTS='-Dorg.gradle.jvmargs=-Xmx3328m -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8 -Dkotlin.compiler.execution.strategy=in-process -Dkotlin.daemon.enabled=false'

./android/gradlew \
  --offline \
  --no-daemon \
  --max-workers=1 \
  assembleDebug
```

O limite de memória foi escolhido a partir de execução real:

- 2 GiB não bastaram para o `JetifyTransform` do JAR ARM64 do engine;
- daemons com limite de 8 GiB causaram pressão de memória e reinicializações;
- 3328 MiB, um worker e Kotlin no processo concluíram o build de forma estável.

### Evidência observada em 2026-08-02

Source privado de base:

```text
dea5a81c6afc66a401bc0d2208133768bc11ce32
```

O runtime local foi reconciliado com os 11 arquivos de formatação publicados posteriormente na `main`; os demais commits observados no intervalo alteravam workflows Jikan.

Resultados:

- Flutter 3.44.1 / Dart 3.12.1;
- `flutter pub get --offline --enforce-lockfile`: passou;
- SHA-256 do lock antes/depois: `d0b0b0fcc4dbedc296fa5bdb1e514d8e357d92ee1dc4068a5c6e17a21eb6786e`;
- analyzer: zero issues;
- Gradle: `BUILD SUCCESSFUL`, 506 tasks;
- APK debug: 224.540.372 bytes;
- APK SHA-256: `ae9ba305d5a2fcc830efcabad9b0b52b711142dfe80a39f0ed84559debae4031`;
- ZIP íntegro e assinatura Android debug v2 válida;
- `compileSdk`/`targetSdk` 36, `minSdk` 24;
- nenhum padrão de download encontrado no log;
- endpoints Pub e Flutter apontados para loopback inválido durante o build.

Runs públicos relacionados:

| Prova | Run | Commit |
| --- | --- | --- |
| Delta Pub exato | `30720581099` | `1b0a2800a8f75e9f25702a99e11a1623cf5caa67` |
| Base Android com SDK 33 | `30723103034` | `7052c693eba61f55620994412db4e6974d713b53` |
| Delta Maven com política condicional | `30727071708` | `349eddb66390aa79675865f7556a1659db17314e` |
| Exposição automática de `io.flutter` | `30727767677` | `50e1174edcce1df004078569a0cca42983cf810c` |

Detalhes adicionais: `docs/goanime-exact-offline-build.md`.

### Escopo e limitações

A prova cobre análise, testes e APK **debug** offline. Ela não comprova:

- release assinada;
- Android SAF em dispositivo real;
- playback HLS Android/Windows em ambiente alvo;
- identidade final do pacote — o APK observado ainda usa `com.example.goanime_mobile`;
- compatibilidade automática depois de atualizar Flutter, AGP, Kotlin, SDK ou lockfile.

Avisos de futura migração para Built-in Kotlin não bloquearam a versão atual.

### Quando regenerar

- **base Android:** SDK, build-tools, NDK, CMake ou JDK mudaram;
- **bundle Flutter:** Flutter, wrapper Gradle, AGP, Kotlin, media_kit ou o conjunto amplo de caches mudou;
- **delta Pub:** `pubspec.lock` mudou;
- **delta Gradle:** o build offline apontou uma coordenada Maven pública realmente ausente.

Prefira deltas pequenos antes de reconstruir bundles de vários gigabytes. Não execute Actions apenas para repetir uma prova sem alteração de entrada.

## ZapZap

A fixture pública replica o grafo documentado na branch ativa do ZapZap: Gradle 8.9, AGP 8.7.3, Kotlin/Compose 2.0.21, JDK 17 e SDK Android.

```bash
tar --zstd -xf android-base-linux-x64.tar.zst
tar --zstd -xf zapzap-gradle-cache-linux-x64.tar.zst

source ./android-base/activate.sh
source ./zapzap-toolchain/activate.sh

bash ./tools/checks/run_pure_tests.sh
bash ./tools/checks/audit_sources.sh
bash ./tools/checks/verify_android_baseline.sh

./gradlew --offline testDebugUnitTest
./gradlew --offline lintDebug
./gradlew --offline :app:assembleDebug
```

## Source bundles privados cifrados

O workflow `Build encrypted private source bundle` exporta apenas os repositórios privados fixos:

| Projeto | Repositório |
| --- | --- |
| `goanime` | `Semogtw/goanime-mobile` |
| `zapzap` | `Semogtw/Zapzap` |

Ele não aceita nome arbitrário de repositório.

### Modos

- `full` — branches, tags e histórico alcançável pelo checkout completo;
- `ref` — branch, tag ou SHA exato em Git bundle reduzido;
- `snapshot` — somente arquivos rastreados de um commit, sem `.git`.

O export não inclui Git LFS, submódulos, arquivos não rastreados, stashes ou commits nunca enviados ao remoto.

### PAT privado

Use um fine-grained personal access token com:

- owner `Semogtw`;
- acesso somente a `goanime-mobile` e `Zapzap`;
- `Contents: Read-only`;
- expiração definida;
- nenhuma permissão de escrita.

Secret esperado:

```text
Settings → Secrets and variables → Actions
PRIVATE_REPOSITORIES_TOKEN
```

Os checkouts usam `fetch-depth: 0`, `persist-credentials: false`, `lfs: false` e `submodules: false`.

### Criptografia

A chave pública está em:

```text
keys/source-bundles-public.asc
```

Fingerprint esperado:

```text
2DE29DC31427CF0A911AB96175679291435059B0
```

A chave privada correspondente deve permanecer fora do GitHub. O workflow verifica o fingerprint, cria o pacote, cifra, remove checkout e arquivos em claro e somente então publica artifacts.

Perder a chave privada torna exports antigos irrecuperáveis. Expor a chave privada permite descriptografar qualquer artifact ainda válido produzido para o fingerprint.

### Gatilho pelo navegador

```text
Actions → Build encrypted private source bundle → Run workflow
```

Escolha projeto, modo e ref. Ref vazia usa o checkout padrão.

### Gatilho pelo conector

Como o conector não expõe `workflow_dispatch`, o fluxo usa:

1. branch permanente `build/source-bundles`;
2. alteração de `triggers/private-source-bundle.json`;
3. workflow sem secrets `Request private source bundle`;
4. workflow privilegiado da `main`, acionado por `workflow_run` somente após request válido.

Exemplo:

```json
{
  "project": "goanime",
  "mode": "ref",
  "ref": "main"
}
```

O job privilegiado aceita somente requests bem-sucedidos da branch fixa e atribuídos ao proprietário. Código alterado na branch pública de request não substitui o workflow privilegiado da `main`.

### Artifacts e remontagem

Cada execução publica por um dia:

```text
private-source-<project>-<mode>-manifest
private-source-<project>-<mode>-part-000
private-source-<project>-<mode>-part-001
...
```

O ciphertext usa partes de 400 MiB, com limite de 16 partes. O manifest público contém apenas dados de transporte, fingerprint e hashes; repositório, commit e refs permanecem dentro do pacote cifrado.

```bash
bash scripts/assemble-source-bundle.sh \
  ./downloads \
  ./private-source.gpg
```

O script exige todas as partes, valida hashes individuais, remonta em ordem e confirma o SHA-256 final.

### Descriptografia local

Use keyring temporário:

```bash
export GNUPGHOME="$(mktemp -d)"
chmod 700 "$GNUPGHOME"
gpg --import /caminho/seguro/offline-toolchains-source-bundles-private.asc

gpg --output private-source-package.tar.zst \
  --decrypt private-source.gpg

mkdir private-source-package
tar --zstd -xf private-source-package.tar.zst \
  -C private-source-package
```

O pacote contém `PRIVATE-MANIFEST.json`, `REFS.txt` e `repository.bundle` ou `snapshot.tar.zst`.

### Restaurar Git bundle

```bash
git bundle verify private-source-package/repository.bundle
mkdir checkout
git init checkout

git -C checkout fetch \
  ../private-source-package/repository.bundle \
  '+refs/heads/*:refs/remotes/origin/*' \
  '+refs/tags/*:refs/tags/*'
```

No modo `full`:

```bash
git -C checkout switch -c main --track origin/main
```

No modo `ref`, a head exportada aparece como `origin/offline-export`.

### Restaurar snapshot

```bash
mkdir checkout
tar --zstd -xf private-source-package/snapshot.tar.zst \
  -C checkout --strip-components=1
```

### Rotação de chave

1. gere nova chave OpenPGP de criptografia;
2. substitua `keys/source-bundles-public.asc`;
3. atualize fingerprint nos workflows, scripts e documentação;
4. execute `bash scripts/validate-private-source-workflows.sh`;
5. preserve a chave privada anterior até todos os artifacts antigos expirarem.

Nunca versione uma chave privada OpenPGP.

## Validação e segurança

Antes de alterar source bundles:

```bash
bash scripts/validate-private-source-workflows.sh
```

Regras permanentes:

- trate artifacts como executáveis e use somente runs de commits confiáveis;
- valide digest dos ZIPs, `SHA256SUMS.parts`, SHA global e Zstandard;
- workflows públicos de toolchain não precisam do PAT privado;
- o PAT de source bundle permanece read-only e limitado aos dois repositórios fixos;
- nunca publique chave privada, keystores, APKs, `local.properties`, `google-services.json`, Firebase, TURN ou signing;
- não execute conteúdo da branch pública de request no job que recebe o PAT;
- não confunda `queued`/`in_progress` com sucesso.
