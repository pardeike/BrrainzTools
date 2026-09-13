#!/usr/bin/env bash
# Source from a project workflow after setting project_dir.
mkdir -p "$project_dir/.build/logs"
workflow_log="$project_dir/.build/logs/$(basename "$0" .sh)-$(date +%Y%m%d-%H%M%S)-$$.log"
exec 3>&1 4>&2
exec >"$workflow_log" 2>&1
workflow_step=initialization
workflow_child=
workflow_exit() {
  local status=$?
  if [[ $status -eq 0 ]]; then
    echo ok >&3
  else
    echo "Failed step: $workflow_step" >&4
    tail -n 18 "$workflow_log" >&4
    echo "Full log: $workflow_log" >&4
  fi
  exit "$status"
}
workflow_cancel() {
  trap - INT TERM
  if [[ -n "$workflow_child" ]]; then
    pkill -TERM -P "$workflow_child" || true
    kill -TERM "$workflow_child" 2>/dev/null || true
    wait "$workflow_child" 2>/dev/null || true
  fi
  exit 130
}
trap workflow_exit EXIT
trap workflow_cancel INT TERM
run_step() {
  workflow_step="$1"
  shift
  "$@" &
  workflow_child=$!
  wait "$workflow_child"
  workflow_child=
}
