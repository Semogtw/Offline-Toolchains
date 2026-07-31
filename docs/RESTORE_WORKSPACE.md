# Restaurar workspace em um comando

Este fluxo é para sessões Linux x86_64 que acessam o GitHub somente pelo conector. Ele combina um source bundle privado cifrado com os perfis de toolchain necessários e produz um checkout Git verificável, um script local de ativação e um relatório JSON.

## Pré-requisitos locais

O ambiente precisa ter:

```text
bash
python3
git
gpg
tar
zstd
unzip
sha256sum
```

Também é necessário anexar à sessão, fora do GitHub:

```text
offline-toolchains-source-bundles-private.asc
```

Fingerprint esperado:

```text
2DE29DC31427CF0A911AB96175679291435059B0
```

A chave privada nunca deve ser enviada a Actions, secrets, artifacts, issues, PRs ou commits.

## 1. Gerar o source bundle

Atualize na branch `build/source-bundles`:

```text
triggers/private-source-bundle.json
```

GoAnime:

```json
{
  "project": "goanime",
  "mode": "full",
  "ref": ""
}
```

ZapZap:

```json
{
  "project": "zapzap",
  "mode": "full",
  "ref": ""
}
```

Os resultados aparecem no issue #4 com IDs de manifesto e partes.

## 2. Gerar a toolchain exata

Atualize na branch `build/toolchains`:

```text
triggers/toolchain-build.json
```

Exemplo:

```json
{
  "profile": "zapzap-full",
  "force_rebuild": false
}
```

Os resultados e IDs aparecem no issue #8. Um pedido idêntico reutiliza o conjunto vivo quando perfil, lock, builder, plataforma e arquitetura coincidem.

## 3. Baixar pelo conector

Baixe para uma única pasta de staging:

- o manifesto e todas as partes `private-source-<project>-full-*`;
- o manifesto e partes de cada perfil concreto expandido;
- a chave privada fica fora dessa pasta.

Não renomeie arquivos internos dos ZIPs. Os nomes dos próprios ZIPs podem variar.

## 4. Restaurar

GoAnime completo:

```bash
bash scripts/restore-workspace.sh \
  --project goanime \
  --downloads /mnt/data/goanime-downloads \
  --private-key /mnt/data/offline-toolchains-source-bundles-private.asc \
  --destination /mnt/data/goanime-mobile-offline \
  --profile goanime-full \
  --require-exact-lock \
  --report /mnt/data/goanime-restore-report.json
```

ZapZap completo:

```bash
bash scripts/restore-workspace.sh \
  --project zapzap \
  --downloads /mnt/data/zapzap-downloads \
  --private-key /mnt/data/offline-toolchains-source-bundles-private.asc \
  --destination /mnt/data/zapzap-offline \
  --profile zapzap-full \
  --require-exact-lock \
  --report /mnt/data/zapzap-restore-report.json
```

Uma branch pode ser escolhida explicitamente:

```text
--branch completion/essential-features
```

Sem `--branch`, o restaurador usa a default branch informada no pacote cifrado quando possível.

## O que o restaurador executa

1. valida ferramentas locais e argumentos;
2. extrai ZIPs sem permitir path traversal;
3. valida schemas, IDs, plataforma e arquitetura;
4. verifica checksums de partes e archives;
5. remonta o ciphertext do source bundle;
6. cria um `GNUPGHOME` temporário e valida o fingerprint da chave;
7. descriptografa o pacote localmente;
8. valida e restaura o Git bundle;
9. configura o remote informativo;
10. expande o perfil agregado;
11. compara fingerprints `private-exact` com os locks do checkout;
12. extrai os pacotes de toolchain;
13. executa doctors;
14. gera `activate-workspace.sh` e o relatório;
15. executa `git fsck --full --no-dangling`;
16. apaga keyring, plaintext, ciphertext, ZIPs e staging temporário por padrão.

Ele nunca executa `source` em scripts baixados durante a validação. Primeiro valida o contrato e paths; depois escreve um ativador local que referencia somente pacotes aprovados na ordem do registro.

## Ativação e gates

Depois da restauração:

```bash
source /mnt/data/<workspace>/activate-workspace.sh
```

GoAnime:

```bash
cd /mnt/data/goanime-mobile-offline
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

ZapZap:

```bash
cd /mnt/data/zapzap-offline
java -version
./gradlew --version
./gradlew --offline \
  :core:model:test \
  :core:data:test \
  :core:network:test \
  :app:testDebugUnitTest \
  :app:lintDebug \
  :app:assembleDebug
```

O Java do ZapZap deve indicar major 21. O target de bytecode Android permanece 17.

## Doctor

Para verificar um pacote isolado:

```bash
bash scripts/doctor.sh \
  --manifest /caminho/artifact-set.json \
  --root /caminho/pacote \
  --json
```

Estados:

- `ready` — checks obrigatórios passaram;
- `partial` — somente checks opcionais falharam;
- `missing` ou `incompatible` — não use o pacote.

## Opções de retenção local

Use somente para diagnóstico:

```text
--keep-temporary
--keep-downloads
```

`--keep-temporary` preserva plaintext/ciphertext e deve ser evitado em sessões normais. O restaurador nunca apaga a chave privada fornecida pelo usuário.

## Falhas seguras

A restauração para antes de usar o pacote quando encontra:

- chave errada;
- checksum divergente;
- parte ausente ou de outro run;
- archive com traversal;
- schema incompatível;
- arquitetura diferente;
- profile dependency ausente;
- lock fingerprint exato diferente do checkout.

O relatório de erro não inclui PAT, chave privada, conteúdo de lockfile ou código-fonte.
