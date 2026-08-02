# GoAnime-Mobile: build Android exato e offline

Este documento descreve a composição comprovada para analisar, testar e gerar o APK debug do repositório privado `Semogtw/goanime-mobile` fora do GitHub Actions, sem alterar o lock Pub e sem resolver dependências pela rede durante o build.

## Componentes

A cadeia usa quatro pacotes independentes:

| Pacote | Responsabilidade |
| --- | --- |
| `android-base-linux-x64-*` | JDK 17, Android SDK 33/35/36, build-tools, NDK, CMake e platform-tools |
| `goanime-flutter-cache-linux-x64-*` | Flutter 3.44.1, Dart 3.12.1, PowerShell, distribuição Gradle e caches amplos |
| `goanime-lock-delta-linux-x64-*` | As 148 versões hosted exatas do `pubspec.lock` privado |
| `goanime-gradle-delta-linux-x64-*` | Coordenadas Maven pontuais e um repositório local compatível com as políticas Gradle do app e dos included builds do Flutter |

Os pacotes grandes permanecem estáveis. Mudanças pequenas no lock ou no grafo Maven devem gerar deltas pequenos, não uma reconstrução do bundle inteiro.

## Aplicação

Depois de verificar `SHA256SUMS.parts`, o SHA global e o Zstandard de cada archive:

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

O instalador Gradle também percorre os artifacts `io.flutter` já existentes em `caches/modules-2/files-2.1` e os expõe em layout Maven canônico. A operação é idempotente e falha diante de arquivos de mesmo nome com hashes diferentes.

## Gates de Dart e Flutter

No checkout privado:

```bash
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
(
  cd packages/goanime_core
  flutter pub get --offline
  flutter test --no-pub --concurrency=1
)
```

Registre o SHA-256 do `pubspec.lock` antes e depois. Um lock modificado invalida a prova determinística.

## APK debug

O build comprovado usou o Gradle diretamente para garantir o flag offline real:

```bash
export GRADLE_OPTS='-Dorg.gradle.jvmargs=-Xmx3328m -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8 -Dkotlin.compiler.execution.strategy=in-process -Dkotlin.daemon.enabled=false'

./android/gradlew \
  --offline \
  --no-daemon \
  --max-workers=1 \
  assembleDebug
```

Motivos para esses limites:

- 2 GiB não foram suficientes para o `JetifyTransform` do JAR ARM64 do engine;
- configurações antigas que permitiam daemons de 8 GiB causaram pressão de memória e reinicializações do ambiente;
- 3328 MiB, um worker e compilador Kotlin no processo concluíram o build de forma estável.

## Evidência de 2026-08-02

- source privado de base: `dea5a81c6afc66a401bc0d2208133768bc11ce32`;
- runtime reconciliado com os 11 arquivos de formatação publicados posteriormente na `main`;
- Flutter 3.44.1 / Dart 3.12.1;
- `flutter pub get --offline --enforce-lockfile`: passou;
- lock SHA-256: `d0b0b0fcc4dbedc296fa5bdb1e514d8e357d92ee1dc4068a5c6e17a21eb6786e`;
- analyzer: zero issues;
- Gradle: `BUILD SUCCESSFUL`, 506 tasks;
- APK: 224.540.372 bytes;
- APK SHA-256: `ae9ba305d5a2fcc830efcabad9b0b52b711142dfe80a39f0ed84559debae4031`;
- ZIP do APK íntegro;
- assinatura debug Android v2 válida;
- nenhum padrão de download encontrado no log;
- endpoints Pub e Flutter apontados para loopback inválido durante o build.

Runs públicos relacionados:

- delta Pub exato: `30720581099`;
- base Android com SDK 33: `30723103034`;
- delta Maven com política condicional: `30727071708`;
- instalador com exposição automática de `io.flutter`: `30727767677`.

## Escopo da prova

A evidência comprova análise, testes e APK **debug** offline para o runtime privado reconciliado. Ela não comprova:

- release assinada;
- comportamento Android SAF em dispositivo real;
- playback HLS Android/Windows em ambiente alvo;
- identidade final do pacote, que ainda aparece como `com.example.goanime_mobile`;
- ausência de futuras mudanças necessárias após atualização de Flutter, AGP, Kotlin, SDK ou lockfile.

Regere somente o componente cuja entrada mudou e repita o gate correspondente.
