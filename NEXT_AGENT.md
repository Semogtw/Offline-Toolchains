# Handoff para o próximo agente

**Atualizado em:** 2026-08-01 03:57 BRT  
**Escopo:** `Semogtw/Offline-Toolchains`  
**Estado:** correções registradas; não gerar novos artifacts nesta sessão.

## Regra de retomada

Não use artifacts antigos como prova de build offline do GoAnime. A retomada deve começar pela geração deliberada de uma nova base Android e de um novo bundle GoAnime a partir da `main` atual. Não altere o gatilho nem execute workflows apenas para “ver se funciona” sem antes ler este arquivo.

## O que foi comprovado

- source bundle privado do GoAnime foi baixado pelo conector, verificado, descriptografado em keyring temporário e restaurado como Git bundle completo;
- a chave privada nunca foi versionada e deve permanecer fora do GitHub;
- artifacts segmentados em 400 MiB são baixáveis pelo conector;
- Flutter 3.44.1, Dart 3.12.1 e PowerShell 7.6.3 executam fora do runner;
- checksums relativos e `safe.directory` portátil já foram corrigidos anteriormente;
- a base Android geração 5 foi remontada e verificada localmente;
- JDK 17, SDK 35/36, build-tools, CMake, NDK 27.0.12077973 e NDK 28.2.13676358 estão presentes nessa base;
- o NDK 28.2 é necessário para o build Android observado com Flutter 3.44.1.

## Erro encontrado e correção aplicada no fabricante GoAnime

`media_kit_libs_android_video 1.3.8` não usa a resolução offline normal do Gradle para seus binários nativos. O `android/build.gradle` do pacote chama `URL.openStream()` para quatro JARs da release `libmpv-android-video-build v1.1.7` durante a configuração do build.

Isso fazia `flutter build apk --debug --no-pub` tentar acessar GitHub mesmo com o cache Gradle e o SDK Android completos.

O workflow `build-goanime.yml` foi alterado para:

1. verificar a versão esperada do pacote `media_kit_libs_android_video`;
2. capturar os quatro JARs baixados no build online da fixture;
3. verificar os MD5 oficiais usados pelo próprio plugin;
4. armazenar os JARs em `GRADLE_USER_HOME/offline-media-kit/v1.1.7`;
5. instalar um init script Gradle que os copia para o `buildDir` do plugin antes da avaliação;
6. apagar o build anterior do plugin na validação;
7. executar um APK debug usando o bundle copiado;
8. falhar se o log contiver `Downloading file from:`;
9. exigir a existência de `app-debug.apk`.

A alteração foi registrada no commit `01912a7` com `[skip ci]` para não continuar o processo automaticamente. **Ainda não existe run novo comprovando essa correção.**

## Próxima execução intencional

1. Conferir que a `main` contém a correção de preload do `media_kit`.
2. Copiar/sincronizar essa revisão para a branch persistente `build/toolchains`, se ela não estiver atualizada.
3. Incrementar `triggers/build.txt` somente quando estiver pronto para consumir os artifacts no mesmo dia.
4. Acompanhar o run `Build GoAnime offline cache` até `completed/success`.
5. Conferir no job que `Validate copied bundle offline` executou um build APK, não apenas `gradle tasks`.
6. Baixar manifesto e todas as partes; verificar `SHA256SUMS.parts` e o SHA-256 final de `PARTS.txt`.
7. Inspecionar o bundle extraído:

```bash
test -d goanime-toolchain/gradle-home/offline-media-kit/v1.1.7
test -f goanime-toolchain/gradle-home/init.d/goanime-offline-media-kit.gradle
```

8. Combinar com a base Android geração 5 e executar no checkout real:

```bash
source ./android-base/activate.sh
source ./goanime-toolchain/activate.sh
flutter build apk --debug --no-pub
```

9. Tratar qualquer ocorrência de `Downloading file from:` como falha da toolchain.

## Limitação ainda aberta: lockfile

O Pub cache da fixture resolve um grafo compatível, mas não espelha todas as versões exatas do `pubspec.lock` privado. Um `flutter pub get --offline --enforce-lockfile` no checkout real já mostrou que dezenas de versões seriam substituídas.

Não modificar o lock real para acomodar o cache. A solução futura é uma lista pública sanitizada de dependências `hosted` e versões exatas, ou um lock sanitizado sem URLs privadas, dependências Git privadas ou credenciais.

## Segurança

- nunca versionar ou anexar a chave privada OpenPGP;
- usar `GNUPGHOME` temporário e removê-lo após descriptografar;
- não publicar checkout, patches privados, Firebase, Shorebird, signing ou `local.properties` neste repositório público;
- não ampliar o PAT privado para escrita;
- verificar hashes antes de extrair ou executar artifacts;
- não confundir run `queued`/`in_progress` com sucesso.
