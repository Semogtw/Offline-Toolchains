# GoAnime — saída residencial opcional para o Scrapling

## Objetivo

O refresh externo de catálogo do GoAnime roda em runners públicos do GitHub. Algumas fontes podem rejeitar a saída de datacenter mesmo depois da escalada `static -> dynamic -> stealth`.

Para esses casos o hub suporta uma rota **opcional e sem proxy comercial** usando Tailscale: o runner entra no tailnet em userspace e usa um dispositivo residencial como exit node. O fallback é limitado aos providers que realmente terminaram o primeiro passe em estado seguro de fallback; fontes saudáveis não são recrawleadas pelo telefone.

Existe um único workflow autorizado para construir e publicar o cache Scrapling:

```text
.github/workflows/goanime-scrapling-provider-cache.yml
```

O antigo `goanime-scrapling-residential-egress.yml` foi aposentado em 2026-08-18. O fallback residencial agora faz parte do workflow principal para que preflight, credenciais, validação, race-check e publicação tenham uma única implementação.

## Fluxo atual

O desenho é fail-safe para o catálogo:

1. um request de push informa `target_branch` e um `source_hint` de 40 caracteres;
2. o workflow valida o request em código confiável do `Offline-Toolchains`;
3. o checkout privado precisa corresponder exatamente ao `source_hint` solicitado;
4. `mal_availability_map.json` é validado antes de instalar Scrapling/Playwright ou abrir qualquer egress;
5. a suíte determinística roda antes do crawl real;
6. o primeiro passe atualiza todos os providers pela rota normal configurada;
7. quando esse passe termina com código `2`, o manifest identifica quais providers elegíveis ficaram `preserved` ou `unavailable`;
8. somente esses providers entram na tentativa opcional por Tailscale;
9. a rota do telefone só é considerada pronta se o proxy responder, o IP público observado por ele for diferente do IP direto do runner e um probe HTTPS completar;
10. o segundo passe usa `--only-providers` com a lista selecionada e preserva os demais snapshots/evidências;
11. o validator, o whitelist de diff e o race-check da revisão original rodam antes da publicação.

Se a rota residencial estiver indisponível, snapshots anteriores válidos continuam sendo a proteção normal. Um provider sem snapshot anterior permanece `unavailable` e não passa silenciosamente pelo validator de publicação.

## Componentes

O fluxo usa:

- `tailscale/github-action@v4`;
- autenticação OIDC/Workload Identity Federation, sem auth key Tailscale de longa duração no workflow;
- `tailscaled` em userspace networking;
- proxy HTTP local em `127.0.0.1:1055`;
- tag do node efêmero do runner: `tag:goanime-scraper`;
- exit node residencial indicado por variável do repositório;
- comparação de egress público direto versus proxy antes do segundo passe.

O teste do IP direto usa `--noproxy '*'`, evitando que variáveis de proxy herdadas falseiem a comparação. Os endereços observados não são impressos no log.

## Pré-requisitos no Tailscale

É necessário ter um tailnet e um dispositivo conectado à rede residencial que possa atuar como exit node. O dispositivo pode ser um computador ou outro dispositivo suportado pelo Tailscale; quando um telefone Android é usado, ele precisa estar online e com a função de exit node habilitada no momento do refresh residencial.

A ACL/grant do tailnet deve permitir que o node efêmero autenticado como `tag:goanime-scraper` use o exit node escolhido. Mantenha a permissão tão restrita quanto possível: esse runner existe somente para o refresh do GoAnime.

## Autenticação OIDC/WIF

Prefira Workload Identity Federation do Tailscale em vez de armazenar uma auth key reutilizável no GitHub.

No Tailscale, crie a configuração WIF/OAuth apropriada para este repositório/workflow e limite a identidade ao necessário para um node efêmero com a tag:

```text
tag:goanime-scraper
```

O workflow possui permissão GitHub:

```yaml
permissions:
  contents: read
  id-token: write
```

O token OIDC do GitHub é trocado durante o run; não deve ser salvo em artifact, cache ou log.

## Configuração no GitHub

Configure no repositório `Semogtw/Offline-Toolchains`:

### Secrets

```text
GOANIME_TAILSCALE_CLIENT_ID
GOANIME_TAILSCALE_AUDIENCE
PRIVATE_REPOSITORIES_TOKEN
GOANIME_CATALOG_WRITE_TOKEN
```

Opcionalmente, o primeiro passe também pode usar:

```text
GOANIME_SCRAPLING_PROXY_URL
```

Esse proxy opcional não substitui a verificação independente da rota residencial do telefone.

### Repository variable

```text
GOANIME_TAILSCALE_EXIT_NODE
```

`GOANIME_TAILSCALE_EXIT_NODE` identifica o exit node residencial que o workflow deve selecionar. Use um identificador estável aceito pelo Tailscale, sem colocar credenciais nesse valor.

Não versionar os valores reais desses campos neste repositório.

## Escopo de secrets

Secrets não ficam mais no `env` do job inteiro.

- o token privado é entregue apenas ao checkout/validação que necessita dele;
- o token de escrita existe apenas na sondagem de publicação e no passo de push;
- `GOANIME_SCRAPLING_PROXY_URL` existe apenas no primeiro crawl;
- client id/audience do Tailscale existem apenas na checagem/configuração da conexão;
- a suíte de testes, o preflight MAL e a instalação da toolchain não recebem os segredos de proxy/Tailscale.

O workflow não usa `set -x`, não imprime ambiente completo e remove o checkout privado no encerramento.

## Escopo de roteamento

Os providers elegíveis à rota residencial são atualmente:

```text
animefire,animesonline
```

Depois do primeiro passe, a lista real do segundo passe é a interseção entre esse conjunto e os providers cujo manifest terminou como `preserved` ou `unavailable`.

Durante o segundo passe o processo recebe, por exemplo:

```text
SCRAPLING_PROXY_URL=http://127.0.0.1:1055
SCRAPLING_PROXY_PROVIDERS=animefire
```

se apenas AnimeFire precisar do telefone. O mesmo valor é passado a `--only-providers`, então Goyabu, AniTube e qualquer provider elegível que já esteja saudável não são recrawleados.

`ScraplingFetcher` aplica o proxy apenas aos ids explicitamente selecionados. Escopo vazio ou ids desconhecidos são rejeitados pelo pipeline antes da criação do fetcher.

## Segurança de evidência

A URL real de proxy não deve aparecer nos documentos produzidos pelo pipeline.

O fetcher sanitiza erros antes de gravá-los em `FetchRecord`: URL configurada do proxy, `netloc`, usuário e senha são substituídos por `[redacted-proxy]`. Os artefatos públicos registram apenas contexto operacional seguro, como `egressUsed: direct|alternate` e a classificação do bloqueio.

Quando uma rota alternada produz um crawl limpo e alcançável, a evidência mantém `recommendedEgress: residential`; o validator rejeita regressões que marquem `reachable + alternate` como recomendação direta.

## Request confiável e source pinning

Requests novos pertencem a:

```text
triggers/goanime-scrapling-provider-cache/*.request
```

Formato:

```text
target_branch=feat/scrapling-provider-pipeline
source_hint=<SHA completo de 40 caracteres do GoAnime>
reason=<motivo curto>
```

Em eventos `push`, o workflow exige exatamente um request adicionado/modificado, rejeita chaves desconhecidas/duplicadas, valida o nome da branch com `git check-ref-format` e compara o SHA realmente obtido no checkout com `source_hint`.

Antes do push do cache, o workflow busca novamente a branch remota e exige que ela ainda esteja exatamente no SHA de origem. Um avanço concorrente também faz o push normal falhar por não ser fast-forward. Assim um resultado calculado sobre uma revisão antiga não pode substituir silenciosamente uma revisão mais nova.

## Comportamento quando o telefone/exit node está offline

A indisponibilidade da rota residencial não precisa derrubar um catálogo que já possui snapshot validado.

O resultado esperado é:

- o primeiro crawl continua sendo a primeira fonte de verdade;
- providers rejeitados mantêm o snapshot anterior quando ele existe;
- o validator roda com `--allow-preserved`;
- nenhum snapshot parcial é promovido a `complete`;
- providers sem snapshot anterior continuam `unavailable` e impedem publicação inválida;
- o próximo refresh pode tentar novamente a rota residencial.

Isso permite usar um telefone como exit node sem transformar o telefone em dependência de disponibilidade do app.

## Como validar

Depois de configurar os campos acima, use `workflow_dispatch` ou grave um request source-bound em:

```text
triggers/goanime-scrapling-provider-cache/*.request
```

Um run saudável deve mostrar, sem revelar secrets:

- request/branch resolvidos pelo código confiável;
- revisão solicitada e revisão obtida compatíveis;
- preflight MAL passando antes do setup pesado;
- toolchain Python/Scrapling validada;
- suíte determinística passando;
- primeiro crawl executado;
- lista explícita de providers candidatos ao telefone somente quando necessária;
- conexão Tailscale opcional;
- prova de que o proxy mudou o egress público antes do segundo passe;
- segundo passe restrito à lista calculada;
- contrato dos caches validado;
- diff restrito aos arquivos de cache/evidência permitidos;
- artifact sanitizado;
- publicação somente se o token de escrita existir e a revisão de origem continuar a mesma.

## Custos

Este desenho não depende de um provedor de proxy residencial pago. O tráfego residencial é fornecido por um dispositivo do próprio tailnet. Continuam aplicáveis os limites/termos dos serviços usados (GitHub Actions, Tailscale e conexão de internet do exit node).
