# Codex offline toolchain

Este pacote permite compilar e testar `Semogtw/codex-gemini-agents` em ambientes Linux x64 sem depender de uma instalação prévia do toolchain no consumidor.

## Fonte imutável

O bundle principal e o artifact `rusty_v8` não usam mais uma branch Codex hardcoded. Cada workflow lê um trigger versionado com:

```json
{
  "schema_version": 1,
  "repository": "Semogtw/codex-gemini-agents",
  "ref": "<branch-segura-ou-SHA-completo>"
}
```

O resolver `scripts/resolve_codex_toolchain_trigger.py` é testado antes do checkout, aceita somente o fork allowlisted e rejeita refs inseguras/fields desconhecidos. Quando `ref` é um SHA completo de 40 caracteres, o workflow exige que `git rev-parse HEAD` seja exatamente esse SHA.

Para checkpoints de integração CodexGemini, prefira sempre SHA completo. Branches continuam permitidas apenas para hidratação manual/exploratória do toolchain.

Triggers atuais:

- `triggers/codex-toolchain.json` — bundle principal;
- `triggers/codex-rusty-v8.json` — arquivo `rusty_v8` correspondente ao mesmo `Cargo.lock`.

## Conteúdo

O workflow `Build Codex offline toolchain` publica:

- Rust e Cargo 1.95.0;
- `rustfmt` e Clippy do mesmo toolchain;
- cache Cargo hidratado pelo `Cargo.lock` do ref Codex solicitado;
- Ruff e uv;
- just;
- `protoc` e bibliotecas/headers nativos necessários ao Codex;
- script portátil `activate.sh`.

O `MANIFEST.txt` schema 2 registra `codex_repository`, `codex_ref` e `codex_commit` realmente usados. `PARTS.txt` repete a identidade do core junto ao checksum do archive.

O workflow `Build Codex rusty_v8 offline archive` publica separadamente o arquivo pré-compilado de `rusty_v8` correspondente à versão `v8` encontrada no `Cargo.lock` do ref solicitado. Seu manifest schema 2 registra a mesma tríade `codex_repository/codex_ref/codex_commit`.

Separar o V8 evita reconstruir o bundle principal quando apenas esse artifact precisa ser renovado, sem permitir que os dois sejam silenciosamente gerados de branches diferentes.

## Build imutável do par CodexGemini

`triggers/codex-gemini-pair.json` é mais estrito: exige SHAs completos tanto do core quanto do wrapper. O workflow `Build immutable CodexGemini pair` faz checkout de ambos, verifica as identidades exatas, executa o contrato determinístico de fonte e compila o binário release `codex`.

Por segurança, esse gate de build não executa nem stageia o binário recém-compilado no CI. Ele produz evidência estática (`SHA-256`, tamanho, `file`, header ELF) e associa o artefato aos dois commits exatos. O `external-agents/stage.sh` do wrapper continua sendo a autoridade para executar `--version`, validar identidade/checksum e produzir `compatibility.json` em um ambiente de staging confiável.

## Remontar o bundle principal

Baixe os artifacts `codex-toolchain-linux-x64-manifest` e `codex-toolchain-linux-x64-part-*`, extraia os ZIPs na mesma pasta e valide:

```bash
sha256sum --check SHA256SUMS.parts
cat codex-toolchain-linux-x64.part-* > codex-toolchain-linux-x64.tar.zst
sha256sum codex-toolchain-linux-x64.tar.zst
```

Compare o SHA-256 do arquivo remontado com `archive_sha256` em `PARTS.txt` antes de extrair:

```bash
mkdir -p /tmp/codex-offline
tar --zstd -xf codex-toolchain-linux-x64.tar.zst -C /tmp/codex-offline
source /tmp/codex-offline/codex-toolchain/activate.sh
```

A ativação define `CARGO_NET_OFFLINE=true`, configura caches e adiciona ferramentas/dependências nativas ao shell atual. Ela não modifica configuração Git global.

## Ativar o V8 offline

Baixe e extraia `codex-rusty-v8-linux-x64`, valide:

```bash
sha256sum --check SHA256SUMS
```

Depois defina:

```bash
export RUSTY_V8_ARCHIVE="$PWD/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz"
```

O `MANIFEST.txt` informa versão da crate V8, target, ref/commit Codex e URL pública de origem.

## Verificação mínima

```bash
rustc --version
cargo --version
cargo clippy --version
cargo fmt --version
ruff --version
uv --version
just --version
protoc --version

cd codex-rs
cargo metadata --locked --offline --no-deps >/dev/null
cargo test --offline -p codex-state external_agent_sessions --lib
```

O repositório Codex usa pelo menos 8 MiB de stack nos testes Rust:

```bash
export RUST_MIN_STACK=8388608
```

## Gate completo do fork

```bash
source /caminho/codex-toolchain/activate.sh
export RUSTY_V8_ARCHIVE=/caminho/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz
export RUST_MIN_STACK=8388608

python3 scripts/verify_external_agent_integration.py \
  --require-rust \
  --command-timeout-seconds 7200
```

Ou execute manualmente:

```bash
cd codex-rs
cargo fmt --all -- --check
cargo test --offline -p codex-state external_agent_sessions --lib
cargo test --offline -p codex-core --lib --tests
cargo clippy --offline -p codex-state --lib --tests -- -D warnings
cargo clippy --offline -p codex-core --lib --tests -- -D warnings
```

## Quando regenerar

Regenere o bundle principal quando houver mudança relevante em `Cargo.lock`, versão Rust, ferramentas, dependências nativas, arquitetura ou no ref Codex aceito para o checkpoint.

Regenere `rusty_v8` quando a versão da crate `v8` no lockfile mudar ou quando o core pinado mudar. O workflow resolve a versão automaticamente e falha se o lockfile não contiver exatamente uma entrada `v8`.

## Segurança

- O pacote contém executáveis; use somente artifacts de runs confiáveis.
- Verifique hashes antes de extrair ou executar.
- Checkpoints de integração devem usar SHAs completos, não branches móveis.
- O resolver rejeita repositórios não allowlisted, refs inseguras e campos extras.
- Os workflows usam somente dependências públicas e não precisam da chave privada OpenPGP.
- A chave privada de source bundles nunca deve ser copiada para este repositório, artifacts ou checkout Codex.
- Importe material secreto apenas em armazenamento temporário explicitamente necessário e remova-o depois.
