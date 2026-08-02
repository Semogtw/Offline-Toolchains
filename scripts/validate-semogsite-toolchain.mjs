#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const workspace = resolve(root, "fixtures/semogsite/workspace");
const fixture = JSON.parse(readFileSync(resolve(workspace, "package.json"), "utf8"));
const pnpmWorkspace = readFileSync(resolve(workspace, "pnpm-workspace.yaml"), "utf8");
const smoke = readFileSync(resolve(workspace, "smoke.mjs"), "utf8");
const activate = readFileSync(resolve(root, "fixtures/semogsite/toolchain/activate.sh"), "utf8");
const install = readFileSync(resolve(root, "fixtures/semogsite/toolchain/install-offline.sh"), "utf8");
const hydrate = readFileSync(resolve(root, "fixtures/semogsite/toolchain/hydrate-native-assets.sh"), "utf8");
const doctor = readFileSync(resolve(root, "fixtures/semogsite/toolchain/doctor.sh"), "utf8");

assert.equal(fixture.private, true);
assert.equal(fixture.packageManager, "pnpm@10.14.0");
assert.match(fixture.engines.node, /22/);
assert.match(fixture.engines.pnpm, /10\.14\.0/);

const exact = {
  dependencies: {
    "@modelcontextprotocol/sdk": "^1.29.0",
    "@tanstack/react-router": "^1.168.32",
    "@tanstack/react-start": "^1.168.32",
    zod: "^3.25.1",
  },
  devDependencies: {
    "@tanstack/router-cli": "1.167.21",
    typescript: "^5.7.0",
    vite: "^6.1.0",
    vitest: "^2.1.0",
  },
};
for (const [section, dependencies] of Object.entries(exact)) {
  for (const [name, version] of Object.entries(dependencies)) {
    assert.equal(fixture[section]?.[name], version, `${section}.${name}`);
  }
}

for (const name of [
  "@hono/node-server",
  "@modelcontextprotocol/sdk",
  "@tanstack/react-query",
  "@tanstack/react-router",
  "@tanstack/react-start",
  "better-sqlite3",
  "drizzle-orm",
  "hono",
  "lucide-react",
  "react",
  "react-dom",
  "zod",
]) {
  assert.ok(fixture.dependencies?.[name], `missing runtime dependency: ${name}`);
}
for (const name of [
  "@playwright/test",
  "@tanstack/router-cli",
  "@testing-library/jest-dom",
  "@testing-library/react",
  "@types/better-sqlite3",
  "@types/node",
  "@types/react",
  "@types/react-dom",
  "@vitejs/plugin-react",
  "jsdom",
  "tsx",
  "typescript",
  "vite",
  "vitest",
  "wrangler",
]) {
  assert.ok(fixture.devDependencies?.[name], `missing development dependency: ${name}`);
}

assert.match(pnpmWorkspace, /^onlyBuiltDependencies:$/m);
const buildAllowlist = [...pnpmWorkspace.matchAll(/^  - ["']?([^"'\n]+)["']?$/gm)]
  .map((match) => match[1]);
assert.deepEqual(
  buildAllowlist,
  ["@parcel/watcher", "better-sqlite3", "esbuild", "sharp", "workerd"],
);
assert.doesNotMatch(pnpmWorkspace, /allowBuilds:|strictDepBuilds:|dangerouslyAllowAllBuilds:/);

assert.match(smoke, /better-sqlite3/);
assert.match(smoke, /drizzle-orm\/better-sqlite3/);
assert.match(smoke, /@tanstack\/react-router/);
assert.match(smoke, /@modelcontextprotocol\/sdk/);
assert.match(smoke, /React\.version/);
assert.match(activate, /PLAYWRIGHT_BROWSERS_PATH/);
assert.match(activate, /PNPM_STORE_DIR/);
assert.match(activate, /npm_config_offline=true/);
assert.match(install, /--offline/);
assert.match(install, /--ignore-scripts/);
assert.match(install, /hydrate-native-assets\.sh/);
assert.match(hydrate, /node-v\$abi-linux-x64/);
assert.match(hydrate, /better_sqlite3\.node/);
assert.match(doctor, /SemogSite toolchain doctor: PASS/);

console.log("SemogSite toolchain fixture contract: PASS");
