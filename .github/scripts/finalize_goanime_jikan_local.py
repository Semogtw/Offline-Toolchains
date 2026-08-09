from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {count}")
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


replace_once(
    "infra/jikan/scripts/restore.sh",
    "require_command docker\n\n",
    "require_command docker\n\n"
    "if ! docker compose version >/dev/null 2>&1; then\n"
    "  printf 'Could not verify Docker Compose availability before restore.\\n' >&2\n"
    "  exit 74\n"
    "fi\n\n",
    "restore early Compose probe",
)
replace_once(
    "infra/jikan/scripts/restore.sh",
    "if ! docker compose version >/dev/null; then\n"
    "  printf 'Could not verify Docker Compose availability before restore.\\n' >&2\n"
    "  exit 74\n"
    "fi\n",
    "",
    "restore old Compose probe",
)

restore_contract = "infra/jikan/tests/backup_restore_contract_test.sh"
cases = [
    (
        "restored secret stage creation failure reached Docker",
        "restored secret stage creation failure",
    ),
    (
        "restored secret stage chmod failure reached Docker",
        "restored secret stage chmod failure",
    ),
    (
        "staged secret synchronization failure must happen before Docker access",
        "staged secret synchronization failure",
    ),
    (
        "secret publication synchronization failure must happen before Docker access",
        "secret publication synchronization failure",
    ),
]
for old_message, context in cases:
    old = (
        '[[ ! -s "$DOCKER_LOG" ]] || \\\n'
        f"  fail '{old_message}'\n"
    )
    new = (
        'grep -Eq \'^compose version[[:space:]]*$\' "$DOCKER_LOG" || \\\n'
        f"  fail '{context} skipped Compose preflight'\n"
        'if grep -Ev \'^compose version[[:space:]]*$\' "$DOCKER_LOG" | grep -q .; then\n'
        f"  fail '{context} reached Docker beyond the read-only Compose preflight'\n"
        "fi\n"
    )
    replace_once(restore_contract, old, new, context)

replace_once(
    "infra/jikan/tests/validate_images_contract_test.sh",
    "printf 'docker %s\\n' \"$*\" >> \"${CALL_LOG:?}\"\n",
    "printf 'docker %s\\n' \"$*\" >> \"${CALL_LOG:?}\"\n"
    'if [[ "${1:-}" == "compose" && "${2:-}" == "version" ]]; then\n'
    "  exit 0\n"
    "fi\n",
    "validate-images fake Compose probe",
)
replace_once(
    "infra/jikan/tests/validate_images_contract_test.sh",
    '[[ ! -s "$CALL_LOG" ]] || \\\n'
    "  fail 'temporary image listing failure reached Docker'\n",
    "grep -Fxq 'docker compose version' \"$CALL_LOG\" || \\\n"
    "  fail 'temporary image listing failure skipped Compose preflight'\n"
    "if grep -Fvx 'docker compose version' \"$CALL_LOG\" | grep -q .; then\n"
    "  fail 'temporary image listing failure reached Docker beyond the read-only Compose preflight'\n"
    "fi\n",
    "validate-images mktemp assertion",
)

replace_once(
    "services/metadata-api/src/http_server.js",
    """          response.setHeader(
            'cache-control',
            `public, max-age=${Math.max(0, Math.floor((config.homeFreshTtlMs ?? 60_000) / 1_000))}`,
          );
""",
    """          // Home is assembled from independently aged section caches. A full
          // downstream max-age would reset their effective freshness whenever
          // the aggregate is requested, including stale fallback responses.
          // Revalidate via the stable ETag instead; internal section caches
          // still absorb upstream refresh traffic.
          response.setHeader(
            'cache-control',
            'public, max-age=0, must-revalidate',
          );
""",
    "Home downstream cache policy",
)

replace_once(
    "infra/jikan/scripts/measure-rpm.sh",
    '$1 ~ ("class=\\\\\\\"" class_name "\\\\\\\"")',
    'index($1, "class=\\\"" class_name "\\\"") > 0',
    "RPM class label matcher",
)
replace_once(
    "infra/jikan/scripts/measure-rpm.sh",
    '$1 ~ ("cache=\\\\\\\"" cache_name "\\\\\\\"")',
    'index($1, "cache=\\\"" cache_name "\\\"") > 0',
    "RPM cache label matcher",
)
