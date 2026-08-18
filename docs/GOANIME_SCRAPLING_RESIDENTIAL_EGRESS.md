# GoAnime — saída residencial opcional para o Scrapling

## Objetivo

O refresh externo de catálogo do GoAnime roda em runners públicos do GitHub. Algumas fontes podem rejeitar a saída de datacenter mesmo depois da escalada `static -> dynamic -> stealth`.

Para esses casos o hub suporta uma rota **opcional e sem proxy comercial** usando Tailscale: o runner entra no tailnet em userspace e usa um dispositivo residencial como exit node. O fallback é limitado aos providers que precisam dessa rota; as fontes saudáveis continuam saindo diretamente pelo runner do GitHub.

O desenho atual é deliberadamente fail-open para o catálogo:

1. o workflow executa primeiro o crawl normal;
2. snapshots rejeitados permanecem preservados;
3. somente quando o crawl direto termina com fallback preservado o workflow considera a rota residencial;
4. se a configuração Tailscale estiver completa e a rota responder, somente `animefire` e `animesonline` são recrawleados;
5. se o dispositivo residencial estiver offline, o Tailscale falhar ou a configuração estiver ausente, o workflow continua com os snapshots preservados em vez de derrubar o catálogo.

## Componentes

O fluxo usa:

- `tailscale/github-action@v4`;
- autenticação OIDC/Workload Identity Federation, sem auth key Tailscale de longa duração no workflow;
- `tailscaled` em userspace networking;
- proxy HTTP local em `127.0.0.1:1055`;
- tag do node efêmero do runner: `tag:goanime-scraper`;
- exit node residencial indicado por variável do repositório.

O workflow principal está em:

```text
.github/workflows/goanime-scrapling-provider-cache.yml
```

Existe também um workflow residencial dedicado para diagnóstico/refresh seletivo:

```text
.github/workflows/goanime-scrapling-residential-egress.yml
```

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
```

### Repository variable

```text
GOANIME_TAILSCALE_EXIT_NODE
```

`GOANIME_TAILSCALE_EXIT_NODE` identifica o exit node residencial que o workflow deve selecionar. Use um identificador estável aceito pelo Tailscale, sem colocar credenciais nesse valor.

Não versionar os valores reais desses campos neste repositório.

## Escopo de roteamento

Quando a rota residencial está ativa, o pipeline exporta localmente:

```text
SCRAPLING_PROXY_URL=http://127.0.0.1:1055
SCRAPLING_PROXY_PROVIDERS=animefire,animesonline
```

`ScraplingFetcher` aplica o proxy somente se o `provider.id` estiver no conjunto configurado. Portanto:

- AnimeFire: rota residencial no segundo passe;
- AnimesOnline: rota residencial no segundo passe;
- Goyabu: saída direta do runner;
- AniTube: saída direta do runner.

O refresh seletivo usa `build_provider_cache.py --only-providers animefire,animesonline`, preservando snapshots, evidência e timestamps dos providers que não participam do segundo passe.

## Segurança de secrets e evidência

A URL real de proxy não deve aparecer nos documentos produzidos pelo pipeline.

O fetcher sanitiza erros antes de gravá-los em `FetchRecord`: URL configurada do proxy, `netloc`, usuário e senha são substituídos por `[redacted-proxy]`. Os artefatos de evidência registram apenas contexto operacional seguro, como `egressUsed: direct|alternate` e a classificação do bloqueio.

O workflow também não deve usar `set -x`, imprimir ambiente completo, serializar secrets em summaries ou persistir o checkout privado fora da janela necessária.

## Comportamento quando o telefone/exit node está offline

A indisponibilidade da rota residencial não é erro fatal para o catálogo.

O resultado esperado é:

- o crawl direto continua sendo a primeira fonte de verdade;
- providers que falharam mantêm o snapshot anterior validado;
- o validator roda com `--allow-preserved`;
- nenhum snapshot parcial é promovido a `complete`;
- o próximo run pode tentar novamente a rota residencial.

Isso permite usar um telefone como exit node sem transformar o telefone em dependência de disponibilidade do app.

## Como validar

Depois de configurar os campos acima, dispare o workflow de provider cache ou grave um request em:

```text
triggers/goanime-scrapling-provider-cache/*.request
```

Um run saudável deve mostrar, sem revelar secrets:

- toolchain Python/Scrapling validada;
- suíte determinística passando;
- primeiro crawl direto executado;
- tentativa Tailscale somente quando necessária;
- proxy residencial marcado como pronto quando o exit node está disponível;
- segundo passe restrito a `animefire,animesonline`;
- contrato dos caches validado;
- diff restrito aos arquivos de cache/evidência permitidos;
- artifact sanitizado;
- publicação somente se `GOANIME_CATALOG_WRITE_TOKEN` estiver configurado e a revisão de origem continuar a mesma.

Se a conexão Tailscale falhar, o summary deve registrar a ausência da rota e o workflow deve continuar pela política de preservação.

## Custos

Este desenho não depende de um provedor de proxy residencial pago. O tráfego residencial é fornecido por um dispositivo do próprio tailnet. Continuam aplicáveis os limites/termos dos serviços usados (GitHub Actions, Tailscale e conexão de internet do exit node).
