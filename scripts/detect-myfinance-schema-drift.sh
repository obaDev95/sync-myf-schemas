#!/usr/bin/env bash
# Local parity with .github/workflows/sync-myfinance-schemas.yml → job "detect-drift".
# Usage: run from repo root. Optional: ONLY regex as first arg (matches local schema filenames).
set -euo pipefail

ONLY="${1:-}"
SRC_DIR="${SCHEMA_SRC_DIR:-/tmp/api-src-myfinance-drift}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -d "$SRC_DIR/.git" ]; then
  echo "Cloning API-JSON-Schema-Definitions into $SRC_DIR ..." >&2
  rm -rf "$SRC_DIR"
  git clone --depth=1 https://github.com/Maersk-Global/API-JSON-Schema-Definitions "$SRC_DIR"
fi

SRC="$SRC_DIR"
SOURCE_SHA=$(git -C "$SRC" rev-parse HEAD)
CHANGES='[]'

MAPPING=$(cat <<'MAP'
apis/500-Maersk.com/v1/myfinance-invoices-API.v1.yml	myfinance-invoices-API.v1.yml
apis/500-Maersk.com/v2/myfinance-invoices-API.v2.yaml	myfinance-invoices-API.v2.yaml
apis/500-Maersk.com/v1/myfinance-submit-proof-of-payment-API.v1.yaml	myfinance-submit-proof-of-payment-API.v1.yaml
apis/508-PaymentsAndCheckout/v1/PNC_PaymentAvailability-API.v1.yaml	PNC_PaymentAvailability-API.v1.yaml
apis/508-PaymentsAndCheckout/v1/PNC_BankProfiles-API.v1.yaml	PNC_BankProfiles-API.v1.yaml
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
  if [ -n "$ONLY" ] && ! echo "$local_name" | grep -Eq "$ONLY"; then
    continue
  fi
  remote_path="$SRC/$remote_rel"
  local_path="schemas/$local_name"
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
echo "has_changes=true (launch-agent would run on CI)"
exit 0
