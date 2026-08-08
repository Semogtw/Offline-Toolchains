from __future__ import annotations

import argparse
import dataclasses
import json
import pathlib
import re
import sys

ALLOWED_REPOSITORY = "Semogtw/codex-gemini-agents"
SAFE_REF = re.compile(r"[A-Za-z0-9._/-]{1,160}")
EXPECTED_FIELDS = {"schema_version", "repository", "ref"}


class TriggerError(ValueError):
    pass


@dataclasses.dataclass(frozen=True)
class ResolvedTrigger:
    repository: str
    ref: str


def resolve_trigger(path: pathlib.Path) -> ResolvedTrigger:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise TriggerError(f"could not read trigger: {error}") from error
    if not isinstance(payload, dict):
        raise TriggerError("trigger must be a JSON object")
    if set(payload) != EXPECTED_FIELDS:
        raise TriggerError("trigger contains missing or unknown fields")
    if payload.get("schema_version") != 1:
        raise TriggerError("unsupported trigger schema_version")

    repository = payload.get("repository")
    ref = payload.get("ref")
    if repository != ALLOWED_REPOSITORY:
        raise TriggerError("repository is not allowlisted")
    if not isinstance(ref, str) or SAFE_REF.fullmatch(ref) is None:
        raise TriggerError("ref contains unsupported characters or length")
    if ".." in ref or ref.startswith("/") or ref.endswith("/"):
        raise TriggerError("ref is not a safe Git ref")
    return ResolvedTrigger(repository=repository, ref=ref)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("request", type=pathlib.Path)
    parser.add_argument(
        "--github-output",
        type=pathlib.Path,
        help="append repository/ref fields in GitHub Actions output format",
    )
    args = parser.parse_args(argv)
    try:
        resolved = resolve_trigger(args.request)
    except TriggerError as error:
        print(str(error), file=sys.stderr)
        return 2

    rendered = f"repository={resolved.repository}\nref={resolved.ref}\n"
    if args.github_output is not None:
        with args.github_output.open("a", encoding="utf-8", newline="\n") as output:
            output.write(rendered)
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
