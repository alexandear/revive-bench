#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGETS_FILE="${TARGETS_FILE:-$ROOT_DIR/targets/repos.txt}"
TARGETS_DIR="${TARGETS_DIR:-$ROOT_DIR/targets/src}"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
REVIVE_CONFIG="${REVIVE_CONFIG:-$ROOT_DIR/configs/revive-bench.toml}"
REVIVE_FORMATTER="${REVIVE_FORMATTER:-unix}"

REVIVE_BASE_BIN="${REVIVE_BASE_BIN:-}"
REVIVE_CANDIDATE_BIN="${REVIVE_CANDIDATE_BIN:-}"

WARMUP_RUNS="${WARMUP_RUNS:-2}"
MIN_RUNS="${MIN_RUNS:-10}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --base-bin PATH         Path to baseline revive binary (optional)
  --candidate-bin PATH    Path to candidate revive binary (required)
  --config PATH           Revive config file (default: $REVIVE_CONFIG)
  --formatter NAME        Revive formatter (default: $REVIVE_FORMATTER)
  --targets-file PATH     Bench targets file (default: $TARGETS_FILE)
  --targets-dir PATH      Cloned targets directory (default: $TARGETS_DIR)
  --results-dir PATH      Output directory (default: $RESULTS_DIR)
  --warmup N              Hyperfine warmup runs (default: $WARMUP_RUNS)
  --runs N                Hyperfine minimum runs (default: $MIN_RUNS)
  -h, --help              Show this help

Mode:
  - If only --candidate-bin is provided, runs single-command timings.
  - If --base-bin and --candidate-bin are provided, compares both binaries.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-bin)
      REVIVE_BASE_BIN="$2"
      shift 2
      ;;
    --candidate-bin)
      REVIVE_CANDIDATE_BIN="$2"
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
    --results-dir)
      RESULTS_DIR="$2"
      shift 2
      ;;
    --warmup)
      WARMUP_RUNS="$2"
      shift 2
      ;;
    --runs)
      MIN_RUNS="$2"
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

if ! command -v hyperfine >/dev/null 2>&1; then
  echo "hyperfine is required but not installed." >&2
  exit 1
fi

if [[ -z "$REVIVE_CANDIDATE_BIN" ]]; then
  echo "--candidate-bin is required" >&2
  exit 1
fi

if [[ ! -x "$REVIVE_CANDIDATE_BIN" ]]; then
  echo "Candidate binary is not executable: $REVIVE_CANDIDATE_BIN" >&2
  exit 1
fi

if [[ -n "$REVIVE_BASE_BIN" && ! -x "$REVIVE_BASE_BIN" ]]; then
  echo "Base binary is not executable: $REVIVE_BASE_BIN" >&2
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

mkdir -p "$RESULTS_DIR"

version_label_for_bin() {
  local bin_path="$1"
  local label

  label="$(("$bin_path" -version 2>/dev/null || true) | head -n1 | tr -d '\r')"
  if [[ -z "$label" ]]; then
    label="$(basename "$bin_path")"
  fi

  echo "$label"
}

run_for_target() {
  local name="$1"
  local target_path="$TARGETS_DIR/$name"

  if [[ ! -d "$target_path" ]]; then
    echo "Target directory missing: $target_path" >&2
    echo "Run scripts/setup-targets.sh first." >&2
    exit 1
  fi

  local out_json="$RESULTS_DIR/${name}.json"
  local out_md="$RESULTS_DIR/${name}.md"

  local candidate_cmd="cd '$target_path' && '$REVIVE_CANDIDATE_BIN' -config '$REVIVE_CONFIG' -formatter '$REVIVE_FORMATTER' ./..."

  if [[ -n "$REVIVE_BASE_BIN" ]]; then
    local base_label
    local candidate_label
    base_label="$(version_label_for_bin "$REVIVE_BASE_BIN")"
    candidate_label="$(version_label_for_bin "$REVIVE_CANDIDATE_BIN")"

    local base_cmd="cd '$target_path' && '$REVIVE_BASE_BIN' -config '$REVIVE_CONFIG' -formatter '$REVIVE_FORMATTER' ./..."

    hyperfine \
      --warmup "$WARMUP_RUNS" \
      --min-runs "$MIN_RUNS" \
      --export-json "$out_json" \
      --export-markdown "$out_md" \
      --command-name "$base_label" "$base_cmd" \
      --command-name "$candidate_label" "$candidate_cmd"
  else
    local candidate_label
    candidate_label="$(version_label_for_bin "$REVIVE_CANDIDATE_BIN")"

    hyperfine \
      --warmup "$WARMUP_RUNS" \
      --min-runs "$MIN_RUNS" \
      --export-json "$out_json" \
      --export-markdown "$out_md" \
      --command-name "$candidate_label" "$candidate_cmd"
  fi
}

while read -r name repo ref; do
  if [[ -z "${name:-}" ]] || [[ "$name" == "#"* ]]; then
    continue
  fi

  echo
  echo "==> Benchmarking target: $name"
  run_for_target "$name"
done <"$TARGETS_FILE"

echo
echo "Results saved in $RESULTS_DIR"
