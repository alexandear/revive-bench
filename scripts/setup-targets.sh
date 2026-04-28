#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGETS_FILE="${TARGETS_FILE:-$ROOT_DIR/targets/repos.txt}"
DEST_DIR="${DEST_DIR:-$ROOT_DIR/targets/src}"

mkdir -p "$DEST_DIR"

if [[ ! -f "$TARGETS_FILE" ]]; then
  echo "Targets file not found: $TARGETS_FILE" >&2
  exit 1
fi

while read -r name repo ref; do
  if [[ -z "${name:-}" ]] || [[ "$name" == "#"* ]]; then
    continue
  fi

  if [[ -z "${repo:-}" || -z "${ref:-}" ]]; then
    echo "Invalid line in $TARGETS_FILE: '$name $repo $ref'" >&2
    exit 1
  fi

  repo_dir="$DEST_DIR/$name"

  if [[ -d "$repo_dir/.git" ]]; then
    echo "Updating $name ($ref)"
    git -C "$repo_dir" fetch --depth 1 origin "$ref"
    git -C "$repo_dir" checkout --detach FETCH_HEAD >/dev/null
  else
    echo "Cloning $name ($ref)"
    git clone --depth 1 --branch "$ref" "$repo" "$repo_dir"
  fi
done <"$TARGETS_FILE"

echo "Targets ready at $DEST_DIR"
