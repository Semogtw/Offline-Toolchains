from __future__ import annotations

import argparse
import dataclasses
import json
import pathlib
import re
import sys

CORE_REPOSITORY = "Semogtw/codex-gemini-agents"
WRAPPER_REPOSITORY = "Semogtw/codex-desktop-linux-gemini-"
FULL_SHA = re.compile(r"[0-9a-fA-F]{40}")
EXPECTED_FIELDS = {
    "schema_version",
    "core_repository",
    "core_ref",
    "wrapper_repository",
    "wrapper_ref",
}


class PairTriggerError(ValueError):
    pass


@dataclasses.dataclass(frozen=True)
class ResolvedPairTrigger:
    core_repository: str
    core_ref: str
    wrapper_repository: str
    wrapper_ref: str


def resolve_pair_trigger(path: pathlib.Path) -> ResolvedPairTrigger:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PairTriggerError(f"could not read pair trigger: {error}") from error
    if not isinstance(payload, dict):
        raise PairTriggerError("pair trigger must be a JSON object")
    if set(payload) != EXPECTED_FIELDS:
        raise PairTriggerError("pair trigger contains missing or unknown fields")
    if payload.get("schema_version") != 1:
        raise PairTriggerError("unsupported pair trigger schema_version")
    if payload.get("core_repository") != CORE_REPOSITORY:
        raise PairTriggerError("core repository is not allowlisted")
    if payload.get("wrapper_repository") != WRAPPER_REPOSITORY:
        raise PairTriggerError("wrapper repository is not allowlisted")

    core_ref = payload.get("core_ref")
    wrapper_ref = payload.get("wrapper_ref")
    if not isinstance(core_ref, str) or FULL_SHA.fullmatch(core_ref) is None:
        raise PairTriggerError("core_ref must be a full 40-character hexadecimal SHA")
    if not isinstance(wrapper_ref, str) or FULL_SHA.fullmatch(wrapper_ref) is None:
        raise PairTriggerError("wrapper_ref must be a full 40-character hexadecimal SHA")

    return ResolvedPairTrigger(
        core_repository=CORE_REPOSITORY,
        core_ref=core_ref.lower(),
        wrapper_repository=WRAPPER_REPOSITORY,
        wrapper_ref=wrapper_ref.lower(),
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("request", type=pathlib.Path)
    parser.add_argument("--github-output", type=pathlib.Path)
    args = parser.parse_args(argv)
    try:
        pair = resolve_pair_trigger(args.request)
    except PairTriggerError as error:
        print(str(error), file=sys.stderr)
        return 2

    rendered = (
        f"core_repository={pair.core_repository}\n"
        f"core_ref={pair.core_ref}\n"
        f"wrapper_repository={pair.wrapper_repository}\n"
        f"wrapper_ref={pair.wrapper_ref}\n"
    )
    if args.github_output is not None:
        with args.github_output.open("a", encoding="utf-8", newline="\n") as output:
            output.write(rendered)
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
