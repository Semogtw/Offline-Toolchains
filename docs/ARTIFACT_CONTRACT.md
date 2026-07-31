# Contrato de artifacts v2

O Artifact Platform v2 usa um contrato uniforme para SDKs, caches e toolchains. Source bundles privados continuam cifrados e possuem seu fluxo próprio; este documento descreve principalmente os conjuntos públicos de toolchain.

## Unidade de distribuição

Cada pacote lógico produz:

```text
<artifact-set-id>-manifest
<artifact-set-id>-part-00
<artifact-set-id>-part-01
...
toolchain-receipt-<profile>-<run-id>
```

O `artifact-set-id` inclui perfil, prefixo do fingerprint e run ID. Isso impede misturar partes de runs diferentes e permite selecionar conjuntos antigos com segurança.

O artifact `*-manifest` contém:

- `artifact-set.json` — contrato legível por máquina;
- `SBOM.spdx.json` — inventário SPDX 2.3 das ferramentas conhecidas;
- `PARTS.txt` — resumo humano, archive hash e ordem de remontagem;
- `SHA256SUMS.parts` — checksums relativos das partes.

Cada parte descompactada tem no máximo **400 MiB**, abaixo do limite prático de 512 MiB do conector. Todos os artifacts usam retenção de **1 dia**.

## Campos obrigatórios

O schema está em [`schemas/artifact-set-v2.schema.json`](../schemas/artifact-set-v2.schema.json). Os campos essenciais são:

- `schema_version: 2`;
- `artifact_set_id`;
- `profile` e `package`;
- `platform: linux` e `architecture: x86_64`;
- `lock_mode`;
- `lock_fingerprint` e `builder_fingerprint`;
- workflow, commit confiável e run ID;
- horário de criação e expiração;
- archive, tamanho e SHA-256;
- lista ordenada de partes, nomes de artifact, tamanhos e SHA-256;
- dependências de perfil e ordem de ativação;
- caminhos relativos de `activate.sh` e `doctor.sh`;
- inventário de software.

Paths absolutos, `..`, partes duplicadas, hashes inválidos, arquiteturas incompatíveis e partes acima de 400 MiB são rejeitados.

## Modos de lock

### `private-exact`

O builder leu os arquivos permitidos do repositório privado, calculou um fingerprint determinístico, resolveu dependências e repetiu o gate em modo offline no mesmo checkout. É o único modo aceito com `--require-exact-lock`.

### `synthetic`

O builder usou uma fixture pública que replica versões e dependências relevantes. É útil para bootstrap e para disponibilizar ferramentas, mas não prova compatibilidade exata com o lock privado atual.

### `not-applicable`

Usado por pacotes independentes do projeto, como `android-base` e `jdk21`.

### `aggregate`

Existe somente no registro de perfis. Um agregado não publica archive; ele expande para pacotes concretos em ordem.

## Fingerprints

O `lock_fingerprint` é calculado com serialização length-delimited dos conteúdos permitidos. Alterar qualquer lock, catálogo, wrapper ou configuração listada pelo perfil muda o fingerprint.

O `builder_fingerprint` inclui:

- perfil e pacote;
- modo/fingerprint do lock;
- plataforma e arquitetura;
- commit da implementação confiável;
- schema do contrato.

Um conjunto somente pode ser reutilizado quando todos esses valores coincidirem e todos os artifacts esperados ainda existirem sem expiração.

## Remontagem

O caminho preferencial é o restaurador completo. Para uso isolado:

```bash
bash scripts/assemble-artifact.sh \
  ./downloads \
  ./downloads/artifact-set.json \
  ./toolchain.tar.zst
```

O assembler:

1. extrai ZIPs com validação contra path traversal;
2. encontra exatamente o conjunto declarado;
3. verifica cada parte;
4. remonta em ordem numérica;
5. verifica tamanho e SHA-256 do archive final.

Nunca concatene arquivos apenas pelo nome sem validar `artifact_set_id` e hashes.

## Reutilização e limpeza

Antes de hidratar dependências, cada builder consulta os artifacts vivos. A reutilização exige manifesto válido e conjunto completo.

Após um build novo, o reporter do issue #8 pode apagar:

- conjuntos completos mais antigos do mesmo perfil e fingerprint;
- conjuntos órfãos/incompletos com mais de seis horas.

Ele preserva:

- o run atual;
- source bundles `private-source-*`;
- perfis e fingerprints diferentes;
- qualquer grupo cuja identidade não possa ser provada.

Falha de limpeza não invalida um artifact construído; ela aparece separadamente no catálogo.

## Compatibilidade

O restaurador recusa:

- schema futuro ou diferente de `2`;
- plataforma/arquitetura incompatível;
- partes de conjuntos diferentes;
- fingerprint exato divergente do checkout restaurado;
- dependência de perfil ausente;
- archive ou parte com checksum inválido.

Um run verde do repositório público prova fabricação e transporte. Os testes do produto continuam precisando ser executados no checkout privado e SHA exatos.
