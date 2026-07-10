#!/usr/bin/env bash
# Fetches named myfinance OAS schema file(s) from the org-private
# Maersk-Global/API-JSON-Schema-Definitions repo and writes them into the
# current ui-myfinance checkout's schemas/ directory, ready for the
# schema-adapter agent to pick up. Run from the root of a local ui-myfinance
# checkout:
#
#   scripts/prep-myfinance-sync.sh myfinance-invoices-API.v1.yml [more.yml ...]
#
# Auth: uses your existing git/SSH access to Maersk-Global by default. Set
# MAERSK_SCHEMAS_PAT (fine-grained PAT, Contents:Read on
# API-JSON-Schema-Definitions) to use HTTPS + token instead.
#
# Source of truth for filename -> remote path -> codegen script:
#   scripts/myfinance-schema-map.tsv
set -euo pipefail

API_REPO=Maersk-Global/API-JSON-Schema-Definitions
API_DIR="${SCHEMA_SRC_DIR:-/tmp/api-src-myfinance-sync}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP_FILE="$REPO_ROOT/scripts/myfinance-schema-map.tsv"

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <schema-file.yml> [more-schema-file.yml ...]" >&2
  exit 1
fi

if [ ! -d schemas ] || [ ! -f package.json ]; then
  echo "error: run this from the root of a ui-myfinance checkout (no ./schemas or ./package.json here)" >&2
  exit 1
fi

if [ ! -f "$MAP_FILE" ]; then
  echo "error: schema map file missing: $MAP_FILE" >&2
  exit 1
fi

echo "Fetching Maersk-Global/API-JSON-Schema-Definitions ..." >&2
rm -rf "$API_DIR"
if [ -n "${MAERSK_SCHEMAS_PAT:-}" ]; then
  git clone --depth=1 "https://x-access-token:${MAERSK_SCHEMAS_PAT}@github.com/${API_REPO}" "$API_DIR" >&2
else
  git clone --depth=1 "git@github.com:${API_REPO}.git" "$API_DIR" >&2
fi
SOURCE_SHA=$(git -C "$API_DIR" rev-parse HEAD)

# Portable lookup (no associative arrays — macOS ships bash 3.2, which lacks
# them): grep the TSV directly per requested filename instead of preloading it.
map_row() {
  grep -v '^#' "$MAP_FILE" | grep -v '^[[:space:]]*$' | awk -F'\t' -v n="$1" '$2 == n { print; exit }'
}

echo "SOURCE_SHA: $SOURCE_SHA"
echo ""
echo "CHANGED SCHEMAS:"

FOUND_CHANGE=0
for local_name in "$@"; do
  row=$(map_row "$local_name")
  if [ -z "$row" ]; then
    {
      echo "error: '$local_name' is not a known myfinance schema."
      echo "Known schema files:"
      cut -f2 "$MAP_FILE" | grep -v '^#' | grep -v '^[[:space:]]*$' | sed 's/^/  - /'
    } >&2
    exit 1
  fi
  remote_rel=$(echo "$row" | cut -f1)
  codegen=$(echo "$row" | cut -f3)

  remote_path="$API_DIR/$remote_rel"
  local_path="schemas/$local_name"

  if [ ! -f "$remote_path" ]; then
    if [ -f "$local_path" ]; then
      git rm -q -f "$local_path"
      echo "status=deleted local=$local_name codegen=$codegen"
      FOUND_CHANGE=1
    else
      echo "note: $local_name has no remote file and no local file — nothing to do" >&2
    fi
    continue
  fi

  if [ -f "$local_path" ] && diff -q "$remote_path" "$local_path" >/dev/null 2>&1; then
    echo "note: $local_name is already up to date — skipping" >&2
    continue
  fi

  status=modified
  [ -f "$local_path" ] || status=added
  mkdir -p schemas
  cp "$remote_path" "$local_path"
  echo "status=$status local=$local_name codegen=$codegen"
  FOUND_CHANGE=1
done

if [ "$FOUND_CHANGE" -eq 0 ]; then
  echo "(none — all requested schemas already match the API repo)"
fi
