#!/usr/bin/env bash
# Local parity with .github/workflows/sync-myfinance-schemas.yml → job "detect-drift".
#
# Auth: set MAERSK_SCHEMAS_PAT to a fine-grained GitHub PAT with Contents: Read on
# Maersk-Global/API-JSON-Schema-Definitions and Contents: Read on Maersk-Global/ui-myfinance
# (and Contents: Write on ui-myfinance when using STAGE=1).
# Or omit it and use SSH (git@github.com:...) if your git client has org access.
#
# Optional env:
#   SCHEMA_SRC_DIR   — API-JSON clone directory (default /tmp/api-src-myfinance-drift)
#   UI_SCHEMAS_DIR   — ui-myfinance sparse clone root (default /tmp/ui-src-myfinance-drift)
#   STAGE=1          — After detecting drift, push sync/myfinance-schemas-<shortSha> to
#                      ui-myfinance (requires MAERSK_SCHEMAS_PAT with Write, or SSH write).
#   UI_BASE_BRANCH   — Base branch for staging (default: resolve via `gh api` if `gh` is installed)
#   UI_STAGE_DIR     — Full clone used for staging only (default /tmp/ui-stage-myfinance-drift)
#   SCHEMA           — Exact local schema filename under schemas/ (e.g. myfinance-invoices-API.v1.yml).
#                      When set, only that row from the mapping is considered (mirrors workflow `schema` input).
#
# Usage: run from repo root.
#   Optional first arg: ONLY — extended regex matched against local schema filenames (power-user;
#   ignored for a row when SCHEMA is set).
set -euo pipefail

ONLY="${1:-}"
SCHEMA_FILE="${SCHEMA:-}"
API_DIR="${SCHEMA_SRC_DIR:-/tmp/api-src-myfinance-drift}"
UI_DIR="${UI_SCHEMAS_DIR:-/tmp/ui-src-myfinance-drift}"
UI_STAGE_DIR="${UI_STAGE_DIR:-/tmp/ui-stage-myfinance-drift}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

clone_api_repo() {
  if [ -d "$API_DIR/.git" ]; then
    return 0
  fi
  echo "Cloning API-JSON-Schema-Definitions into $API_DIR ..." >&2
  rm -rf "$API_DIR"
  if [ -n "${MAERSK_SCHEMAS_PAT:-}" ]; then
    git clone --depth=1 \
      "https://x-access-token:${MAERSK_SCHEMAS_PAT}@github.com/Maersk-Global/API-JSON-Schema-Definitions" \
      "$API_DIR"
  else
    git clone --depth=1 \
      "git@github.com:Maersk-Global/API-JSON-Schema-Definitions.git" \
      "$API_DIR"
  fi
}

clone_ui_schemas() {
  if [ -d "$UI_DIR/.git" ]; then
    return 0
  fi
  echo "Sparse-cloning ui-myfinance/schemas into $UI_DIR ..." >&2
  rm -rf "$UI_DIR"
  if [ -n "${MAERSK_SCHEMAS_PAT:-}" ]; then
    git clone --depth=1 --filter=blob:none --sparse \
      "https://x-access-token:${MAERSK_SCHEMAS_PAT}@github.com/Maersk-Global/ui-myfinance" \
      "$UI_DIR"
  else
    git clone --depth=1 --filter=blob:none --sparse \
      "git@github.com:Maersk-Global/ui-myfinance.git" \
      "$UI_DIR"
  fi
  git -C "$UI_DIR" sparse-checkout set schemas
}

stage_changes_to_ui_myfinance() {
  local changes_json="$1"
  local source_sha="$2"
  local src_dir="$3"

  if [ "${STAGE:-0}" != "1" ]; then
    return 0
  fi

  local total
  total=$(echo "$changes_json" | jq 'length')
  if [ "$total" -eq 0 ]; then
    echo "STAGE=1 but no changes; nothing to push." >&2
    return 0
  fi

  local base_ref="${UI_BASE_BRANCH:-}"
  if [ -z "$base_ref" ]; then
    if command -v gh >/dev/null 2>&1; then
      base_ref=$(gh api repos/Maersk-Global/ui-myfinance --jq .default_branch)
    else
      echo "STAGE=1: set UI_BASE_BRANCH or install GitHub CLI (gh) to resolve default branch." >&2
      exit 1
    fi
  fi

  local short_sha="${source_sha:0:7}"
  local stage_branch="sync/myfinance-schemas-${short_sha}"

  echo "STAGE=1: pushing $stage_branch from base $base_ref ..." >&2
  rm -rf "$UI_STAGE_DIR"

  if [ -n "${MAERSK_SCHEMAS_PAT:-}" ]; then
    git clone --depth=1 -b "$base_ref" \
      "https://x-access-token:${MAERSK_SCHEMAS_PAT}@github.com/Maersk-Global/ui-myfinance" \
      "$UI_STAGE_DIR"
    git -C "$UI_STAGE_DIR" remote set-url origin \
      "https://x-access-token:${MAERSK_SCHEMAS_PAT}@github.com/Maersk-Global/ui-myfinance.git"
  else
    git clone --depth=1 -b "$base_ref" \
      "git@github.com:Maersk-Global/ui-myfinance.git" \
      "$UI_STAGE_DIR"
  fi

  git -C "$UI_STAGE_DIR" config user.email "local-drift-script@local"
  git -C "$UI_STAGE_DIR" config user.name "detect-myfinance-schema-drift.sh"
  git -C "$UI_STAGE_DIR" checkout -b "$stage_branch"

  local row status remote_rel local_name
  while IFS= read -r row; do
    status=$(echo "$row" | jq -r .status)
    remote_rel=$(echo "$row" | jq -r .remote)
    local_name=$(echo "$row" | jq -r .local)
    case "$status" in
      added|modified)
        mkdir -p "$UI_STAGE_DIR/schemas"
        cp "$src_dir/$remote_rel" "$UI_STAGE_DIR/schemas/$local_name"
        ;;
      deleted)
        if [ -f "$UI_STAGE_DIR/schemas/$local_name" ]; then
          git -C "$UI_STAGE_DIR" rm -f "schemas/$local_name"
        fi
        ;;
    esac
  done < <(echo "$changes_json" | jq -c '.[]')

  git -C "$UI_STAGE_DIR" add schemas/
  git -C "$UI_STAGE_DIR" commit -m "chore(schemas): sync myfinance YAMLs from API repo @ ${source_sha}"
  git -C "$UI_STAGE_DIR" push --force-with-lease origin "$stage_branch"

  echo "STAGE_BRANCH=$stage_branch" >&2
  echo "AGENT_STARTING_REF=$stage_branch" >&2
}

clone_api_repo
clone_ui_schemas

SRC="$API_DIR"
SOURCE_SHA=$(git -C "$SRC" rev-parse HEAD)
CHANGES='[]'

MAPPING=$(cat <<'MAP'
apis/500-Maersk.com/v1/myfinance-invoices-API.v1.yml	myfinance-invoices-API.v1.yml
apis/500-Maersk.com/v2/myfinance-invoices-API.v2.yaml	myfinance-invoices-API.v2.yaml
apis/500-Maersk.com/v1/myfinance-submit-proof-of-payment-API.v1.yaml	myfinance-submit-proof-of-payment-API.v1.yaml
apis/500-Maersk.com/v1/35-myfinance-export-documents-API.v1.yml	myfinance-export-documents-API.v1.yml
apis/500-Maersk.com/v1/myfinance-refund-request-API.v1.yaml	myfinance-refund-request-API.v1.yaml
apis/500-Maersk.com/v1/myfinance-estatements-API.v1.yml	myfinance-estatements-API.v1.yml
apis/500-Maersk.com/v1/myfinance-workflows-API.v1.yaml	myfinance-workflows-API.v1.yaml
MAP
)

cd "$REPO_ROOT"
while IFS=$'\t' read -r remote_rel local_name; do
  remote_rel=$(echo "$remote_rel" | xargs)
  local_name=$(echo "$local_name" | xargs)
  if [ -n "$SCHEMA_FILE" ]; then
    if [ "$local_name" != "$SCHEMA_FILE" ]; then
      continue
    fi
  elif [ -n "$ONLY" ] && ! echo "$local_name" | grep -Eq "$ONLY"; then
    continue
  fi
  remote_path="$SRC/$remote_rel"
  local_path="$UI_DIR/schemas/$local_name"
  if [ ! -f "$remote_path" ]; then
    if [ -f "$local_path" ]; then
      CHANGES=$(echo "$CHANGES" | jq --arg r "$remote_rel" --arg l "$local_name" \
        '. + [{"remote": $r, "local": $l, "status": "deleted"}]')
    fi
  elif [ ! -f "$local_path" ]; then
    CHANGES=$(echo "$CHANGES" | jq --arg r "$remote_rel" --arg l "$local_name" \
      '. + [{"remote": $r, "local": $l, "status": "added"}]')
  elif ! diff -q "$remote_path" "$local_path" >/dev/null 2>&1; then
    CHANGES=$(echo "$CHANGES" | jq --arg r "$remote_rel" --arg l "$local_name" \
      '. + [{"remote": $r, "local": $l, "status": "modified"}]')
  fi
done <<< "$MAPPING"

TOTAL=$(echo "$CHANGES" | jq 'length')
echo "SOURCE_SHA=$SOURCE_SHA"
echo "TOTAL=$TOTAL"
echo "$CHANGES" | jq .

if [ "$TOTAL" -eq 0 ]; then
  echo "has_changes=false (launch-agent would be skipped on CI)"
  exit 0
fi

stage_changes_to_ui_myfinance "$CHANGES" "$SOURCE_SHA" "$SRC"

echo "has_changes=true (launch-agent would run on CI)"
exit 0
