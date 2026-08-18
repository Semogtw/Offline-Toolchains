# GoAnime — refresh externo de catálogo com Scrapling

O catálogo externo do `Semogtw/GoAnime-Mobile` é atualizado por um único workflow canônico do `Semogtw/Offline-Toolchains`:

```text
.github/workflows/goanime-scrapling-provider-cache.yml
```

O coletor roda fora do APK/runtime Flutter. O GoAnime mantém crawlers, política de refresh, testes, validator e contrato dos artefatos; o Toolchains fornece runner confiável, toolchain pinada, egress opcional e publicação.

## Branch ativa

```text
feat/scrapling-provider-pipeline
```

Não usar o GoAnime original nem reviver os workflows residenciais/multisource antigos para este fluxo.

## Requests source-bound

Triggers por push pertencem a:

```text
triggers/goanime-scrapling-provider-cache/<identificador>.request
```

Formato:

```text
target_branch=feat/scrapling-provider-pipeline
source_hint=<SHA completo de 40 caracteres do GoAnime>
reason=<motivo curto>
```

O parser compartilhado fica em:

```text
scripts/goanime_resolve_request.py
```

Ele:

- exige exatamente um `.request` adicionado/modificado;
- rejeita remoção de request, linha malformada, chave desconhecida ou duplicada;
- valida `target_branch` com `git check-ref-format --branch`;
- exige SHA completo em triggers por push;
- cruza os paths do payload do GitHub com o diff confiável `HEAD^..HEAD` do Toolchains, evitando depender de listas de commits truncadas no evento.

Por isso os workflows que usam o parser fazem checkout do Toolchains com `fetch-depth: 2`.

`workflow_dispatch` aceita `target_branch` e um `source_hint` opcional. Quando o SHA é fornecido, o checkout privado é feito diretamente nessa revisão. Em `schedule`, a revisão obtida no checkout da branch é fixada para a execução.

## Diagnóstico determinístico

Antes de gastar um crawl real, o workflow:

```text
.github/workflows/goanime-scrapling-diagnostics.yml
```

pode validar um SHA exato do GoAnime. Ele executa:

1. checkout source-bound;
2. classificação estrutural sanitizada do MAL;
3. `mal_input_preflight.py` oficial e fail-closed;
4. Python 3.12;
5. requisitos pinados;
6. instalação Scrapling;
7. instalação Patchright/Chromium com retry;
8. verificação das versões pinadas;
9. suíte determinística.

Quando a suíte falha, o runner de diagnóstico divide os testes em grupos sanitizados (`core`, `network`, `crawl`, `evidence`) e publica apenas o estado do grupo, sem despejar conteúdo privado dos testes em status públicos.

A sonda MAL não substitui o validator: ela apenas classifica a estrutura para diagnóstico. O `mal_input_preflight.py` do próprio SHA testado continua sendo o gate obrigatório.

## Ordem do gate canônico

1. resolve/valida request ou dispatch;
2. valida credenciais e `workers`;
3. faz checkout privado da branch ou do SHA solicitado;
4. fixa/verifica a revisão de origem;
5. roda o preflight MAL antes do setup pesado;
6. instala Python 3.12 e Scrapling/Playwright/Patchright nas versões pinadas;
7. restaura browsers/estado adaptativo quando disponíveis em cache;
8. executa toda a suíte determinística;
9. executa o primeiro crawl real de AnimeFire, AnimesOnline, Goyabu e AniTube;
10. se houver fallback seguro (`exit 2`), seleciona somente providers elegíveis em `preserved`/`unavailable`;
11. quando configurado, conecta Tailscale e prova troca real de egress;
12. recrawleia apenas os providers selecionados com `--only-providers`;
13. executa `validate_provider_cache.py --allow-preserved`;
14. aplica o whitelist de diff gerado;
15. executa `git diff --cached --check`;
16. busca novamente a branch remota e exige o mesmo SHA de origem;
17. publica somente os artefatos permitidos com push normal, nunca forçado;
18. arquiva cache/evidência e limpa o checkout privado.

## Toolchain pinada

O gate verifica explicitamente:

```text
Scrapling 0.4.14
Playwright 1.62.0
Patchright 1.61.2
```

A instalação do Chromium Patchright usa `scripts/goanime_install_patchright.py` com novas tentativas. O retry cobre falhas transitórias de download, mas o gate continua falhando se o browser não puder ser instalado.

## Contrato de segurança

- `persist-credentials: false` no checkout privado;
- `PRIVATE_REPOSITORIES_TOKEN` somente onde o checkout privado precisa dele;
- `GOANIME_CATALOG_WRITE_TOKEN` somente na sondagem de publicação e no push;
- proxy direto opcional somente no primeiro crawl;
- credenciais Tailscale somente nos passos de configuração/conexão;
- preflight/testes não recebem secrets de proxy/Tailscale;
- nenhum `set -x` ou dump de ambiente;
- checkout privado removido em `always()`;
- branch remota precisa continuar no SHA de origem imediatamente antes do push;
- publicação nunca usa force-push.

## Rota residencial opcional

AnimeFire e AnimesOnline são os providers atualmente elegíveis. A lista real do segundo passe vem do manifest após o primeiro crawl, portanto um provider saudável não é rerodado apenas porque seu par falhou.

Tailscale roda em userspace com **um único listener HTTP**:

```text
--tun=userspace-networking
--outbound-http-proxy-listen=127.0.0.1:1055
```

Não use `--socks5-server` no mesmo endereço/porta. O pipeline consome HTTP em:

```text
SCRAPLING_PROXY_URL=http://127.0.0.1:1055
```

Antes do retry, o workflow exige:

- IP público direto obtido com `--noproxy '*'`;
- IP público via proxy HTTP;
- os IPs precisam ser diferentes;
- probe HTTPS adicional pela rota alternada precisa concluir.

Os IPs não são impressos.

Detalhes de configuração: `docs/GOANIME_SCRAPLING_RESIDENTIAL_EGRESS.md`.

## Estados de provider

- `complete`: crawl atual aceito pelos gates de completude/cobertura;
- `preserved`: tentativa atual rejeitada/incompleta, mas snapshot anterior validado foi preservado.

`unavailable` não passa silenciosamente pelo validator de publicação. Uma fonte sem snapshot seguro não é promovida para manter o pipeline verde.

## Política de refresh

Um crawl marcado como completo ainda precisa respeitar:

- mínimo absoluto de entradas;
- razão mínima contra snapshot anterior;
- arredondamento compatível com o runtime Dart;
- preservação do snapshot anterior quando a tentativa atual falha no contrato.

## Artefatos permitidos

```text
assets/data/anime_provider_catalogs.json
assets/data/anime_provider_catalog_manifest.json
assets/data/available_animes.json
assets/data/available_anime_modes.json
assets/data/mal_provider_availability_map.json
assets/data/provider_scrape_evidence.json
tools/scrapling_provider_pipeline/provider_source_hints.json
```

Qualquer outro arquivo gerado/alterado faz o gate falhar.

## Evidência e privacidade

A evidência pública não deve conter URL de proxy, userinfo, senha, query/fragment sensível, payload bruto de exceção, localhost ou hosts/IPs privados observados pelo navegador.

O ownership de rede continua mais estrito que a atribuição de evidência: uma URL histórica só pode ser associada a um provider depois de sanitizada, sem tornar a URL bruta elegível para fetch.

Para sucesso limpo:

- `reachable + direct` recomenda `direct`;
- `reachable + alternate` recomenda `residential`.

O validator verifica essa paridade independentemente do gerador.
