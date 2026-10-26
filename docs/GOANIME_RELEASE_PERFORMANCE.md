# GoAnime — desempenho do workflow oficial de release

Atualizado em 2026-10-26. Workflow: `.github/workflows/release-goanime.yml`.

## Baseline verificado

Execução bem-sucedida [1.26.28](https://github.com/Semogtw/Offline-Toolchains/actions/runs/40273367329): aproximadamente 20 minutos, com jobs paralelos. O Windows foi o caminho crítico (~18 minutos), Android ~13 minutos, Linux ~10 minutos e publicação ~1 minuto. Os números foram derivados dos logs de jobs, não de estimativas do Flutter.

O instalador `choco install innosetup openssl -y` consumiu 5m54s na 1.26.28 e 2m18s na 1.26.27. Ficou mais de 28 minutos preso nas tentativas 1.26.29/1.26.30, com Android e Linux já completos. O OpenSSL baixava um instalador de cerca de 311 MB.

## Melhorias implementadas

1. **Windows:** verificar Inno Setup instalado e reutilizar OpenSSL presente no runner/Git; instalar Inno Setup somente se necessário, com timeout. Não baixar OpenSSL grande via Chocolatey. Validado na execução [1.26.31](https://github.com/Semogtw/Offline-Toolchains/actions/runs/40345287996), que avançou para `Build and stage Windows`.
2. **Linux:** reutilizar `rustc`/`cargo` já instalados; `rustup` é fallback em runners sem Rust.
3. **Android:** cache público e imutável apenas dos toolchains NDK 28.2.13676358 e CMake 3.22.1. Chave atrelada às versões; após atualizar Flutter/NDK/CMake, revisar **ambos** os caminhos e a chave. Primeira execução cria o cache; medir da segunda em diante. Sem cache de projeto, Gradle, `private-source`, artefatos ou credenciais.
4. **Preparação:** `fetch-depth: 1` para checkout de release imutável (não há necessidade de histórico no `prepare.sh`).
5. **Publicação:** usar `aws` pré-instalado; executar `pip install --user awscli` somente quando ausente.

## Invariantes

- Sempre usar SHA resolvido no job `prepare`, `pubspec.yaml` e lançamento imutável; não reutilizar ativos de outra versão.
- Manter assinatura Android, Shorebird, hashes SHA-256 dos ativos, SBOM, manifesto de atualização assinado, staging no R2 e ponteiro `latest` atualizado somente depois de a release ser pública.
- O hub de Actions é público e compila um repositório privado. **Nunca** compartilhar `~/.gradle`, resultados de compilação, dados do checkout privado, segredos ou metadados privados via `actions/cache`. A política `scripts/validate-workflow-hub-security.py` proíbe o cache compartilhado de Gradle em workflows com `PRIVATE_REPOSITORIES_TOKEN`.
- O pipeline oficial continua multiplataforma por padrão. Uma release apenas Android não pode apagar entradas de Windows/Linux no manifesto público de atualizações.
- Nenhum ganho de tempo deve ser anunciado sem comparar execuções concluídas; cache frio pode custar tempo inicialmente.

## Como acompanhar e comparar

1. Abrir Actions > `Release GoAnime from public toolchains`.
2. Comparar os tempos de `Validate source and open staging draft`, `Android arm64 release`, `Windows x64 release`, `Linux x64 release` e `Publish R2 channel and GoAnime release`.
3. Dentro do job Windows, observar `Verify Windows packaging tools` e `Build and stage Windows`; no Android, conferir cache hit/miss da etapa `Reuse Android NDK and CMake toolchains` e os downloads do SDK.
4. Fazer benchmark contra a baseline 1.26.28, tanto em cache frio quanto aquecido, e registrar a duração da plataforma mais lenta e o total end-to-end.

## Oportunidades com trade-offs

- A preparação Flatpak/Linux (apt, SDK GNOME e libmpv) ainda baixa dependências. Uma imagem Linux pré-configurada e imutável poderia ajudar, mas adiciona custo de manutenção e exige validar compatibilidade com Shorebird e com a distribuição.
- O build Android pode continuar gastando tempo com R8/Gradle, que são tarefas legítimas. Não contornar R8, shrinker, assinatura ou testes de integridade para acelerar o release.
- Separar a distribuição Android da de desktop pode reduzir latência percebida, mas requer preservação verificável das entradas anteriores no manifesto de updates; não alterar o fluxo de publicação atual sem essa garantia.
