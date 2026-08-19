# GoAnime Scrapling — estado da prova residencial em 2026-08-18

## Estado observado

Até este registro, **nenhum crawl publicado do GoAnime utilizou a rota residencial Tailscale**.

Os gates canônicos que produziram cache registraram `egressUsed: direct` para AnimeFire e AnimesOnline. Quando o runner hospedado recebeu bloqueio HTTP, o pipeline preservou os snapshots previamente validados em vez de inventar uma atualização parcial.

Um diagnóstico read-only da configuração residencial confirmou que o fallback não chegou à etapa de conexão porque os três pré-requisitos abaixo não estavam configurados no `Semogtw/Offline-Toolchains`:

### GitHub Secrets

- `GOANIME_TAILSCALE_CLIENT_ID`
- `GOANIME_TAILSCALE_AUDIENCE`

### Repository variable

- `GOANIME_TAILSCALE_EXIT_NODE`

Os valores reais não devem ser versionados nem impressos em logs.

## O que isso prova — e o que não prova

A ausência desses campos prova apenas que o caminho residencial **não foi exercitado**. Ela não demonstra falha do `tailscale/github-action`, do proxy HTTP local ou do exit node.

O workflow canônico já contém o caminho esperado:

1. primeiro crawl direto;
2. seleção apenas de providers elegíveis que terminaram `preserved`/`unavailable`;
3. conexão Tailscale userspace;
4. proxy HTTP local `127.0.0.1:1055`;
5. comparação entre IP público direto e IP via proxy;
6. probe HTTPS pela rota alternativa;
7. segundo passe apenas nos providers selecionados, com `SCRAPLING_PROXY_URL=http://127.0.0.1:1055`;
8. evidência `egressUsed: alternate` quando a rota realmente for usada;
9. validator, whitelist, race-check e publicação normal.

## Critério para considerar a rota provada

A prova residencial só deve ser marcada como concluída quando um run source-bound observar simultaneamente:

- configuração residencial presente;
- ação Tailscale concluída;
- IP público via proxy diferente do IP direto;
- probe HTTPS via proxy concluído;
- segundo crawl executado para ao menos um provider selecionado;
- `provider_scrape_evidence.json` registrando `egressUsed: alternate` para esse provider;
- `recommendedEgress: residential` quando o provider ficar alcançável pela rota alternativa;
- validator e publicação cache-only concluídos sem violar o race-check.

Até lá, a documentação e o PR devem continuar descrevendo a rota como implementada, porém **não comprovada end-to-end**.
