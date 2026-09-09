#!/usr/bin/env bash
set -euo pipefail

CHECKPOINT_RUN_BUDGET_MINUTES="${CHECKPOINT_RUN_BUDGET_MINUTES:-300}"
CHECKPOINT_MIN_UNIT_WINDOW_MINUTES="${CHECKPOINT_MIN_UNIT_WINDOW_MINUTES:-30}"
CHECKPOINT_WORKER="${CHECKPOINT_WORKER:-tools/manga/materialize_global_manga_availability_checkpointed_ci.sh}"

for numeric in "$CHECKPOINT_RUN_BUDGET_MINUTES" "$CHECKPOINT_MIN_UNIT_WINDOW_MINUTES"; do
  [[ "$numeric" =~ ^[0-9]+$ ]] || {
    echo "checkpoint run limits must be non-negative integers" >&2
    exit 2
  }
done

(( CHECKPOINT_RUN_BUDGET_MINUTES > 0 )) || {
  echo "CHECKPOINT_RUN_BUDGET_MINUTES must be greater than zero" >&2
  exit 2
}
(( CHECKPOINT_MIN_UNIT_WINDOW_MINUTES > 0 )) || {
  echo "CHECKPOINT_MIN_UNIT_WINDOW_MINUTES must be greater than zero" >&2
  exit 2
}
(( CHECKPOINT_MIN_UNIT_WINDOW_MINUTES < CHECKPOINT_RUN_BUDGET_MINUTES )) || {
  echo "minimum unit window must be smaller than the total run budget" >&2
  exit 2
}

test -f "$CHECKPOINT_WORKER" || {
  echo "checkpoint worker not found: $CHECKPOINT_WORKER" >&2
  exit 1
}

final_output="${GITHUB_OUTPUT:-}"
start_epoch="$(date +%s)"
budget_seconds="$((CHECKPOINT_RUN_BUDGET_MINUTES * 60))"
minimum_window_seconds="$((CHECKPOINT_MIN_UNIT_WINDOW_MINUTES * 60))"
units_completed=0
final_continue=1
final_complete=0

read_output() {
  local file="$1"
  local key="$2"
  awk -F= -v key="$key" '$1 == key { value=$2 } END { print value }' "$file"
}

emit_final_outputs() {
  echo "CHECKPOINT_CONTINUE=$final_continue"
  echo "CHECKPOINT_COMPLETE=$final_complete"
  echo "CHECKPOINT_UNITS_COMPLETED=$units_completed"
  if [[ -n "$final_output" ]]; then
    {
      echo "CHECKPOINT_CONTINUE=$final_continue"
      echo "CHECKPOINT_COMPLETE=$final_complete"
      echo "CHECKPOINT_UNITS_COMPLETED=$units_completed"
    } >> "$final_output"
  fi
}

while true; do
  now_epoch="$(date +%s)"
  elapsed_seconds="$((now_epoch - start_epoch))"
  remaining_seconds="$((budget_seconds - elapsed_seconds))"

  if (( units_completed > 0 && remaining_seconds < minimum_window_seconds )); then
    echo "[manga-checkpoint] run budget guard reached after $units_completed durable unit(s); remaining=${remaining_seconds}s"
    final_continue=1
    final_complete=0
    break
  fi

  if (( remaining_seconds <= 0 )); then
    echo "[manga-checkpoint] run budget exhausted before another durable unit"
    final_continue=1
    final_complete=0
    break
  fi

  unit_output="$(mktemp)"
  unit_timeout_seconds="$remaining_seconds"
  echo "[manga-checkpoint] starting durable unit $((units_completed + 1)); remaining budget=${remaining_seconds}s"

  set +e
  GITHUB_OUTPUT="$unit_output" timeout \
    --signal=TERM \
    --kill-after=5m \
    "${unit_timeout_seconds}s" \
    bash "$CHECKPOINT_WORKER"
  unit_status="$?"
  set -e

  if (( unit_status != 0 )); then
    rm -f "$unit_output"
    echo "[manga-checkpoint] durable unit failed with status $unit_status" >&2
    exit "$unit_status"
  fi

  unit_continue="$(read_output "$unit_output" CHECKPOINT_CONTINUE)"
  unit_complete="$(read_output "$unit_output" CHECKPOINT_COMPLETE)"
  rm -f "$unit_output"

  [[ "$unit_continue" =~ ^[01]$ ]] || {
    echo "checkpoint worker did not emit a valid CHECKPOINT_CONTINUE value" >&2
    exit 1
  }
  [[ "$unit_complete" =~ ^[01]$ ]] || {
    echo "checkpoint worker did not emit a valid CHECKPOINT_COMPLETE value" >&2
    exit 1
  }

  units_completed="$((units_completed + 1))"

  if [[ "$unit_complete" == "1" ]]; then
    final_continue=0
    final_complete=1
    break
  fi

  if [[ "$unit_continue" != "1" ]]; then
    echo "checkpoint worker stopped without completion or continuation" >&2
    exit 1
  fi

done

emit_final_outputs
