# Handoff para o próximo agente

**Atualizado em:** 2026-08-01 22:53 BRT  
**Escopo:** `Semogtw/Offline-Toolchains`  
**Estado:** toolchain exata do GoAnime-Mobile comprovada contra o checkout privado; não refabricar bundles grandes sem mudança de entrada.

## Resultado consolidado

A cadeia pública agora consegue restaurar e validar, fora do runner, o runtime privado atual do **GoAnime-Mobile** sem alterar o `pubspec.lock` e sem acessar repositórios de dependências durante o build:

- Flutter 3.44.1 / Dart 3.12.1;
- PowerShell 7.6.3;
- JDK 17.0.19;
- Android SDK 33, 35 e 36;
- build-tools 34, 35 e 36;
- NDK 27.0.12077973 e 28.2.13676358;
- cache Pub exato para as 148 entradas hosted do lock privado;
- delta Maven incremental para lacunas Gradle exatas;
- exposição automática dos artifacts `io.flutter` já presentes no cache Gradle como repositório Maven local;
- preload offline do `media_kit` já incorporado ao bundle base.

## Provas observadas

### Cache Pub exato

Run `30720581099`, commit `1b0a2800a8f75e9f25702a99e11a1623cf5caa67`:

- artifact manifest `8824726357`;
- artifact part 00 `8824726620`;
- 148 versões hosted;
- aplicação sobre o bundle base concluída;
- `flutter pub get --offline --enforce-lockfile` passou no checkout privado;
- SHA-256 de `pubspec.lock` permaneceu `d0b0b0fcc4dbedc296fa5bdb1e514d8e357d92ee1dc4068a5c6e17a21eb6786e`.

A antiga limitação de lockfile não está mais aberta para o estado atual do GoAnime. Regere o delta quando o lock privado mudar.

### Base Android corrigida

Run `30723103034`, commit `7052c693eba61f55620994412db4e6974d713b53`:

- manifest `8825488903`;
- parts `8825489746`, `8825490584`, `8825491452`, `8825492323` e `8825492866`;
- SDK 33/35/36 validado;
- proxies definidos como string vazia são removidos pelo `activate.sh`;
- archive remontado e verificado localmente.

SDK 33 é necessário por plugins Android do checkout atual. Não remova plataformas antigas apenas porque `compileSdk` é mais novo.

### Delta Maven Gradle

O delta incremental resolve coordenadas públicas ausentes sem reconstruir o bundle Flutter de vários gigabytes.

Run final `30727767677`, commit `50e1174edcce1df004078569a0cca42983cf810c`:

- manifest `8826954503`;
- part 00 `8826954622`;
- testes de manifesto e instalador passaram;
- resolução em `GRADLE_USER_HOME` vazio com `--offline` passou;
- o instalador é idempotente;
- o init script respeita `RepositoriesMode.FAIL_ON_PROJECT_REPOS` dos included builds do Flutter e injeta por projeto somente quando a política permite;
- o instalador converte automaticamente o cache `caches/modules-2/files-2.1/io.flutter` em layout Maven canônico dentro de `offline-goanime-maven`, verificando conflitos por SHA-256.

A coordenada atualmente declarada é `org.jetbrains.kotlin:kotlin-stdlib-common:2.2.0`. Esse módulo é POM-only e resolve para `kotlin-stdlib:2.2.0`; não exija um JAR inexistente de `kotlin-stdlib-common`.

### APK privado real

Source bundle run `30722535097` foi verificado e descriptografado em `GNUPGHOME` temporário. O manifesto privado resolveu para:

`dea5a81c6afc66a401bc0d2208133768bc11ce32`

Sobre esse source foram reaplicados exatamente os 11 arquivos de runtime formatados e já publicados posteriormente na `main`. A comparação com a `main` observada mostrou que os demais commits eram apenas workflows Jikan.

Build executado com Gradle real:

```bash
./gradlew --offline --no-daemon --max-workers=1 assembleDebug
```

Configuração relevante:

- heap Gradle de 3328 MiB;
- compilador Kotlin no processo;
- endpoints Pub/Flutter apontados para loopback inválido;
- variáveis de proxy removidas;
- nenhum padrão de download encontrado no log.

Resultado:

- `BUILD SUCCESSFUL`;
- 506 tasks, 243 executadas e 263 up-to-date;
- APK debug com 224.540.372 bytes;
- SHA-256 `ae9ba305d5a2fcc830efcabad9b0b52b711142dfe80a39f0ed84559debae4031`;
- ZIP íntegro;
- assinatura Android debug v2 válida;
- `compileSdk`/`targetSdk` 36 e `minSdk` 24.

Isso prova o APK debug offline do checkout privado equivalente ao runtime da `main`. Não é prova de release assinada nem substitui testes em dispositivo real.

## Ordem canônica de uso

1. Extraia e ative `android-base-linux-x64-*`.
2. Extraia e ative `goanime-flutter-cache-linux-x64-*`.
3. Aplique `goanime-lock-delta-linux-x64-*` ao bundle Flutter.
4. Aplique `goanime-gradle-delta-linux-x64-*` ao `GRADLE_USER_HOME` do bundle.
5. No source privado:

```bash
source ./android-base/activate.sh
source ./goanime-toolchain/activate-exact.sh
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
./android/gradlew --offline --no-daemon --max-workers=1 assembleDebug
```

Use aproximadamente 3,25 GiB de heap para o Gradle. Com 2 GiB, `JetifyTransform` do JAR ARM64 do engine ficou sem heap; configurações antigas de 8 GiB por daemon causaram pressão suficiente para reinicializar o ambiente.

## Quando regenerar

- base Android: quando SDK/build-tools/NDK/JDK exigidos mudarem;
- bundle Flutter: quando Flutter, Gradle wrapper, AGP, Kotlin, media_kit ou conjunto amplo de caches mudar;
- delta Pub: sempre que `pubspec.lock` mudar;
- delta Gradle: quando o build offline apontar uma coordenada Maven pública realmente ausente.

Não use Actions para repetir uma prova já coberta sem alteração de entrada. Prefira os deltas pequenos antes de reconstruir bundles grandes.

## Limites ainda válidos

- APK debug não é release assinada;
- Android SAF real e playback HLS em Android/Windows ainda exigem ambiente alvo real;
- o `applicationId` observado continua `com.example.goanime_mobile` e deve ser tratado em trabalho próprio;
- avisos de migração futura para Built-in Kotlin não bloquearam o build atual.

## Segurança

- nunca versionar ou anexar a chave privada OpenPGP;
- usar `GNUPGHOME` temporário e removê-lo após a descriptografia;
- nunca publicar source privado, patches privados, Firebase, Shorebird, signing, APKs ou `local.properties` neste repositório público;
- verificar digests dos ZIPs, `SHA256SUMS.parts` e SHA global antes de extrair;
- não ampliar o PAT privado para escrita;
- não confundir run `queued` ou `in_progress` com sucesso.
