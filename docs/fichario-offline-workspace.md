# Fichário Virtual — workspace offline portátil

O workflow `Build Fichário offline workspace` fabrica um ambiente Linux x64 para continuar o desenvolvimento de `Semogtw/FicharioVirtual` em sessões sem acesso direto à internet e, no runner público, executa o contrato completo de validação automatizável do projeto, incluindo o banco Supabase local.

## Conteúdo

O archive inclui:

- snapshot rastreado do commit solicitado do Fichário Virtual;
- Node.js `22.16.0`;
- pnpm `10.34.5` e store compatível com o lockfile;
- Chromium do Playwright;
- Deno `2.8.1` e cache npm necessário às Edge Functions;
- Supabase CLI `2.111.0`;
- scripts de ativação, instalação offline, verificação Edge e diagnóstico.

O bundle não contém secrets, sessões, configuração de produção, banco de dados, imagens Docker ou a chave OpenPGP privada. O `postgresql-client` usado pelo gate de banco é instalado no runner durante a fabricação; ele não é empacotado como parte da toolchain portátil.

## Gerar

Edite `triggers/fichario-toolchain.json` com uma branch, tag ou SHA público de `Semogtw/FicharioVirtual`:

```json
{
  "ref": "main"
}
```

Para uma prova reproduzível, prefira um SHA exato. Um SHA ainda não validado pode ser solicitado para diagnóstico; ele só deve ser tratado como base validada depois que o manifest registrar `validation_status=passed` e o workflow concluir com sucesso.

Um push desse arquivo ou execução manual do workflow inicia a fabricação. O resultado é registrado na issue `[CI] Fichário offline workspace`.

## Validação não bloqueia o empacotamento

A montagem do toolchain e a validação do código-fonte são tratadas separadamente. Quando Node, pnpm, store, Chromium e as demais ferramentas conseguem ser montados, o workflow empacota o workspace mesmo se um gate do snapshot falhar.

O `MANIFEST.txt` e `PARTS.txt` registram explicitamente:

```text
validation_status=passed|failed
validation_failures=none|gate:exit_code,...
database_gate=executed
```

Os gates de código são executados individualmente para maximizar o diagnóstico: lint, `svelte-check`, unitários, build, gates de fonte offline, E2E, Edge offline, Supabase local/pgTAP e doctor. Uma falha não impede os gates seguintes nem a criação dos artifacts.

Quando `validation_status=failed`:

1. manifest, diagnóstico e partes disponíveis ainda são enviados;
2. um snapshot de reparo do Prettier é produzido em melhor esforço;
3. somente depois dos uploads o workflow encerra em vermelho, preservando a indicação de que o snapshot não está validado.

Isso permite usar o bundle para continuar desenvolvimento e correção em ambientes sem rede sem transformar um gate pontual em bloqueio de checkout. O estado vermelho nunca deve ser interpretado como aprovação: consulte `validation_failures` antes de reutilizar o snapshot como base validada.

Falhas na própria montagem do toolchain — por exemplo, impossibilidade de instalar as dependências enquanto a fabricação ainda possui rede — continuam sendo erros fatais, pois nesse caso o artifact não seria confiavelmente utilizável offline.

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

Depois que o archive já estiver em uma máquina compatível, os gates que não dependem de containers continuam disponíveis diretamente:

```bash
pnpm verify
pnpm test:e2e
pnpm test:source:offline
./fichario-offline/bin/check-edge-offline ./fichario-offline/workspace
```

Durante a fabricação, o workflow:

1. popula o cache Deno com o registry npm canônico;
2. bloqueia `HTTP_PROXY`, `HTTPS_PROXY` e `ALL_PROXY` em um endpoint loopback indisponível para o smoke de Edge;
3. verifica os módulos Edge com `deno check --no-config`;
4. executa `pnpm test:db:local` no checkout smoke usando Docker do runner, Supabase CLI e `psql`;
5. registra qualquer gate falho no manifest em vez de descartar um workspace já montado.

O bloqueio por proxy mantém a identidade canônica dos pacotes. Alterar o registry para um endereço inválido mudaria a chave de resolução e produziria um falso negativo mesmo com os bytes corretos armazenados.

`pnpm test:db:local` não é prometido como gate portátil/offline do artifact porque ainda requer adicionalmente:

- Docker funcional;
- imagens de containers usadas pelo Supabase local;
- permissões para iniciar os serviços.

Essas dependências existem no runner usado para fabricar/validar o snapshot, mas as imagens Docker não são incluídas no bundle porque são grandes e mudam independentemente do workspace Node.

## Chave OpenPGP anexada

A chave privada cujo fingerprint é

```text
2DE29DC31427CF0A911AB96175679291435059B0
```

serve exclusivamente para descriptografar source bundles privados já cifrados pelo workflow específico. Ela não é necessária para o Fichário Virtual, que é público, e nunca deve ser armazenada em GitHub Actions, artifacts, commits ou logs.

O repositório possui `.gitignore` específico e o workflow `Toolchain security gates`, que rejeita nomes e marcadores de material privado rastreado. Esses gates são proteção adicional, não autorização para copiar a chave para o checkout.

## Evidência

A primeira fabricação bem-sucedida ocorreu no run `30769889858`, commit de toolchain `2e86407f16930ba38e5c48f1f918f11bea6eac67`, produzindo manifest e duas partes.

A geração v2 foi fixada no commit validado do Fichário `f961461cf27df2fe6e860e2ac50236ec2eb70a23` e adicionou:

- 134 testes unitários;
- cinco gates de fonte;
- três testes E2E;
- cache Deno verificado com rede bloqueada;
- checksum portátil;
- diagnóstico publicado mesmo em caso de falha;
- proteção contra material privado no repositório de toolchains.

A geração v3 separa fabricação de validação. Ela mantém os artifacts quando os gates do snapshot falham, grava o estado de validação no manifest e deixa o workflow vermelho somente depois dos uploads. O run `31203776099` comprovou esse contrato: builder, diagnóstico, manifest e duas partes foram concluídos antes do passo final reportar a validação falha.

A geração v4 acrescenta o gate Supabase local/pgTAP à validação executada no runner. O banco continua fora do artifact portátil, mas deixa de ser uma lacuna silenciosa do recibo do hub.

O recibo mais recente na issue de CI e o `MANIFEST.txt` do artifact são as fontes de verdade para a versão vigente do bundle.
