# Registro de perfis

Os arquivos em [`profiles/`](../profiles/) são a fonte legível por máquina para capacidades, dependências, lock inputs, doctor checks e ordem de ativação.

## Perfis concretos

| Perfil | Projeto | Conteúdo | Requer |
| --- | --- | --- | --- |
| `android-base` | compartilhado | JDK 17, SDK 35/36, build-tools 35/36, platform-tools, CMake e NDK 27/28 | — |
| `jdk21` | compartilhado | Temurin JDK 21 portátil | — |
| `goanime-analysis` | GoAnime | Flutter 3.44.1, Dart, Pub cache exato e PowerShell | — |
| `goanime-android` | GoAnime | cache Gradle/AGP/Kotlin exato para build Android | `android-base`, `goanime-analysis` |
| `zapzap-pure` | ZapZap | cache Gradle/JVM exato para testes dos módulos puros | `jdk21` |
| `zapzap-android` | ZapZap | cache Android/Compose/Gradle exato | `android-base`, `jdk21`, `zapzap-pure` |

Os builders públicos também podem produzir `goanime-analysis`, `goanime-android`, `zapzap-pure` e `zapzap-android` em modo `synthetic`. Os nomes são iguais; o manifesto distingue o modo e o lock fingerprint.

## Perfis agregados

| Perfil | Expansão em ordem |
| --- | --- |
| `goanime-full` | `android-base` → `goanime-analysis` → `goanime-android` |
| `zapzap-full` | `android-base` → `jdk21` → `zapzap-pure` → `zapzap-android` |

Agregados não geram um mega-archive. O restaurador expande a lista e baixa/extrai apenas os pacotes ausentes.

## Escolha prática

Use `goanime-analysis` para:

- `flutter pub get --offline --enforce-lockfile`;
- analyzer;
- testes Dart/Flutter;
- health checks PowerShell.

Use `goanime-full` quando a mudança também exigir build Android.

Use `zapzap-pure` para módulos Kotlin/JVM e gates que não exigem Android packaging. Use `zapzap-full` para lint, testes do app e `assembleDebug`.

## Pedido exato pelo conector

A branch permanente é:

```text
Repository: Semogtw/Offline-Toolchains
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

Perfis aceitos:

```text
goanime-analysis
goanime-android
goanime-full
zapzap-pure
zapzap-android
zapzap-full
```

O workflow sem secrets valida o pedido. O builder privilegiado carregado da `main` expande agregados e mapeia internamente somente:

```text
goanime → Semogtw/goanime-mobile
zapzap  → Semogtw/Zapzap
```

Não existe campo para repository, token, branch privada ou comando arbitrário.

## Lock inputs

### GoAnime

O fingerprint considera, conforme o perfil:

- `pubspec.yaml` e `pubspec.lock`;
- manifests/locks em `packages/*`;
- Gradle wrapper;
- settings/build files Android que fixam AGP, Kotlin e plugins.

O builder exato executa primeiro a resolução online e depois:

```bash
flutter pub get --offline --enforce-lockfile
```

O perfil Android também repete o build Gradle em modo offline.

### ZapZap

O fingerprint considera:

- Gradle wrapper;
- settings e build scripts;
- version catalogs;
- dependency locks;
- `Cargo.toml`/`Cargo.lock` quando o perfil inclui dependências nativas.

O builder usa JDK 21 e repete os tasks selecionados com:

```bash
./gradlew --no-daemon --offline ...
```

Symlinks nos lock inputs são rejeitados para impedir leitura fora do checkout.

## Extensão do registro

Um novo perfil deve declarar:

- `name`, `kind`, `project`;
- `platform: linux` e `architecture: x86_64`;
- `activation_order`;
- `requires` sem ciclos;
- `packages` para perfis concretos;
- `lock_mode` e `lock_inputs`;
- checks objetivos do doctor.

Execute:

```bash
python3 -m unittest tests.test_profile_registry -v
python3 scripts/validate-toolchain-request.py \
  triggers/toolchain-build.json --profiles profiles
```

A allowlist de repositórios privados não deve ser ampliada automaticamente ao adicionar perfis.
