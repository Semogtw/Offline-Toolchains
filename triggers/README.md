# Private source bundle request branch

This branch stays open as the connector-controlled request surface for encrypted private source exports.

To request a fresh export, update `triggers/private-source-bundle.json` with exactly:

```json
{
  "project": "goanime",
  "mode": "full",
  "ref": ""
}
```

Allowed projects: `goanime`, `zapzap`.

Allowed modes:

- `full` — all fetched branches, tags and reachable history;
- `ref` — one exact branch, tag or hexadecimal commit;
- `snapshot` — tracked files only, without Git history.

Changing this README does not trigger an export. Only a push that changes `triggers/private-source-bundle.json` starts the secret-free request validation and, after success, the privileged encrypted export workflow from `main`.

Keep this pull request open and do not merge it.
