#!/usr/bin/env bash

_semogsite_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SEMOGSITE_TOOLCHAIN_ROOT="$(cd "$_semogsite_script_dir/.." && pwd)"
unset _semogsite_script_dir

export NODE_HOME="$SEMOGSITE_TOOLCHAIN_ROOT/node"
export PNPM_HOME="$SEMOGSITE_TOOLCHAIN_ROOT/pnpm/bin"
export PNPM_STORE_DIR="$SEMOGSITE_TOOLCHAIN_ROOT/pnpm-store"
export PLAYWRIGHT_BROWSERS_PATH="$SEMOGSITE_TOOLCHAIN_ROOT/playwright-browsers"
export SEMOGSITE_NATIVE_ASSETS="$SEMOGSITE_TOOLCHAIN_ROOT/native-assets"
export COREPACK_HOME="$SEMOGSITE_TOOLCHAIN_ROOT/corepack"
export XDG_CACHE_HOME="$SEMOGSITE_TOOLCHAIN_ROOT/cache"
export npm_config_cache="$SEMOGSITE_TOOLCHAIN_ROOT/npm-cache"
export npm_config_nodedir="$NODE_HOME"
export npm_config_offline=true
export npm_config_audit=false
export npm_config_fund=false
export npm_config_update_notifier=false
export NO_UPDATE_NOTIFIER=1

if [[ -d "$SEMOGSITE_TOOLCHAIN_ROOT/native-libs" ]]; then
  export LD_LIBRARY_PATH="$SEMOGSITE_TOOLCHAIN_ROOT/native-libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

export PATH="$SEMOGSITE_TOOLCHAIN_ROOT/bin:$PNPM_HOME:$NODE_HOME/bin:$PATH"
