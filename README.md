# myfinance-sync

Claude Code plugin that syncs myfinance OAS schema changes from the org-private
`Maersk-Global/API-JSON-Schema-Definitions` repo into `Maersk-Global/ui-myfinance`: regenerates
types, adapts the UI/business logic/tests to the diff, verifies with typecheck + unit tests, and
opens a PR.

## Install

```
/plugin marketplace add Maersk-Global/sync-myf-schemas
/plugin install myfinance-sync@maersk-myfinance
```

## Use

From a local `ui-myfinance` checkout:

```
cd ~/dev/ui-myfinance
claude
/myfinance-sync:sync myfinance-invoices-API.v1.yml
```

Omit the filename to be prompted with the list of known schemas
(`scripts/myfinance-schema-map.tsv`).

## How it works

1. `scripts/prep-myfinance-sync.sh` (deterministic) fetches `origin` fresh, diffs the named
   schema file(s) from `API-JSON-Schema-Definitions` against `origin/<default-branch>` (never
   the local working tree, so a stale checkout can't re-surface changes already merged
   upstream), and — only if something actually drifted — creates a sync branch off that fresh
   baseline and writes the files into `schemas/`. Unknown filenames fail fast with the list of
   valid ones; a dirty working tree aborts before anything is touched.
2. The `schema-adapter` subagent runs the matching `npm run codegen-*` script, adapts UI/types/
   business logic/tests to the diff, and iterates until `npm run typecheck` and
   `npm run test:unit` pass.
3. The orchestrator (`/myfinance-sync:sync`) commits, pushes, and opens a PR.

## Adding a schema

Add a row to `scripts/myfinance-schema-map.tsv`: remote path in
`API-JSON-Schema-Definitions`, local filename under `ui-myfinance/schemas/`, and the
`npm run` codegen script name.

## Requirements

Your local `ui-myfinance` checkout needs working git access to
`Maersk-Global/API-JSON-Schema-Definitions` (SSH by default, or set `MAERSK_SCHEMAS_PAT`) and
your usual GitHub Packages / `npm` registry auth for codegen — the same access you already use
for day-to-day development.
