# Offline Toolchains

Repositório público para fabricar toolchains Linux x64 reutilizáveis em ambientes que conseguem acessar o GitHub somente pelo conector, mas não conseguem baixar SDKs e dependências diretamente.

Os workflows não acessam os repositórios privados e não recebem tokens, signing, credenciais ou código-fonte privado. Eles produzem somente SDKs públicos, caches de dependências públicas, scripts de ativação, manifestos e checksums.

## Artifacts

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

## Verificação prática

Em 2026-07-31, um run descoberto pelo PR persistente foi acessado exclusivamente pelo conector. O manifesto e as 11 partes do bundle GoAnime foram baixados, os hashes individuais e o SHA-256 final foram confirmados, e o arquivo remontado executou fora do runner:

- Flutter 3.44.1;
- Dart 3.12.1;
- PowerShell 7.6.3.

Essa prova confirmou o transporte e a portabilidade das ferramentas. Ela também encontrou e motivou as correções de checksums relativos e `safe.directory`. O build Android completo ainda exige combinar esse bundle com `android-base-linux-x64-*` e validar o checkout real.

## Segurança

- Trate artifacts como executáveis: use apenas runs de commits confiáveis.
- Verifique `SHA256SUMS.parts` e o SHA-256 final em `PARTS.txt` antes de extrair.
- Não adicione PAT com acesso aos repositórios privados.
- Não copie lockfiles ou manifests que contenham URLs privadas, credenciais ou dependências Git privadas.
- Não publique keystores, `local.properties`, `google-services.json`, Firebase config, TURN credentials ou signing.
- Runners públicos padrão são usados somente para fabricar dependências públicas.
