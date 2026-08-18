# GoAnime — refresh externo de catálogo com Scrapling

O catálogo externo do `Semogtw/GoAnime-Mobile` é atualizado por um único workflow confiável do `Semogtw/Offline-Toolchains`:

```text
.github/workflows/goanime-scrapling-provider-cache.yml
```

O coletor roda fora do APK e do runtime Flutter. O GoAnime contém parser, crawler, política de refresh, testes, validator e contrato dos artefatos; o Toolchains fornece o runner confiável, credenciais mínimas, navegador, egress opcional e publicação.

## Branch ativa

O desenvolvimento atual pertence a:

```text
feat/scrapling-provider-pipeline
```

Não usar o GoAnime original nem reviver os antigos workflows `goanime-scrapling-catalog`/`goanime-scrapling-residential-egress` para este fluxo.

## Request source-bound

Triggers automáticos pertencem a:

```text
triggers/goanime-scrapling-provider-cache/<identificador>.request
```

Formato atual:

```text
target_branch=feat/scrapling-provider-pipeline
source_hint=<SHA completo de 40 caracteres do GoAnime>
reason=<motivo curto>
```

Em push, o workflow:

- exige exatamente um `.request` adicionado/modificado;
- rejeita request removido, linha malformada, chave desconhecida ou chave duplicada;
- valida a branch com `git check-ref-format --branch`;
- exige `source_hint` hexadecimal completo;
- compara o SHA realmente obtido no checkout privado com o SHA solicitado antes de instalar a toolchain ou abrir egress.

`workflow_dispatch` e `schedule` não precisam de `source_hint`; nesses modos o SHA obtido no checkout passa a ser a revisão imutável da execução.

## Contrato de segurança

- `PRIVATE_REPOSITORIES_TOKEN` é usado somente onde o checkout privado/validação precisa dele;
- `persist-credentials` fica desativado no checkout privado;
- `GOANIME_CATALOG_WRITE_TOKEN` só é exposto à sondagem de capacidade de publicação e ao passo de push;
- o proxy direto opcional só existe no ambiente do primeiro crawl;
- credenciais Tailscale só existem nos passos que verificam/configuram o tailnet;
- testes, preflight e setup não recebem secrets de proxy/Tailscale;
- o workflow nunca usa `set -x` nem imprime ambiente completo;
- o checkout privado é removido em `always()`;
- antes do push, a branch remota precisa continuar exatamente no SHA que originou a coleta;
- o push é normal, não forçado, oferecendo uma segunda proteção contra avanço concorrente.

## Ordem dos gates

A execução confiável segue esta ordem:

1. resolve e valida o request;
2. valida credenciais e parâmetros de workers;
3. faz checkout privado da branch solicitada;
4. fixa/verifica a revisão de origem;
5. executa `mal_input_preflight.py` antes do setup pesado;
6. instala Python 3.12 e as versões pinadas de Scrapling/Playwright/Patchright;
7. restaura o estado adaptativo e browsers quando disponíveis em cache;
8. executa toda a suíte determinística do pipeline;
9. executa o primeiro crawl real de AnimeFire, AnimesOnline, Goyabu e AniTube;
10. se o crawl retornar código `2`, identifica providers elegíveis em `preserved`/`unavailable` para a rota do telefone;
11. quando configurado, conecta Tailscale e prova que o proxy realmente mudou o egress público antes do segundo passe;
12. recrawleia somente os providers selecionados com `--only-providers`;
13. valida o contrato completo dos artefatos com `validate_provider_cache.py --allow-preserved`;
14. aplica o whitelist de diff gerado;
15. faz `git diff --cached --check`;
16. busca novamente a branch remota e exige o mesmo SHA de origem;
17. publica somente os artefatos permitidos;
18. arquiva cache/evidência sanitizados e limpa o checkout privado.

## Estados de provider

A publicação aceita:

- `complete`: o crawl atual foi aceito pelos gates de completude/cobertura;
- `preserved`: o crawl atual foi rejeitado ou incompleto, mas existe snapshot anterior validado e ele foi mantido.

`unavailable` não passa pelo validator de publicação. Uma fonte sem snapshot seguro nunca é promovida apenas para manter o pipeline verde.

O manifest mantém `allProvidersComplete: false` quando algum provider está preservado.

## Política de refresh

Um crawl marcado como completo ainda precisa satisfazer a política de qualidade:

- mínimo absoluto de entradas;
- razão mínima em relação ao snapshot anterior;
- arredondamento compatível com o runtime Dart do app;
- preservação do snapshot anterior quando a tentativa atual não atende ao contrato.

Isso evita substituir silenciosamente um catálogo válido por uma coleta truncada.

## Rota residencial opcional

AnimeFire e AnimesOnline são os providers atualmente elegíveis ao fallback residencial. O workflow não reroda os dois cegamente: a lista real vem do manifest produzido no primeiro passe e inclui apenas providers elegíveis que terminaram `preserved` ou `unavailable`.

Antes do segundo passe, a rota Tailscale precisa provar:

- proxy local respondendo em `127.0.0.1:1055`;
- IP público via proxy diferente do IP público direto do runner;
- probe HTTPS concluído pela rota alternada.

Os IPs observados não são impressos. O teste direto ignora proxies herdados com `--noproxy '*'`.

Detalhes de configuração estão em `docs/GOANIME_SCRAPLING_RESIDENTIAL_EGRESS.md`.

## Artefatos permitidos

A publicação é limitada a:

```text
assets/data/anime_provider_catalogs.json
assets/data/anime_provider_catalog_manifest.json
assets/data/available_animes.json
assets/data/available_anime_modes.json
assets/data/mal_provider_availability_map.json
assets/data/provider_scrape_evidence.json
tools/scrapling_provider_pipeline/provider_source_hints.json
```

Qualquer outro arquivo alterado pelo processo faz o gate falhar.

## Evidência e privacidade

A evidência pública não deve conter URL de proxy, userinfo, senha, query string sensível ou payload bruto de exceção. O pipeline sanitiza esses dados e mantém apenas contexto operacional seguro, inclusive o marcador auditável `[redacted-proxy]` quando aplicável.

`networkAssessment` registra a rota usada e a recomendação operacional. Para sucesso limpo:

- `reachable + direct` recomenda `direct`;
- `reachable + alternate` recomenda `residential`.

O validator verifica essa paridade independentemente do gerador.

## O que este workflow não faz

- não instala Flutter para compilar o app;
- não publica código de feature;
- não altera arquivos fora do whitelist de cache/evidência;
- não transforma snapshot parcial em `complete`;
- não usa o workflow residencial antigo, que foi aposentado;
- não substitui os gates próprios do APK/runtime do GoAnime.
