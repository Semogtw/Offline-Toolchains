# Hydra source health gates

Os gates de descoberta universal do `Semogtw/HydraPersonalizado` rodam no Toolchains com checkout privado efêmero e `PRIVATE_REPOSITORIES_TOKEN` read-only.

## Gates periódicos

- **Smoke real diário:** `09:17 UTC` em `.github/workflows/smoke-private-hydra-source-discovery.yml`.
- **Validação semanal:** domingo, `10:17 UTC`, em `.github/workflows/validate-private-hydra-branch.yml`.
- **Packaging semanal:** domingo, `11:17 UTC`, em `.github/workflows/validate-private-hydra-source-packaging.yml`.

Os horários são separados para evitar disputa desnecessária por runners e para que uma falha fique atribuível ao gate correto.

## Resolução do Hydra testado

Em execução agendada, o workflow não reutiliza um arquivo de trigger antigo. Ele:

1. usa o token privado somente para leitura;
2. consulta `refs/heads/main` de `Semogtw/HydraPersonalizado` com `git ls-remote`;
3. valida que o resultado é um SHA de 40 caracteres hexadecimais;
4. faz checkout do SHA exato com `persist-credentials: false`;
5. consulta a branch novamente antes do gate e exige que ela ainda aponte para o mesmo SHA.

Se `main` mudar entre a resolução e a verificação, o gate falha em vez de produzir um recibo enganoso para uma revisão que deixou de ser a ponta da branch.

Execuções disparadas por arquivos em `triggers/` continuam aceitando branch + SHA exatos para validações de desenvolvimento. O `workflow_dispatch` existente de smoke/package continua reutilizando o request manual mais recente.

## Cobertura

### Smoke real

Exercita, em sequência:

- runtime Electron;
- runtime/browser Scrapling pinado;
- GameBounty pelo discovery universal;
- Ecológica Verde pelo adapter estruturado;
- AnkerGames pelo adapter allowlisted e recuperação browser validada;
- pipeline real até URI `trusted` e roteável para downloader;
- opção local gravando bytes reais;
- `DirectHttp` pelo `DownloadManager`, incluindo a barreira contra destino privado.

### Validação

Exercita:

- dependências JavaScript;
- Electron;
- compile e testes Python do source discovery;
- toda a suíte `local-download-sources/*.test.ts`;
- testes de roteamento de downloader;
- `typecheck:node`.

### Packaging

Exercita:

- dependências Python do runtime de discovery;
- build do RPC/discovery CLI empacotado;
- presença e executabilidade dos binários;
- presença do browser Scrapling empacotado.

## Recibos sanitizados

Os resultados por SHA ficam no branch `hydra-validation-results`:

- `hydra-smoke-results/<sha>.json`;
- `hydra-validation-results/<sha>.json`;
- `hydra-package-results/<sha>.json`.

O smoke também publica `status: running` no início para expor o `runId` antes dos testes externos demorados.

## Guard dos workflows

`.github/workflows/validate-hydra-source-health-workflows.yml` valida alterações nos três workflows e em seu contrato estático. Ele executa:

- `scripts/validate-hydra-source-health-workflows.py` para exigir cron, resolução da `main`, token read-only, checkout sem credencial persistida e verificação do SHA;
- parse YAML dos workflows;
- publicação de `validation-results/hydra-source-health-workflows.json`.

## Fronteira de segurança

Esses workflows não recebem credencial de escrita para `HydraPersonalizado`. O token privado deve continuar com `Contents: Read-only`. Nenhum gate periódico deve publicar source privado, HTML coletado, URLs finais sensíveis ou credenciais em artifact/log. Resultados persistidos são somente recibos sanitizados de status.
