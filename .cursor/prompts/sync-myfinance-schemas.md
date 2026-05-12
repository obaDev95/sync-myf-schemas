You are working in the `ui-myfinance` repo. Your job is to adapt the UI (and tests) to match
the myfinance API schema changes already identified by CI. The org-private source repo is
`Maersk-Global/API-JSON-Schema-Definitions` — **do not clone it**; you do not have credentials
for it in this environment.

## Inputs (from the launching workflow)

- SCHEMA:                    ${SCHEMA}                    # `(all)` or one local schema filename under `schemas/`
- SPLIT_INTO_PR_PER_SCHEMA:  ${SPLIT_INTO_PR_PER_SCHEMA}  # `true` when CI will split your commits into one PR per Conventional Commit scope after the run (see Commit rules below)
- SELECTED_SCHEMAS:          ${SELECTED_SCHEMAS}          # JSON array of schema slugs for drifted files (e.g. `["invoices-v1","estatements"]`) — use these as commit scopes when split is enabled
- Triggered by:              ${ACTOR}
- CHANGED_FILES:             ${CHANGED_FILES}             # JSON array — each entry is `{ "remote": "<path in API repo>", "local": "<path in schemas/>", "status": "added|modified|deleted" }`
- SOURCE_SHA:                ${SOURCE_SHA}                # commit of the API repo CI synced from

## Hard rules

- **Never invent or simulate schema YAML or API content.** If you cannot complete a required
  step (missing file, unexpected diff shape, etc.), stop, make a single commit with message
  `chore(sync): aborted due to <short reason>`, and state in the PR body that the run **aborted**
  and why. Do not fabricate files to "complete" the workflow.
- **Do not re-clone** `Maersk-Global/API-JSON-Schema-Definitions` or assume it is public.
- **Never run `npm` commands of any kind** — no `npm ci`, no `npm install`, no `npm run codegen-*`,
  no `npm run typecheck`, no `npm run test:unit`. You have **no registry credentials** in this
  environment by design (registry auth lives only on the GitHub Actions runner). CI has already
  regenerated the clients before you started and will run typecheck + unit tests on your final
  branch after you push. Lean on `grep` / cross-file search to catch missed references.
- **Never create, read, or reference an `.npmrc` or any other credential-bearing file.** If you
  encounter one in the working tree, do not stage it, do not echo it, do not mention its
  contents in any commit message or PR body.

## Branch and schema state

CI has already pushed a branch you are checked out on. **Tip of `HEAD` includes two automated
commits:**

- `HEAD`   — `chore(codegen): regenerate clients for myfinance schemas @ …` (regenerated client/types output)
- `HEAD~1` — `chore(schemas): sync myfinance YAMLs from API repo @ …` (updated `schemas/`)
- `HEAD~2` — the pre-sync baseline (previous schema + previous generated client)

To inspect what changed for a given schema YAML:

```bash
git diff HEAD~2 HEAD~1 -- schemas/<filename>
```

To inspect what regenerated client output looks like vs. the previous state:

```bash
git diff HEAD~1 HEAD
```

For **deleted** schemas, the file is gone on `HEAD`; use `git show HEAD~2:schemas/<filename>`
if you need the old content. Build on top of `HEAD` — never re-run codegen (Hard rules).

## Schema slug reference (for `SPLIT_INTO_PR_PER_SCHEMA=true`)

> Source of truth: [`scripts/myfinance-schema-map.tsv`](../../scripts/myfinance-schema-map.tsv) in the automation repo. The table below is a mirror; if it ever disagrees with the TSV, trust the TSV.

Use these **exact** scopes in commit messages when split mode is on. They must match
`SELECTED_SCHEMAS` for the files you touch in each commit.

| Local schema file (under `schemas/`) | Slug |
|--------------------------------------|------|
| `myfinance-invoices-API.v1.yml` | `invoices-v1` |
| `myfinance-invoices-API.v2.yaml` | `invoices-v2` |
| `myfinance-submit-proof-of-payment-API.v1.yaml` | `submit-proof-of-payment` |
| `myfinance-export-documents-API.v1.yml` | `export-documents` |
| `myfinance-refund-request-API.v1.yaml` | `refund-request` |
| `myfinance-estatements-API.v1.yml` | `estatements` |
| `myfinance-workflows-API.v1.yaml` | `workflows` |

Cross-cutting changes (shared util, barrel file, or a single edit that clearly serves more than one schema slug above) must use scope **`shared`**: `chore(shared): …` or `feat(shared): …` as appropriate.

## Schema → codegen script mapping (reference)

CI runs the matching `npm run codegen-*` script for every drifted schema on the GitHub-hosted
runner before you start, using credentials you do not have access to. The regenerated output
is already on `HEAD` as the `chore(codegen):` commit. Column 4 of [`scripts/myfinance-schema-map.tsv`](../../scripts/myfinance-schema-map.tsv) records which script produced which generated files; consult it if you need to attribute pieces of the `chore(codegen):` diff.

## Steps

### 1. Trust the pre-computed CHANGED_FILES list

**Do NOT re-enumerate the API repo.** The workflow's `detect-drift` job
already diffed it against `schemas/` and gave you the exact file
list with statuses. Parse CHANGED_FILES as JSON and use it directly.

When `SCHEMA` is not `(all)`, CHANGED_FILES will contain only that one file (if it drifted).

### 2. Codegen is done — confirm, don't re-run

CI has already executed every applicable `npm run codegen-*` script and committed the result
as the `chore(codegen):` commit at `HEAD`. **Do not run codegen yourself.** Confirm the
regenerated client is present by inspecting:

```bash
git log -1 --oneline HEAD
git diff --stat HEAD~1 HEAD
```

If the `chore(codegen):` commit is missing or empty, that is a CI bug — stop and follow the
abort rule (Hard rules). Do not attempt to compensate.

If a drifted schema was unmapped, CI will have emitted a `::warning::` in the workflow log;
list any such file under "Unmapped files" in the PR description.

### 3. Adapt the UI to the schema diff

For each **modified** schema, compare against the pre-sync baseline:

```bash
git diff HEAD~2 HEAD~1 -- schemas/<filename>
```

The regenerated client diff (`HEAD~1..HEAD`) is your reference for what the new types and
client surface look like — read it to see what API the UI now has to call.

For **added** schemas, treat the whole file as new on `HEAD~1`. For **removed** schemas, remove
UI and test usage as in 3c.

Then apply the matching code changes:

#### 3a. Renamed properties (`oldName` → `newName`)

- Search the entire repo for the literal `oldName` in `.ts`, `.vue`,
  `.spec.ts`, `.cy.ts`, JSON mocks, fixtures, and storybook files.
- Rename in: TS interfaces / generated clients, store state / getters /
  actions, component props / refs / `computed` / `watch`, template bindings
  (`{{ }}`, `v-bind`, `v-model`, `:key`), table column `key`/`field`
  definitions, form field names, zod/yup schemas, validation rules, i18n
  keys if they mirror the property name, mock data, MSW handlers, Vitest
  fixtures, Cypress fixtures.
- You cannot run `npm run typecheck` (no registry credentials). Use repeated
  cross-file `grep` for the old identifier to catch missed references;
  CI runs typecheck on your final branch and will surface any remaining hit.

#### 3b. Added properties

- Always type them in the generated client / interface.
- Decide UI surfacing per property:
  * If the property is user-facing data (e.g. a new invoice column, a new
    customer attribute), surface it in the relevant table column, detail
    panel, form field, filter, or tooltip — match the conventions of the
    nearest sibling property.
  * If it is internal/metadata-only, type it but do not surface it.
- Document each surfacing decision in the PR description under
  "New properties surfaced".

#### 3c. Removed / deprecated properties

- Delete references in templates, components, stores, tests, mocks, fixtures.
- Confirm the UI still renders without the field (no broken bindings, no
  `undefined` in templates, no orphan i18n keys).

#### 3d. Type-only changes

(`string` → `string | null`, enum value added/removed, required → optional)

- Tighten or loosen TypeScript types accordingly.
- Add null-handling in templates and computed properties where needed.
- Update enum-driven UI (selects, badges, color maps) to handle new values.

#### 3e. Tests, mocks, fixtures

- Update Vitest mocks, MSW handlers, Cypress fixtures, and any hard-coded
  JSON in tests to match the new shape.
- Add a single test that exercises any newly-surfaced UI element.

#### Ambiguity escape hatch

If a change is genuinely ambiguous (e.g. you can't tell whether a new field
should be surfaced), add a `// TODO(cursor-sync):` comment, leave the type
but skip the UI surfacing, and call it out in the PR description under
"Decisions deferred to reviewer".

### 4. Verification runs in CI — not here

You **must not** run `npm run typecheck` or `npm run test:unit` (no registry credentials).
After you push, the workflow's `verify-agent-output` job runs both on the GitHub-hosted runner
against your final branch and surfaces failures as PR checks. Reviewers see red CI for any
breakage. If you spot something genuinely ambiguous during your edits, leave a
`// TODO(cursor-sync):` comment and call it out in the PR description.

### 5. Commit

Use logical chunks with Conventional Commits:

- **Do not** add another `chore(schemas): …` or `chore(codegen): …` commit — CI already pushed both on your branch.

**When `SPLIT_INTO_PR_PER_SCHEMA` is `true`**

Every commit subject **must** be `type(scope): description` where `type` is one of
`feat|fix|test|chore|refactor|docs|style|perf|ci|build` and `scope` is either:

- one of the slugs from **Schema slug reference** above (matching the schema file that commit primarily concerns), or
- `shared` for cross-cutting work.

CI hard-fails the split job if any commit subject is missing a Conventional Commit scope, or if the scope is not in the allowed set (TSV slugs + `shared`). There is no silent fallback — surface ambiguity as `shared` or stop and abort per Hard rules.

Examples: `feat(invoices-v1): adapt invoices table to new fields`, `test(estatements): update fixtures`, `chore(shared): fix shared date util used by invoices and estatements`.

**When `SPLIT_INTO_PR_PER_SCHEMA` is not `true`** (single combined PR)

Use area-style scopes as before:

- `feat(<area>): adapt <area> to schema changes` (one per affected area)
- `test(<area>): update fixtures for schema changes` (if needed)

### 6. PR body

When Cursor opens the PR automatically (`autoCreatePR: true` — the default when split mode is off), include:

- Source commit SHA: `${SOURCE_SHA}`.
- The three file sets (ADDED / MODIFIED / DELETED).
- A note that codegen was run by CI on the runner (see the `chore(codegen):` commit on this branch).
- **Scopes used** — list every Conventional Commit scope you used (`invoices-v1`, `shared`, etc.) so reviewers and automation can audit split mode.
- **Renamed properties** table: `oldName | newName | files touched`.
- **New properties surfaced** table: `property | UI surface(s) | rationale`.
- **Removed properties** list.
- Any unmapped files or `TODO(cursor-sync)` comments left in the diff.
- If the run aborted per Hard rules, say so prominently at the top.

When split mode is on, Cursor does not auto-create a single combined PR; CI opens an umbrella PR plus one PR per scope from your commits. Still assemble the sections above for reviewers (Cursor PR draft, commit message bodies, or any description field available). At minimum, list **Scopes used** so reviewers can confirm scopes match the slug table.
