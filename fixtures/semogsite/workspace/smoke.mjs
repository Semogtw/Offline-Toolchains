import assert from "node:assert/strict";
import Database from "better-sqlite3";
import { drizzle } from "drizzle-orm/better-sqlite3";
import { Hono } from "hono";
import React from "react";
import { QueryClient } from "@tanstack/react-query";
import { createRootRoute } from "@tanstack/react-router";
import { z } from "zod";

const schema = z.object({ service: z.literal("semogsite") });
assert.deepEqual(schema.parse({ service: "semogsite" }), {
  service: "semogsite",
});

const app = new Hono();
app.get("/health", (context) => context.json({ ok: true }));
const response = await app.request("http://localhost/health");
assert.equal(response.status, 200);
assert.deepEqual(await response.json(), { ok: true });

const sqlite = new Database(":memory:");
sqlite.exec("create table smoke (value text not null)");
sqlite.prepare("insert into smoke (value) values (?)").run("offline");
assert.equal(
  sqlite.prepare("select value from smoke").get().value,
  "offline",
);
drizzle(sqlite);
sqlite.close();

const queryClient = new QueryClient();
queryClient.setQueryData(["toolchain"], "ready");
assert.equal(queryClient.getQueryData(["toolchain"]), "ready");

const route = createRootRoute();
assert.ok(route);
assert.equal(React.version, "18.3.1");

console.log(
  JSON.stringify(
    {
      ok: true,
      node: process.version,
      modulesAbi: process.versions.modules,
      react: React.version,
    },
    null,
    2,
  ),
);
