#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const workspaceRoot = resolve(root, "fixtures/semogsite/workspace");
const packagePath = resolve(workspaceRoot, "package.json");
const pnpmWorkspacePath = resolve(workspaceRoot, "pnpm-workspace.yaml");
const smokePath = resolve(workspaceRoot, "smoke.mjs");
const activatePath = resolve(root, "fixtures/semogsite/toolchain/activate.sh");
const installPath = resolve(root, "fixtures/semogsite/toolchain/install-offline.sh");
const hydratePath = resolve(
  root,
  "fixtures/semogsite/toolchain/hydrate-native-assets.sh",
);
const doctorPath = resolve(root, "fixtures/semogsite/toolchain/doctor.sh");

const fixture = JSON.parse(readFileSync(packagePath, "utf8"));
const pnpmWorkspace = readFileSync(pnpmWorkspacePath, "utf8");
const smoke = readFileSync(smokePath, "utf8");
const activate = readFileSync(activatePath, "utf8");
const install = readFileSync(installPath, "utf8");
const hydrate = readFileSync(hydratePath, "utf8");
const doctor = readFileSync(doctorPath, "utf8");

assert.equal(fixture.private, true);
assert.equal(fixture.packageManager, "pnpm@11.15.1");
assert.match(fixture.engines.node, /22/);
assert.equal(fixture.pnpm, undefined, "pnpm 11 settings belong in pnpm-workspace.yaml");
assert.equal(fixture.devDependencies["@tanstack/router-plugin"], "1.168.23");
assert.equal(fixture.devDependencies["@testing-library/jest-dom"], "6.9.1");

const requiredRuntime = [
  "@hono/node-server",
  "@tanstack/react-query",
  "@tanstack/react-router",
  "@tanstack/react-start",
  "better-sqlite3",
  "drizzle-orm",
  "hono",
  "react",
  "react-dom",
  "zod",
];
const requiredDevelopment = [
  "@playwright/test",
  "@radix-ui/react-accordion",
  "@radix-ui/react-dialog",
  "@radix-ui/react-select",
  "@tanstack/router-plugin",
  "@testing-library/dom",
  "@testing-library/jest-dom",
  "@testing-library/react",
  "@types/node",
  "@vitejs/plugin-react",
  "drizzle-kit",
  "jsdom",
  "tsx",
  "typescript",
  "vite",
  "vitest",
  "wrangler",
];

for (const dependency of requiredRuntime) {
  assert.ok(
    fixture.dependencies?.[dependency],
    `missing runtime dependency: ${dependency}`,
  );
}
for (const dependency of requiredDevelopment) {
  assert.ok(
    fixture.devDependencies?.[dependency],
    `missing development dependency: ${dependency}`,
  );
}

const builtDependencies = [...pnpmWorkspace.matchAll(/^  - ["']?([^"'\n]+)["']?$/gm)]
  .map((match) => match[1]);
assert.deepEqual(
  builtDependencies,
  [...builtDependencies].sort(),
  "onlyBuiltDependencies must stay sorted",
);
assert.ok(pnpmWorkspace.includes("onlyBuiltDependencies:"));
assert.ok(builtDependencies.includes("better-sqlite3"));
assert.ok(builtDependencies.includes("esbuild"));
assert.ok(builtDependencies.includes("workerd"));

assert.match(smoke, /better-sqlite3/);
assert.match(smoke, /drizzle-orm\/better-sqlite3/);
assert.match(smoke, /@tanstack\/react-router/);
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

const serialized = `${JSON.stringify(fixture)}\n${pnpmWorkspace}`;
for (const forbidden of [
  "PRIVATE_REPOSITORIES_TOKEN",
  "google-services.json",
  "SEMOGTW_SESSION_SECRET",
  "OWNER_PASSWORD_HASH",
]) {
  assert.equal(
    serialized.includes(forbidden),
    false,
    `fixture must not contain private marker: ${forbidden}`,
  );
}

console.log("SemogSite toolchain fixture contract: PASS");
