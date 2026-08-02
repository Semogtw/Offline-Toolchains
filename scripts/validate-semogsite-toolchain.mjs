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
assert.equal(fixture.packageManager, "pnpm@10.14.0");
assert.match(fixture.engines.node, /22/);
assert.match(fixture.engines.pnpm, /10\.14\.0/);
assert.equal(fixture.dependencies["@modelcontextprotocol/sdk"], "^1.29.0");
assert.equal(fixture.dependencies["@tanstack/react-router"], "^1.168.32");
assert.equal(fixture.dependencies["@tanstack/react-start"], "^1.168.32");
assert.equal(fixture.dependencies.zod, "^3.25.1");
assert.equal(fixture.devDependencies["@tanstack/router-cli"], "1.167.21");
assert.equal(fixture.devDependencies.vite, "^6.1.0");
assert.equal(fixture.devDependencies.vitest, "^2.1.0");
assert.equal(fixture.devDependencies.typescript, "^5.7.0");

const requiredRuntime = [
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
];
const requiredDevelopment = [
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

assert.match(pnpmWorkspace, /^strictDepBuilds: true$/m);
assert.match(pnpmWorkspace, /^allowBuilds:$/m);
const allowedBuilds = [...pnpmWorkspace.matchAll(/^  ["']?([^"':\n]+(?:\/[^"':\n]+)?)["']?: true$/gm)]
  .map((match) => match[1]);
assert.deepEqual(
  allowedBuilds,
  [...allowedBuilds].sort(),
  "allowBuilds entries must stay sorted",
);
for (const dependency of ["@parcel/watcher", "better-sqlite3", "esbuild", "sharp", "workerd"]) {
  assert.ok(allowedBuilds.includes(dependency), `missing allowBuilds entry: ${dependency}`);
}
assert.doesNotMatch(pnpmWorkspace, /onlyBuiltDependencies:/);
assert.doesNotMatch(pnpmWorkspace, /dangerouslyAllowAllBuilds:/);

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
