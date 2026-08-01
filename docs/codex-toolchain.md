# Codex offline toolchain

Este pacote permite compilar e testar `Semogtw/codex-gemini-agents` em ambientes Linux x64 sem acesso direto à internet.

## Conteúdo

O workflow `Build Codex offline toolchain` publica:

- Rust e Cargo 1.95.0;
- `rustfmt` e Clippy do mesmo toolchain;
- cache Cargo hidratado pelo `Cargo.lock` da branch `feature/antigravity-capabilities`;
- Ruff 0.15.13 e uv 0.11.3;
- just 1.51.0;
- `protoc` e bibliotecas/headers nativos necessários ao Codex;
- script portátil `activate.sh`.

O workflow `Build Codex rusty_v8 offline archive` publica separadamente o arquivo pré-compilado de `rusty_v8` correspondente à versão `v8` encontrada no `Cargo.lock` ativo. Separar o V8 evita reconstruir o bundle principal quando apenas esse artifact precisa ser renovado.

## Obter os IDs pelo conector

Cada run concluído comenta o issue permanente `Codex offline toolchain run receipts` com:

- run ID e commit;
- conclusão;
- IDs, tamanhos e expiração dos artifacts.

Use apenas recibos com conclusão `success` e commits confiáveis.

## Remontar o bundle principal

Baixe:

```text
codex-toolchain-linux-x64-manifest
codex-toolchain-linux-x64-part-00
codex-toolchain-linux-x64-part-01
...
```

Extraia todos os ZIPs na mesma pasta e execute:

```bash
sha256sum --check SHA256SUMS.parts
cat codex-toolchain-linux-x64.part-* > codex-toolchain-linux-x64.tar.zst
```

Compare o SHA-256 do arquivo remontado com `archive_sha256` em `PARTS.txt` antes de extrair:

```bash
sha256sum codex-toolchain-linux-x64.tar.zst
mkdir -p /tmp/codex-offline
tar --zstd -xf codex-toolchain-linux-x64.tar.zst -C /tmp/codex-offline
source /tmp/codex-offline/codex-toolchain/activate.sh
```

A ativação define `CARGO_NET_OFFLINE=true`, configura os caches e adiciona ferramentas e dependências nativas ao shell atual. Ela não modifica configuração Git global.

## Ativar o V8 offline

Baixe e extraia o artifact:

```text
codex-rusty-v8-linux-x64
```

Valide o checksum relativo dentro da pasta extraída:

```bash
sha256sum --check SHA256SUMS
```

Depois defina:

```bash
export RUSTY_V8_ARCHIVE="$PWD/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz"
```

O `MANIFEST.txt` informa a versão da crate V8, target, commit do Codex e URL pública de origem.

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

Regenere o bundle principal quando houver mudança relevante em:

- `codex-rs/Cargo.lock`;
- versão Rust fixada;
- Ruff/uv/just;
- dependências nativas;
- arquitetura ou imagem Linux do consumidor.

Regenere o artifact V8 quando a versão da crate `v8` no lockfile mudar. O workflow resolve essa versão automaticamente e falha se o lockfile não contiver exatamente uma entrada `v8`.

## Segurança

- O pacote contém executáveis; use somente artifacts de runs confiáveis.
- Verifique hashes antes de extrair ou executar.
- Os workflows do toolchain usam somente dependências públicas e não precisam da chave privada OpenPGP.
- A chave privada de source bundles nunca deve ser copiada para este repositório, para artifacts ou para o checkout Codex.
- Importe a chave privada apenas em `GNUPGHOME` temporário quando for realmente necessário descriptografar um source bundle; remova o diretório depois.
