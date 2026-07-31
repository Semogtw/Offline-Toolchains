# Offline Toolchains

Repositório público para fabricar ambientes Linux x64 reutilizáveis em sessões que conseguem acessar o GitHub somente pelo conector, mas não conseguem baixar SDKs, dependências ou um checkout Git diretamente.

Há dois fluxos independentes:

1. **Toolchains públicas** — SDKs e caches de dependências públicas, sem acesso aos repositórios privados.
2. **Source bundles privados** — exports Git cifrados do GoAnime Mobile e ZapZap, usando um PAT somente leitura e criptografia antes de qualquer upload.

## Artifacts de toolchains

| Prefixo dos artifacts | Conteúdo | Uso |
| --- | --- | --- |
| `android-base-linux-x64-*` | Temurin JDK 17, Android SDK 35/36, build-tools, platform-tools, NDK e CMake | Base comum para GoAnime Mobile e ZapZap |
| `goanime-flutter-cache-linux-x64-*` | Flutter 3.44.1, Dart, Pub cache, Gradle cache Android e PowerShell | `flutter pub get --offline`, análise, testes, health checks e build Android do GoAnime |
| `zapzap-gradle-cache-linux-x64-*` | Gradle 8.9 e caches de AGP 8.7.3, Kotlin/Compose 2.0.21 e dependências Android | testes, lint e `assembleDebug` do ZapZap |

Todos os artifacts usam retenção de **1 dia** para minimizar armazenamento. Gere-os novamente quando uma sessão precisar deles.

Cada pacote grande é dividido em artifacts independentes de **400 MiB**, porque o conector rejeita um artifact acima de 512 MiB. Baixe o artifact `*-manifest` e todos os `*-part-NN`, extraia os ZIPs na mesma pasta e remonte:

```bash
sha256sum -c SHA256SUMS.parts
cat <prefixo>.part-* > <arquivo>.tar.zst
```

`PARTS.txt` contém os nomes exatos e o SHA-256 do arquivo remontado. Artifacts gerados antes de 2026-07-31 podem conter paths absolutos no arquivo de checksums; gere um run novo em vez de reutilizá-los.

## Ordem de uso

Extraia primeiro a base Android e depois o pacote específico do projeto:

```bash
tar --zstd -xf android-base-linux-x64.tar.zst
source ./android-base/activate.sh

tar --zstd -xf goanime-flutter-cache-linux-x64.tar.zst
source ./goanime-toolchain/activate.sh
```

Para ZapZap:

```bash
tar --zstd -xf android-base-linux-x64.tar.zst
source ./android-base/activate.sh

tar --zstd -xf zapzap-gradle-cache-linux-x64.tar.zst
source ./zapzap-toolchain/activate.sh
```

Os scripts somente adicionam variáveis ao shell atual. O bundle GoAnime também fornece `safe.directory` ao Git por variáveis de ambiente para que o Flutter continue portátil quando o arquivo for extraído por um usuário diferente do runner. Ele não altera `~/.gitconfig`.

## GoAnime Mobile

A fixture pública replica apenas dependências públicas declaradas pelo projeto. Ela não contém assets, código, configuração Firebase, Shorebird privada, signing ou arquivos locais.

No checkout privado:

```bash
flutter pub get --offline
flutter analyze --no-pub
flutter test --no-pub
pwsh -NoLogo -NoProfile -File ./tools/validate_project_health.ps1
flutter build apk --debug --no-pub
```

O cache deve ser regenerado quando Flutter, `pubspec.yaml`, `pubspec.lock`, AGP, Kotlin ou o wrapper Gradle do GoAnime mudar.

### Limite atual do lockfile

A fixture atual hidrata um grafo compatível a partir das constraints públicas, mas ainda não espelha integralmente as versões do `pubspec.lock` privado. Isso é suficiente para disponibilizar Flutter, Dart, PowerShell e um cache amplo, mas não prova que `flutter pub get --offline` preservará exatamente o lock real.

Antes de tratar esse cache como gate determinístico, mantenha no repositório público um lock sanitizado ou uma lista completa `pacote=versão` contendo apenas entradas `source: hosted` do lock real, e valide com:

```bash
flutter pub get --offline --enforce-lockfile
```

Nunca copie URLs privadas, tokens ou dependências Git privadas. O lock atual do GoAnime contém versões públicas que já podem divergir da resolução mais recente da fixture; por isso, um run verde da fixture não substitui a validação contra o checkout real.

## ZapZap

A fixture pública replica o grafo de ferramentas documentado na branch ativa `development/android-build-recovery`: Gradle 8.9, AGP 8.7.3, Kotlin/Compose 2.0.21, JDK 17 e SDK 35.

No checkout privado:

```bash
bash ./tools/checks/run_pure_tests.sh
bash ./tools/checks/audit_sources.sh
bash ./tools/checks/verify_android_baseline.sh

./gradlew --offline testDebugUnitTest
./gradlew --offline lintDebug
./gradlew --offline :app:assembleDebug
```

## Verificação prática das toolchains

Em 2026-07-31, um run descoberto pelo PR persistente foi acessado exclusivamente pelo conector. O manifesto e as 11 partes do bundle GoAnime foram baixados, os hashes individuais e o SHA-256 final foram confirmados, e o arquivo remontado executou fora do runner:

- Flutter 3.44.1;
- Dart 3.12.1;
- PowerShell 7.6.3.

Essa prova confirmou o transporte e a portabilidade das ferramentas. Ela também encontrou e motivou as correções de checksums relativos e `safe.directory`. O build Android completo ainda exige combinar esse bundle com `android-base-linux-x64-*` e validar o checkout real.

## Source bundles privados cifrados

O workflow `Build encrypted private source bundle` exporta somente os dois repositórios privados fixos:

| Projeto | Repositório privado |
| --- | --- |
| `goanime` | `Semogtw/goanime-mobile` |
| `zapzap` | `Semogtw/Zapzap` |

Ele nunca aceita um nome de repositório arbitrário.

### Modos de exportação

- `full` — todas as branches e tags obtidas pelo checkout completo, junto do histórico alcançável;
- `ref` — uma branch, tag ou SHA exatos em um Git bundle reduzido;
- `snapshot` — somente arquivos rastreados de um commit, sem `.git` e sem histórico.

O export não inclui objetos Git LFS, repositórios de submódulos, arquivos não rastreados, stashes nem commits que nunca receberam push.

### Secret obrigatório

Crie um fine-grained personal access token com:

- proprietário `Semogtw`;
- acesso somente a `goanime-mobile` e `Zapzap`;
- permissão de repositório `Contents: Read-only`;
- prazo de expiração definido;
- nenhuma permissão de escrita.

Salve-o em:

```text
Settings → Secrets and variables → Actions → New repository secret
Name: PRIVATE_REPOSITORIES_TOKEN
```

Os checkouts privados usam `fetch-depth: 0`, `persist-credentials: false`, `lfs: false` e `submodules: false`. O token não entra no bundle, manifesto ou artifact.

### Criptografia

A chave pública OpenPGP está em:

```text
keys/source-bundles-public.asc
```

Fingerprint esperado:

```text
2DE29DC31427CF0A911AB96175679291435059B0
```

A chave privada correspondente deve permanecer fora do GitHub. O workflow verifica o fingerprint, cria o bundle, cifra o pacote, remove o checkout e os arquivos em claro e somente então publica os artifacts.

Perder a chave privada torna os exports irrecuperáveis. Expor a chave privada permite descriptografar qualquer artifact ainda disponível produzido para esse fingerprint.

### Gatilho pelo navegador

Abra:

```text
Actions → Build encrypted private source bundle → Run workflow
```

Escolha projeto, modo e ref. Uma ref vazia usa o checkout padrão; no modo `full`, todas as branches e tags buscadas continuam incluídas.

### Gatilho pelo conector

O conector não expõe `workflow_dispatch`. O fluxo automatizado usa duas etapas:

1. a branch permanente `build/source-bundles` altera `triggers/private-source-bundle.json`;
2. o workflow sem secrets `Request private source bundle` valida o JSON;
3. após sucesso, o workflow privilegiado versionado na `main` recebe `workflow_run` e cria o export.

Exemplo:

```json
{
  "project": "zapzap",
  "mode": "full",
  "ref": ""
}
```

O workflow privilegiado aceita somente requests bem-sucedidos da branch `build/source-bundles`, disparados por `push` e atribuídos ao proprietário. Alterações de workflow na branch de request não mudam o código privilegiado executado pela `main`.

### Artifacts produzidos

Cada execução publica por um dia:

```text
private-source-<project>-<mode>-manifest
private-source-<project>-<mode>-part-000
private-source-<project>-<mode>-part-001
...
```

O ciphertext é dividido em 400 MiB e limitado a 16 partes. O manifest público contém apenas dados de transporte, fingerprint e hashes; repositório, commit e refs ficam dentro do pacote cifrado.

### Remontagem e verificação

Deixe os ZIPs baixados em uma pasta ou extraia-os para a mesma pasta. Depois execute:

```bash
bash scripts/assemble-source-bundle.sh ./downloads ./private-source.gpg
```

O script exige todas as partes declaradas, valida os hashes individuais, remonta em ordem numérica e verifica o SHA-256 final.

### Descriptografia local

A lógica de chave privada não fica neste repositório público. Use um keyring temporário:

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

O pacote contém `PRIVATE-MANIFEST.json`, `REFS.txt` e um dos arquivos:

```text
repository.bundle
snapshot.tar.zst
```

### Restaurar um Git bundle

```bash
git bundle verify private-source-package/repository.bundle
mkdir checkout
git init checkout

git -C checkout fetch \
  ../private-source-package/repository.bundle \
  '+refs/heads/*:refs/remotes/origin/*' \
  '+refs/tags/*:refs/tags/*'

git -C checkout branch -a
```

No modo `full`, crie a branch local desejada:

```bash
git -C checkout switch -c main --track origin/main
```

Para a branch ativa do ZapZap:

```bash
git -C checkout switch \
  -c development/android-build-recovery \
  --track origin/development/android-build-recovery
```

No modo `ref`, a head exportada aparece como `origin/offline-export`.

O remote informativo pode ser restaurado após ler `PRIVATE-MANIFEST.json`:

```bash
git -C checkout remote add origin \
  https://github.com/Semogtw/Zapzap.git
```

### Restaurar um snapshot

```bash
mkdir checkout
tar --zstd -xf private-source-package/snapshot.tar.zst \
  -C checkout --strip-components=1
```

### Rotação de chave

1. gere uma nova chave OpenPGP de criptografia;
2. substitua `keys/source-bundles-public.asc`;
3. atualize o fingerprint nos workflows, scripts e documentação;
4. execute `bash scripts/validate-private-source-workflows.sh`;
5. preserve a chave privada anterior até todos os artifacts antigos expirarem.

Nunca versione uma chave privada OpenPGP.

## Validação

Antes de alterar o fluxo de source bundles:

```bash
bash scripts/validate-private-source-workflows.sh
```

Esse guard verifica schema, refs, fingerprint, ausência de chave privada/token, mappings fixos, checkout sem credencial persistida, segmentação de 400 MiB e retenção de um dia.

## Segurança

- Trate artifacts como executáveis: use somente runs de commits confiáveis.
- Verifique `SHA256SUMS.parts` e o SHA-256 final antes de extrair SDKs ou descriptografar source bundles.
- Os workflows de toolchain não precisam de PAT privado.
- O workflow de source bundle usa somente o PAT read-only limitado aos dois repositórios mapeados.
- Não publique a chave privada OpenPGP, keystores, `local.properties`, `google-services.json`, Firebase config, TURN credentials ou signing.
- Não amplie o PAT para escrita nem para outros repositórios.
- Não execute conteúdo da branch pública de request no job que recebe o PAT.
