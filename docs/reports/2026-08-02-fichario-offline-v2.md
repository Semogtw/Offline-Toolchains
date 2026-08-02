# Evidência — Fichário offline workspace v2

_Data: 2 de agosto de 2026_

## Resultado publicado

- workflow: `Build Fichário offline workspace`;
- status: `success`;
- run: `30772786351`;
- commit do toolchain: `500f2c02ea219ffeb98698e49d8c878179771add`;
- source fixado: `Semogtw/FicharioVirtual@f961461cf27df2fe6e860e2ac50236ec2eb70a23`;
- artifacts: manifest, duas partes do archive e diagnóstico do build.

## Conteúdo fixado

```text
Node.js v22.16.0
pnpm 10.34.5
Deno 2.8.1
Supabase CLI 2.111.0
npm registry identity https://registry.npmjs.org/
```

O manifest schema v2 registrou:

```text
pnpm_store=offline_install_and_verification_passed
playwright=offline_browser_test_passed
deno_cache=canonical_registry_proxy_blocked_edge_checks_passed
```

## Checksums publicados

Archive:

```text
6c89dbb395ace2fc1dd3329198631beb8565d78181a99a116ec6985dc8b88a3f  fichario-offline-linux-x64.tar.zst
```

As partes possuem checksums próprios no artifact `SHA256SUMS.parts`; os valores devem sempre ser lidos do manifest do run, porque uma nova fabricação pode produzir bytes diferentes mesmo para o mesmo source.

## Validação fora do GitHub runner

Os três artifacts foram baixados pelo conector GitHub em outro ambiente e verificados na seguinte ordem:

```bash
sha256sum -c SHA256SUMS.parts
cat fichario-offline-linux-x64.part-* > fichario-offline-linux-x64.tar.zst
sha256sum -c fichario-offline-linux-x64.tar.zst.sha256
zstd -t fichario-offline-linux-x64.tar.zst
tar --zstd -xf fichario-offline-linux-x64.tar.zst
./fichario-offline/bin/doctor ./fichario-offline/workspace
```

Resultado observado:

```text
part-00: OK
part-01: OK
archive: OK
Zstandard: 1,396,572,160 bytes íntegros
Playwright 1.57.0 localizado
5 módulos Edge verificados com rede bloqueada
Fichário offline workspace doctor: PASS
```

A prova fora do runner detectou e eliminou uma dependência implícita do registry npm herdado pelo consumidor. O bundle final fixa a identidade canônica do registry e bloqueia a rede por proxies loopback durante o check Deno; isso mantém as chaves do cache estáveis sem permitir download.

## Cobertura do source incluído

Antes da publicação, o workflow executou no workspace offline:

- instalação `pnpm --offline --frozen-lockfile`;
- lint e formatação;
- `svelte-check` sem diagnósticos;
- 134 testes unitários;
- build e validação PWA;
- cinco gates de fonte;
- três testes E2E em Chromium;
- cinco módulos Edge com cache Deno e rede bloqueada;
- `doctor` completo.

O banco local não está dentro do archive. `pnpm test:db:local` continua exigindo Docker e as imagens Supabase correspondentes.

## Chave privada

A chave OpenPGP privada anexada não foi importada pelo workflow, não foi adicionada ao repositório e não aparece nos artifacts. O Fichário é público e o checkout usa apenas `actions/checkout` sem token externo.
