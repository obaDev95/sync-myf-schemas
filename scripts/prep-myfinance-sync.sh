#!/usr/bin/env bash
# Fetches named myfinance OAS schema file(s) from the org-private
# Maersk-Global/API-JSON-Schema-Definitions repo and, if they differ from the
# fresh remote default branch of this ui-myfinance checkout, creates a sync
# branch off that branch and writes them into schemas/ — ready for the
# schema-adapter agent to pick up. Run from the root of a local ui-myfinance
# checkout:
#
#   scripts/prep-myfinance-sync.sh myfinance-invoices-API.v1.yml [more.yml ...]
#
# Always diffs against a freshly fetched origin/<default-branch>, never the
# local working tree — otherwise a stale local checkout re-introduces schema
# changes that are already merged upstream.
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

echo "Fetching origin (ui-myfinance) ..." >&2
git fetch --quiet origin

# git clone normally sets refs/remotes/origin/HEAD to the remote's default
# branch; fall back to "main" if this checkout was made in a way that skipped
# that (e.g. --single-branch).
DEFAULT_BRANCH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
if ! git rev-parse --verify --quiet "origin/$DEFAULT_BRANCH" >/dev/null; then
  echo "error: origin/$DEFAULT_BRANCH not found after fetch — check your git remote." >&2
  exit 1
fi

echo "Fetching Maersk-Global/API-JSON-Schema-Definitions ..." >&2
rm -rf "$API_DIR"
if [ -n "${API_SRC_URL:-}" ]; then
  # Local dev / test override — point at a fixture instead of the real org repo.
  git clone --depth=1 "$API_SRC_URL" "$API_DIR" >&2
elif [ -n "${MAERSK_SCHEMAS_PAT:-}" ]; then
  git clone --depth=1 "https://x-access-token:${MAERSK_SCHEMAS_PAT}@github.com/${API_REPO}" "$API_DIR" >&2
else
  git clone --depth=1 "git@github.com:${API_REPO}.git" "$API_DIR" >&2
fi
SOURCE_SHA=$(git -C "$API_DIR" rev-parse HEAD)
SHORT_SHA="${SOURCE_SHA:0:7}"

echo "SOURCE_SHA: $SOURCE_SHA"
echo "DEFAULT_BRANCH: origin/$DEFAULT_BRANCH"

# Portable lookup (no associative arrays — macOS ships bash 3.2, which lacks
# them): grep the TSV directly per requested filename instead of preloading it.
map_row() {
  grep -v '^#' "$MAP_FILE" | grep -v '^[[:space:]]*$' | awk -F'\t' -v n="$1" '$2 == n { print; exit }'
}

exists_on_default() {
  git cat-file -e "origin/$DEFAULT_BRANCH:schemas/$1" 2>/dev/null
}

# e.g. myfinance-export-documents-API.v1.yml -> export-documents-v1
slug_for() {
  echo "$1" | sed -E 's/\.ya?ml$//; s/^myfinance-//; s/-API\./-/' | tr '[:upper:]' '[:lower:]'
}

# Classify against the freshly fetched remote default branch, NOT the local
# working tree — a stale local checkout must never make an already-synced
# schema look like it still needs syncing (or vice versa). Plain indexed
# array (not associative — see bash 3.2 note above).
DRIFTED=()
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
  client=$(echo "$row" | cut -f4)
  remote_path="$API_DIR/$remote_rel"

  # Which API-repo commit last touched this file — printed alongside the
  # result so a user who doubts freshness can check provenance at a glance
  # instead of re-diffing repos by hand.
  source_commit=$(git -C "$API_DIR" log -1 --format='%h %cs %s' -- "$remote_rel" 2>/dev/null)

  if [ ! -f "$remote_path" ]; then
    if exists_on_default "$local_name"; then
      DRIFTED+=("$local_name|deleted|$codegen|$remote_path|$client|$source_commit")
    else
      echo "note: $local_name has no remote file and isn't on origin/$DEFAULT_BRANCH — nothing to do" >&2
    fi
    continue
  fi

  if exists_on_default "$local_name"; then
    if diff -q <(git show "origin/$DEFAULT_BRANCH:schemas/$local_name") "$remote_path" >/dev/null 2>&1; then
      echo "note: $local_name already matches origin/$DEFAULT_BRANCH — skipping" >&2
      continue
    fi
    status=modified
  else
    status=added
  fi
  DRIFTED+=("$local_name|$status|$codegen|$remote_path|$client|$source_commit")
done

if [ "${#DRIFTED[@]}" -eq 0 ]; then
  echo ""
  echo "CHANGED SCHEMAS:"
  echo "(none — all requested schemas already match origin/$DEFAULT_BRANCH)"
  exit 0
fi

# Only now do we touch the working tree — refuse to mix in unrelated local
# edits (or clobber them) rather than guess at stashing on the user's behalf.
if [ -n "$(git status --porcelain)" ]; then
  {
    echo "error: working tree is not clean — commit or stash your changes before syncing."
    git status --porcelain
  } >&2
  exit 1
fi

# Schema-specific branch name so two different same-day syncs (SOURCE_SHA and
# date alone don't change within a day) never collide with each other.
SLUGS=""
for entry in "${DRIFTED[@]}"; do
  IFS='|' read -r local_name _status _codegen _remote_path _client <<< "$entry"
  s=$(slug_for "$local_name")
  SLUGS="${SLUGS:+$SLUGS-}$s"
done

BRANCH="sync/myfinance-${SHORT_SHA}-${SLUGS}-$(date +%Y%m%d)"
if [ "${#BRANCH}" -gt 80 ]; then
  # Many schemas at once — collapse to a short digest rather than an unwieldy ref name.
  HASH=$(printf '%s' "$SLUGS" | shasum | cut -c1-6)
  BRANCH="sync/myfinance-${SHORT_SHA}-${HASH}-$(date +%Y%m%d)"
fi

# Fail loud on a name collision instead of guessing (auto-suffixing, reusing,
# or stacking onto an existing branch) — a prior same-day run for the same
# schema(s) needs the developer's judgment, not ours.
if git show-ref --verify --quiet "refs/heads/$BRANCH" || git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  echo "error: branch '$BRANCH' already exists (local or on origin) — likely a prior sync run for these schema(s) today. Finish, push, or delete that branch before re-running, or retry tomorrow." >&2
  exit 1
fi

git checkout -q -b "$BRANCH" "origin/$DEFAULT_BRANCH"

echo "BRANCH: $BRANCH"
echo ""
echo "CHANGED SCHEMAS:"
for entry in "${DRIFTED[@]}"; do
  IFS='|' read -r local_name status codegen remote_path client source_commit <<< "$entry"
  local_path="schemas/$local_name"
  if [ "$status" = "deleted" ]; then
    git rm -q -f "$local_path"
  else
    mkdir -p schemas
    cp "$remote_path" "$local_path"
  fi
  echo "status=$status local=$local_name codegen=$codegen client=$client"
  echo "  source: $API_REPO@${source_commit:-unknown}"
done
