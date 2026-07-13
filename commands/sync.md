---
description: Sync myfinance OAS schema file(s) into this ui-myfinance checkout — regenerate types, adapt UI/logic/tests, and open a PR.
argument-hint: [schema-file.yml ...]
---

Run from inside a local `ui-myfinance` checkout (`Maersk-Global/ui-myfinance`).

## Steps

1. **Sanity check.** Confirm the current directory looks like `ui-myfinance` (`schemas/` and
   `package.json` exist at the repo root — `git remote -v` or `ls` is enough to check). If not,
   stop and tell the user to `cd` into their `ui-myfinance` checkout first.

2. **Resolve schema file(s).** Arguments: `$ARGUMENTS`. If empty, read
   `${CLAUDE_PLUGIN_ROOT}/scripts/myfinance-schema-map.tsv` (column 2 = valid filenames) and ask
   the user which schema(s) to sync.

3. **Prep.** Run:
   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/prep-myfinance-sync.sh" <schema-file> [<schema-file> ...]
   ```
   This fetches each file from the org-private `API-JSON-Schema-Definitions` repo and writes it
   into `schemas/`. If it errors (unknown filename, clone failure), surface the error verbatim
   and stop — do not guess at a fix.

   If the output's `CHANGED SCHEMAS` section is empty (`(none — ...)`), tell the user everything
   is already in sync and stop. No branch, no agent dispatch.

4. **Adapt.** Dispatch the `myfinance-sync:schema-adapter` subagent (foreground — you need its
   result before continuing) with the full prep output (`SOURCE_SHA` + the per-schema
   status/local/codegen lines) as its brief.

5. **Ship.** If the subagent completed without aborting:
   - `git checkout -b sync/myfinance-<short-source-sha>-<yyyymmdd>`
   - `git add -A && git commit -m "chore(sync): myfinance schema sync @ <short-source-sha>"`
     (one commit — this is a local, reviewed-before-push flow, not the old split-PR pipeline)
   - `git push -u origin HEAD`
   - `gh pr create` with title `chore(sync): myfinance schema sync @ <short-source-sha>` and the
     subagent's summary as the body (prepend the `SOURCE_SHA` for traceability back to the API
     repo commit).

   If the subagent aborted, do not create a branch or PR — report what blocked it and stop.
