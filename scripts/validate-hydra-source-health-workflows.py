from __future__ import annotations

from pathlib import Path

WORKFLOWS = {
    ".github/workflows/smoke-private-hydra-source-discovery.yml": {
        "cron": 'cron: "17 9 * * *"',
        "marker": 'request="schedule:hydra-main"',
        "extra": ["cancel-in-progress: true", "Publish smoke running status"],
    },
    ".github/workflows/validate-private-hydra-branch.yml": {
        "cron": "cron: '17 10 * * 0'",
        "marker": 'request="schedule:hydra-main"',
        "extra": ["Run local-source tests", "Run shared downloader routing tests"],
    },
    ".github/workflows/validate-private-hydra-source-packaging.yml": {
        "cron": 'cron: "17 11 * * 0"',
        "marker": 'request="schedule:hydra-main"',
        "extra": ["Build packaged Python RPC and discovery CLI", "Verify packaged discovery artifacts"],
    },
}

COMMON = [
    'if [ "${{ github.event_name }}" = "schedule" ]; then',
    'branch="main"',
    "PRIVATE_REPOSITORIES_TOKEN",
    "https://github.com/Semogtw/HydraPersonalizado.git",
    "refs/heads/main",
    'expected_sha="$(git -c http.extraheader=',
    '[[ "$expected_sha" =~ ^[0-9a-f]{40}$ ]]',
    "repository: Semogtw/HydraPersonalizado",
    "persist-credentials: false",
    'test "$(git rev-parse HEAD)" = "$EXPECTED_SHA"',
    'test "$remote_sha" = "$EXPECTED_SHA"',
]


def require(text: str, needle: str, path: str) -> None:
    if needle not in text:
        raise SystemExit(f"{path} is missing required guard: {needle}")


for path, rules in WORKFLOWS.items():
    file = Path(path)
    if not file.is_file():
        raise SystemExit(f"missing workflow: {path}")
    text = file.read_text(encoding="utf-8")
    require(text, "schedule:", path)
    require(text, rules["cron"], path)
    require(text, rules["marker"], path)
    for needle in COMMON:
        require(text, needle, path)
    for needle in rules["extra"]:
        require(text, needle, path)

    for line in text.splitlines():
        if "git push" in line and "HydraPersonalizado" in text:
            raise SystemExit(
                f"{path} must remain read-only toward HydraPersonalizado"
            )

print("Hydra scheduled source-health workflow guards passed.")
