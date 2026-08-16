# GoAnime — refresh externo de catálogo com Scrapling

O workflow `Refresh GoAnime catalog with Scrapling` executa o coletor de providers do `Semogtw/goanime-mobile` fora do APK e fora do runtime Flutter.

## Contrato de segurança

- o checkout do GoAnime usa `PRIVATE_REPOSITORIES_TOKEN` somente leitura;
- `persist-credentials` permanece desligado;
- requests automatizados contêm apenas `goanime`, um SHA hexadecimal exato e `dry-run` ou `publish`;
- `dry-run` não recebe credencial de escrita e só publica um handoff OpenPGP cifrado com retenção de um dia;
- `publish` exige `GOANIME_CATALOG_WRITE_TOKEN`, restrito ao repositório GoAnime;
- antes do push, `origin/main` precisa continuar exatamente no SHA que originou a coleta;
- source privado e temporários são removidos no cleanup `always()`.

## Request

Crie um arquivo novo em:

```text
triggers/goanime-scrapling-catalog/<identificador>.request
```

Conteúdo:

```text
goanime <sha-exato-do-goanime> dry-run
```

ou, após validação do dry-run:

```text
goanime <sha-exato-do-main> publish
```

Não use `publish` para SHA de branch de desenvolvimento. O próprio workflow recusa a publicação se o `main` remoto não corresponder exatamente ao SHA usado na coleta.

## Execução

O runner:

1. instala a versão de Scrapling pinada pelo projeto;
2. instala Chromium e dependências via `scrapling install`;
3. executa `py_compile` e a suíte determinística do pipeline;
4. coleta AnimeFire, AnimesOnline, Goyabu e AniTube;
5. valida o contrato dos caches;
6. em dry-run, cifra os artefatos em vez de alterar o projeto;
7. em publish, publica somente caches validados.

O workflow não instala Flutter porque essa etapa existe para coleta/cache. Os gates de app continuam nos workflows próprios do GoAnime.
