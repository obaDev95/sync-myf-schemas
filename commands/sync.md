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
   This fetches `origin` fresh, resolves the remote default branch, fetches each named file from
   the org-private `API-JSON-Schema-Definitions` repo, and diffs it against `origin/<default>` —
   **never the local working tree**, so a stale local checkout can't re-surface schema changes
   that are already merged upstream. If it errors (unknown filename, clone failure, dirty working
   tree), surface the error verbatim and stop — do not guess at a fix, and do not `git stash` or
   force anything on the user's behalf.

   If the output's `CHANGED SCHEMAS` section is `(none — ...)`, tell the user everything is
   already in sync with `origin/<default>` and stop. No agent dispatch.

   Otherwise, the script has already created and checked out the sync branch reported as
   `BRANCH:` in its output — cut fresh from `origin/<default>` — and written the drifted schema
   file(s) into `schemas/`.

4. **Adapt.** Dispatch the `myfinance-sync:schema-adapter` subagent (foreground — you need its
   result before continuing) with the full prep output (`SOURCE_SHA`, `BRANCH`, and the
   per-schema status/local/codegen lines) as its brief.

5. **Ship.** If the subagent completed without aborting, on the `BRANCH` prep already checked
   out:
   - `git add -A && git commit -m "chore(sync): myfinance schema sync @ <short-source-sha>"`
     (one commit — this is a local, reviewed-before-push flow, not the old split-PR pipeline)
   - `git push -u origin HEAD`
   - `gh pr create` with title `chore(sync): myfinance schema sync @ <short-source-sha>` and the
     subagent's summary as the body (prepend the `SOURCE_SHA` for traceability back to the API
     repo commit).

   If the subagent aborted, do not commit or open a PR — report what blocked it and stop. The
   sync branch prep created is left in place so the user can inspect it or clean it up manually.
