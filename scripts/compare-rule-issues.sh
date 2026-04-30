#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REVIVE_CONFIG="${REVIVE_CONFIG:-$ROOT_DIR/configs/revive-bench.toml}"
REVIVE_FORMATTER="${REVIVE_FORMATTER:-unix}"
REVIVE_BIN="${REVIVE_BIN:-$ROOT_DIR/bin/revive-base}"
REPO_PATH="${REPO_PATH:-}"
RUNS="${RUNS:-3}"
DETAILS_DIR="${DETAILS_DIR:-$ROOT_DIR/results/rule-issues}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --revive-bin PATH      Path to revive binary (default: $REVIVE_BIN)
  --repo PATH            Repository path or target name under targets/src (required)
  --config PATH          Revive config file (default: $REVIVE_CONFIG)
  --formatter NAME       Revive formatter (default: $REVIVE_FORMATTER)
  --runs N               Number of runs to compare (default: $RUNS)
  --details-dir PATH     Output directory for raw run outputs (default: $DETAILS_DIR)
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --revive-bin)
      REVIVE_BIN="$2"
      shift 2
      ;;
    --repo)
      REPO_PATH="$2"
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
    --runs)
      RUNS="$2"
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

if [[ -z "$REPO_PATH" ]]; then
  echo "--repo is required" >&2
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

if ! [[ "$RUNS" =~ ^[1-9][0-9]*$ ]]; then
  echo "--runs must be a positive integer" >&2
  exit 1
fi

if [[ ! -d "$REPO_PATH" ]]; then
  local_target="$ROOT_DIR/targets/src/$REPO_PATH"
  if [[ -d "$local_target" ]]; then
    REPO_PATH="$local_target"
  else
    echo "Repository path not found: $REPO_PATH" >&2
    exit 1
  fi
fi

repo_name="$(basename "$REPO_PATH")"
run_dir="$DETAILS_DIR/$repo_name"
mkdir -p "$run_dir"

declare -A seen_rules=()

extract_rule_counts() {
  local file_path="$1"

  sed -nE 's|^.+:[0-9]+(:[0-9]+)?: \[([a-z0-9-]+)\].*$|\2|p' "$file_path" 2>/dev/null \
    | sort \
    | uniq -c \
    | awk '{ print $2 " " $1 }'
}

write_sorted_unix_output() {
  local output_file="$1"

  ((cd "$REPO_PATH" && "$REVIVE_BIN" -config "$REVIVE_CONFIG" -formatter "$REVIVE_FORMATTER" ./...) 2>&1 || true) \
    | perl -ne 'if (m/^.+:\d+(?::\d+)?: \[([a-z0-9-]+)\]/) { print "$1\t$_" } else { print "~\t$_" }' \
    | LC_ALL=C sort -t $'\t' -k1,1 -k2,2 \
    | cut -f2- >"$output_file"
}

for run in $(seq 1 "$RUNS"); do
  out_file="$run_dir/run-$run.txt"
  echo "==> Run $run/$RUNS"
  write_sorted_unix_output "$out_file"

  while read -r rule count; do
    [[ -z "${rule:-}" ]] && continue
    seen_rules["$rule"]=1
  done < <(extract_rule_counts "$out_file")
done

if [[ ${#seen_rules[@]} -eq 0 ]]; then
  echo
  echo "No issues found across $RUNS run(s)."
  echo "Raw outputs saved in $run_dir"
  exit 0
fi

mapfile -t sorted_rules < <(printf '%s\n' "${!seen_rules[@]}" | sort)

echo
echo "# revive rule issue comparison"
echo
echo "Repository: $REPO_PATH"
echo "Binary: $REVIVE_BIN"
echo "Runs: $RUNS"
echo

header="$(printf '%-36s' 'Rule')"
for run in $(seq 1 "$RUNS"); do
  header+=" $(printf 'run-%-6s' "$run")"
done
echo "$header"
printf '%-36s' '------------------------------------'
for run in $(seq 1 "$RUNS"); do
  printf ' %-10s' '----------'
done
echo

for rule in "${sorted_rules[@]}"; do
  printf '%-36s' "$rule"
  for run in $(seq 1 "$RUNS"); do
    count="0"
    while read -r current_rule current_count; do
      if [[ "$current_rule" == "$rule" ]]; then
        count="$current_count"
        break
      fi
    done < <(extract_rule_counts "$run_dir/run-$run.txt")
    printf ' %-10s' "$count"
  done
  echo
done

echo
echo "Raw outputs saved in $run_dir"
