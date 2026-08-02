# Fichário Virtual — workspace offline portátil

O workflow `Build Fichário offline workspace` fabrica um ambiente Linux x64 para continuar o desenvolvimento de `Semogtw/FicharioVirtual` em sessões sem acesso direto à internet.

## Conteúdo

O archive inclui:

- snapshot rastreado do commit solicitado do Fichário Virtual;
- Node.js `22.16.0`;
- pnpm `10.34.5` e store compatível com o lockfile;
- Chromium do Playwright;
- Deno `2.8.1` e cache npm necessário às Edge Functions;
- Supabase CLI `2.111.0`;
- scripts de ativação, instalação offline e diagnóstico.

O bundle não contém secrets, sessões, configuração de produção, banco de dados, imagens Docker ou a chave OpenPGP privada.

## Gerar

Edite `triggers/fichario-toolchain.json` com uma branch, tag ou SHA público de `Semogtw/FicharioVirtual`:

```json
{
  "ref": "main"
}
```

Um push desse arquivo ou execução manual do workflow inicia a fabricação. O resultado é registrado na issue `[CI] Fichário offline workspace`.

## Baixar e remontar

Baixe o artifact de manifest e todas as partes `fichario-offline-linux-x64-part-*`. Extraia os ZIPs dos artifacts na mesma pasta e execute:

```bash
sha256sum -c SHA256SUMS.parts
cat fichario-offline-linux-x64.part-* > fichario-offline-linux-x64.tar.zst
sha256sum fichario-offline-linux-x64.tar.zst
zstd -t fichario-offline-linux-x64.tar.zst
tar --zstd -xf fichario-offline-linux-x64.tar.zst
```

Compare o SHA-256 do archive com `fichario-offline-linux-x64.tar.zst.sha256` antes de extrair.

## Ativar e instalar

```bash
source ./fichario-offline/bin/activate
./fichario-offline/bin/install-offline ./fichario-offline/workspace
./fichario-offline/bin/doctor ./fichario-offline/workspace
cd ./fichario-offline/workspace
```

A instalação força o registry para loopback inválido e usa `pnpm --offline --frozen-lockfile`, evitando downloads silenciosos. A ativação também aponta `DENO_DIR` para o cache empacotado e desativa a consulta de atualização do Deno.

## Gates disponíveis offline

```bash
pnpm verify
pnpm test:e2e
pnpm test:source:offline
pnpm test:functions:check
```

Durante a fabricação, o workflow popula o cache Deno online e repete `test:functions:check` com os registries npm apontados para um endereço loopback inválido. Assim, a publicação só ocorre quando as Edge Functions conseguem ser verificadas usando exclusivamente o cache incluído.

`pnpm test:db:local` requer adicionalmente:

- Docker funcional;
- imagens de containers usadas pelo Supabase local;
- permissões para iniciar os serviços.

O Supabase CLI está no bundle, mas as imagens Docker não são incluídas porque são grandes e mudam independentemente do workspace Node.

## Chave OpenPGP anexada

A chave privada cujo fingerprint é

```text
2DE29DC31427CF0A911AB96175679291435059B0
```

serve exclusivamente para descriptografar source bundles privados já cifrados pelo workflow específico. Ela não é necessária para o Fichário Virtual, que é público, e nunca deve ser armazenada em GitHub Actions, artifacts, commits ou logs.

## Evidência inicial

A primeira fabricação bem-sucedida ocorreu no run `30769889858`, commit de toolchain `2e86407f16930ba38e5c48f1f918f11bea6eac67`, produzindo manifest e duas partes. O workflow executou instalação offline, frontend, navegador, Edge Functions e diagnóstico antes de publicar os artifacts.

A geração atual adiciona os cinco gates de fonte e um smoke test de Edge Functions com registry bloqueado. O recibo mais recente na issue de CI é a fonte de verdade para a versão vigente do bundle.
