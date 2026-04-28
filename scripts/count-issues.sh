#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGETS_FILE="${TARGETS_FILE:-$ROOT_DIR/targets/repos.txt}"
TARGETS_DIR="${TARGETS_DIR:-$ROOT_DIR/targets/src}"
REVIVE_CONFIG="${REVIVE_CONFIG:-$ROOT_DIR/configs/revive-bench.toml}"
REVIVE_FORMATTER="${REVIVE_FORMATTER:-unix}"

REVIVE_BIN="${REVIVE_BIN:-}"
DETAILS_DIR="${DETAILS_DIR:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --revive-bin PATH      Path to revive binary (required)
  --config PATH          Revive config file (default: $REVIVE_CONFIG)
  --formatter NAME       Revive formatter (default: $REVIVE_FORMATTER)
  --targets-file PATH    Bench targets file (default: $TARGETS_FILE)
  --targets-dir PATH     Cloned targets directory (default: $TARGETS_DIR)
  --details-dir PATH     Write per-repo issue details (*.txt) to this directory
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --revive-bin)
      REVIVE_BIN="$2"
      shift 2
      ;;
    --config)
      REVIVE_CONFIG="$2"
      shift 2
      ;;
    --formatter)
      REVIVE_FORMATTER="$2"
      shift 2
      ;;
    --targets-file)
      TARGETS_FILE="$2"
      shift 2
      ;;
    --targets-dir)
      TARGETS_DIR="$2"
      shift 2
      ;;
    --details-dir)
      DETAILS_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$REVIVE_BIN" ]]; then
  echo "--revive-bin is required" >&2
  exit 1
fi

if [[ ! -x "$REVIVE_BIN" ]]; then
  echo "Revive binary is not executable: $REVIVE_BIN" >&2
  exit 1
fi

if [[ ! -f "$REVIVE_CONFIG" ]]; then
  echo "Config not found: $REVIVE_CONFIG" >&2
  exit 1
fi

if [[ ! -f "$TARGETS_FILE" ]]; then
  echo "Targets file not found: $TARGETS_FILE" >&2
  exit 1
fi

if [[ -n "$DETAILS_DIR" ]]; then
  mkdir -p "$DETAILS_DIR"
fi

count_issues_for_target() {
  local name="$1"
  local target_path="$TARGETS_DIR/$name"

  if [[ ! -d "$target_path" ]]; then
    echo "Target directory missing: $target_path" >&2
    return 1
  fi

  local output
  output="$( (cd "$target_path" && "$REVIVE_BIN" -config "$REVIVE_CONFIG" -formatter "$REVIVE_FORMATTER" ./...) 2>&1 || true )"

  if [[ -n "$DETAILS_DIR" ]]; then
    printf "%s\n" "$output" >"$DETAILS_DIR/${name}.txt"
  fi

  local count
  count=$(printf "%s\n" "$output" | grep -cve '^[[:space:]]*$' || true)
  if [[ -z "$count" ]]; then
    count=0
  fi

  echo "$count"
}

{
  echo "# revive issue count"
  echo
  printf "%-24s %s\n" "Repository" "Issues"
  printf "%-24s %s\n" "------------------------" "----------"

  total_issues=0
  while read -r name repo ref; do
    if [[ -z "${name:-}" ]] || [[ "$name" == "#"* ]]; then
      continue
    fi

    count=$(count_issues_for_target "$name" || echo "ERROR")
    if [[ "$count" != "ERROR" ]]; then
      total_issues=$((total_issues + count))
      printf "%-24s %s\n" "$name" "$count"
    else
      printf "%-24s %s\n" "$name" "ERROR"
    fi
  done <"$TARGETS_FILE"

  echo
  echo "Total: $total_issues issues"
}
