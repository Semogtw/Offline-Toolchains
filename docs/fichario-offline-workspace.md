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
- scripts de ativação, instalação offline, verificação Edge e diagnóstico.

O bundle não contém secrets, sessões, configuração de produção, banco de dados, imagens Docker ou a chave OpenPGP privada.

## Gerar

Edite `triggers/fichario-toolchain.json` com uma branch, tag ou SHA público de `Semogtw/FicharioVirtual`:

```json
{
  "ref": "main"
}
```

Para uma prova reproduzível, prefira um SHA integralmente validado no lugar de uma branch móvel.

Um push desse arquivo ou execução manual do workflow inicia a fabricação. O resultado é registrado na issue `[CI] Fichário offline workspace`.

## Baixar e remontar

Baixe o artifact de manifest e todas as partes `fichario-offline-linux-x64-part-*`. Extraia os ZIPs dos artifacts na mesma pasta e execute:

```bash
sha256sum -c SHA256SUMS.parts
cat fichario-offline-linux-x64.part-* > fichario-offline-linux-x64.tar.zst
sha256sum -c fichario-offline-linux-x64.tar.zst.sha256
zstd -t fichario-offline-linux-x64.tar.zst
tar --zstd -xf fichario-offline-linux-x64.tar.zst
```

Os checksums usam somente nomes relativos e continuam verificáveis depois do download em outro ambiente.

## Ativar e instalar

```bash
source ./fichario-offline/bin/activate
./fichario-offline/bin/install-offline ./fichario-offline/workspace
./fichario-offline/bin/doctor ./fichario-offline/workspace
cd ./fichario-offline/workspace
```

A instalação aponta temporariamente o registry para loopback inválido e usa `pnpm --offline --frozen-lockfile`, evitando downloads silenciosos. A ativação:

- aponta `DENO_DIR` para o cache empacotado;
- desativa a consulta de atualização do Deno;
- fixa `https://registry.npmjs.org/` como identidade canônica do registry npm, independentemente da configuração do ambiente consumidor.

Fixar a identidade é necessário porque o Deno incorpora o URL do registry à resolução dos pacotes npm. Um registry corporativo ou proxy local herdado pelo shell não deve invalidar o cache portátil.

## Gates disponíveis offline

```bash
pnpm verify
pnpm test:e2e
pnpm test:source:offline
./fichario-offline/bin/check-edge-offline ./fichario-offline/workspace
```

Durante a fabricação, o workflow:

1. popula o cache Deno com o registry npm canônico;
2. bloqueia `HTTP_PROXY`, `HTTPS_PROXY` e `ALL_PROXY` em um endpoint loopback indisponível;
3. verifica os cinco módulos Edge com `deno check --no-config`;
4. falha se qualquer dependência não estiver no cache.

O bloqueio por proxy mantém a identidade canônica dos pacotes. Alterar o registry para um endereço inválido mudaria a chave de resolução e produziria um falso negativo mesmo com os bytes corretos armazenados.

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

O repositório possui `.gitignore` específico e o workflow `Toolchain security gates`, que rejeita nomes e marcadores de material privado rastreado. Esses gates são proteção adicional, não autorização para copiar a chave para o checkout.

## Evidência

A primeira fabricação bem-sucedida ocorreu no run `30769889858`, commit de toolchain `2e86407f16930ba38e5c48f1f918f11bea6eac67`, produzindo manifest e duas partes.

A geração v2 está fixada no commit validado do Fichário `f961461cf27df2fe6e860e2ac50236ec2eb70a23` e adiciona:

- 134 testes unitários;
- cinco gates de fonte;
- três testes E2E;
- cache Deno verificado com rede bloqueada;
- checksum portátil;
- diagnóstico publicado mesmo em caso de falha;
- proteção contra material privado no repositório de toolchains.

O recibo mais recente na issue de CI e o `MANIFEST.txt` do artifact são as fontes de verdade para a versão vigente do bundle.
