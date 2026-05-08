You are working in the `ui-myfinance` repo. Your job is to adapt the UI (and tests) to match
the myfinance API schema changes already identified by CI. The org-private source repo is
`Maersk-Global/API-JSON-Schema-Definitions` — **do not clone it**; you do not have credentials
for it in this environment.

## Inputs (from the launching workflow)

- SCHEMA:                    ${SCHEMA}                    # `(all)` or one local schema filename under `schemas/`
- SPLIT_INTO_PR_PER_SCHEMA:  ${SPLIT_INTO_PR_PER_SCHEMA}  # `true` when CI will split your commits into one PR per Conventional Commit scope after the run (see Commit rules below)
- SELECTED_SCHEMAS:          ${SELECTED_SCHEMAS}          # JSON array of schema slugs for drifted files (e.g. `["invoices-v1","estatements"]`) — use these as commit scopes when split is enabled
- DRY_RUN:                   ${DRY_RUN}                   # `true` => report only (see Dry-run gate below)
- Triggered by:              ${ACTOR}
- CHANGED_FILES:             ${CHANGED_FILES}             # JSON array — each entry is `{ "remote": "<path in API repo>", "local": "<path in schemas/>", "status": "added|modified|deleted" }`
- SOURCE_SHA:                ${SOURCE_SHA}                # commit of the API repo CI synced from

## Hard rules

- **Never invent or simulate schema YAML or API content.** If you cannot complete a required
  step (missing file, codegen failure, etc.), stop, make a single commit with message
  `chore(sync): aborted due to <short reason>`, and state in the PR body that the run **aborted**
  and why. Do not fabricate files to “complete” the workflow.
- **Do not re-clone** `Maersk-Global/API-JSON-Schema-Definitions` or assume it is public.

## Branch and schema state (depends on DRY_RUN)

### When `DRY_RUN` is not `true` (normal run)

CI has already pushed a branch you are checked out on. **Tip of `HEAD` includes exactly one**
`chore(schemas): sync myfinance YAMLs from API repo @ …` commit that updates `schemas/`.
The previous schema tree is **`HEAD~1`**.

- To inspect what changed for a given file (if it still exists on `HEAD`):

```bash
git diff HEAD~1 HEAD -- schemas/<filename>
```

- For **deleted** schemas, the file is gone on `HEAD`; use `git show HEAD~1:schemas/<filename>`
  if you need the old content.

### When `DRY_RUN` is `true`

You are on the **default base branch** with **no** pre-applied schema sync commit. The working
tree’s `schemas/` are unchanged. **Do not** run codegen or change UI code. Produce only
`SYNC_REPORT.md` (see below) and commit **that file alone**.

## Schema slug reference (for `SPLIT_INTO_PR_PER_SCHEMA=true`)

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

## Schema → codegen script mapping

Use this table to determine which `npm run codegen-*` script to run for each
changed local schema file (skip entirely when `DRY_RUN=true`). If a changed file is not in this table, list it
under "Unmapped files" in the PR description.

| Local schema file                                      | npm script                           |
|--------------------------------------------------------|--------------------------------------|
| `schemas/myfinance-invoices-API.v1.yml`                | `codegen-invoices`                   |
| `schemas/myfinance-invoices-API.v2.yaml`               | `codegen-invoices-v2`                |
| `schemas/myfinance-submit-proof-of-payment-API.v1.yaml`| `codegen-proof-of-payment`           |
| `schemas/myfinance-export-documents-API.v1.yml`        | `codegen-export-documents`           |
| `schemas/myfinance-refund-request-API.v1.yaml`         | `codegen-refund-request`             |
| `schemas/myfinance-estatements-API.v1.yml`             | `codegen-estatements`                |
| `schemas/myfinance-workflows-API.v1.yaml`              | `codegen-workflows`                  |

## Steps

### 1. Trust the pre-computed CHANGED_FILES list

**Do NOT re-enumerate the API repo.** The workflow's `detect-drift` job
already diffed it against `schemas/` and gave you the exact file
list with statuses. Parse CHANGED_FILES as JSON and use it directly.

When `SCHEMA` is not `(all)`, CHANGED_FILES will contain only that one file (if it drifted).

### 2. Dry-run gate

If `DRY_RUN=true`: write a markdown report to `SYNC_REPORT.md` listing:

- The three file sets (ADDED / MODIFIED / DELETED) from CHANGED_FILES.
- The per-file codegen scripts you **would** run (normal run only).
- The UI changes you **would** apply (per the contract in step 5).

**Commit only `SYNC_REPORT.md`** as the single additional commit on this branch. Do not modify
`schemas/`, generated clients, application code, or tests. **Stop** after that commit.

### 3. Run codegen scripts (skip when `DRY_RUN=true`)

For each changed local schema file in CHANGED_FILES, look up the matching `npm run codegen-*`
command from the mapping table above and run it. If a file has no matching
script, leave a TODO comment in the PR description under "Unmapped files".

### 4. Adapt the UI to the schema diff (mandatory when not dry-run)

For each **modified** schema, compare against the parent commit:

```bash
git diff HEAD~1 HEAD -- schemas/<filename>
```

For **added** schemas, treat the whole file as new on `HEAD`. For **removed** schemas, remove
UI and test usage as in 4c.

Then apply the matching code changes:

#### 4a. Renamed properties (`oldName` → `newName`)

- Search the entire repo for the literal `oldName` in `.ts`, `.vue`,
  `.spec.ts`, `.cy.ts`, JSON mocks, fixtures, and storybook files.
- Rename in: TS interfaces / generated clients, store state / getters /
  actions, component props / refs / `computed` / `watch`, template bindings
  (`{{ }}`, `v-bind`, `v-model`, `:key`), table column `key`/`field`
  definitions, form field names, zod/yup schemas, validation rules, i18n
  keys if they mirror the property name, mock data, MSW handlers, Vitest
  fixtures, Cypress fixtures.
- Re-run `npm run typecheck` after each rename batch to catch missed
  references.

#### 4b. Added properties

- Always type them in the generated client / interface.
- Decide UI surfacing per property:
  * If the property is user-facing data (e.g. a new invoice column, a new
    customer attribute), surface it in the relevant table column, detail
    panel, form field, filter, or tooltip — match the conventions of the
    nearest sibling property.
  * If it is internal/metadata-only, type it but do not surface it.
- Document each surfacing decision in the PR description under
  "New properties surfaced".

#### 4c. Removed / deprecated properties

- Delete references in templates, components, stores, tests, mocks, fixtures.
- Confirm the UI still renders without the field (no broken bindings, no
  `undefined` in templates, no orphan i18n keys).

#### 4d. Type-only changes

(`string` → `string | null`, enum value added/removed, required → optional)

- Tighten or loosen TypeScript types accordingly.
- Add null-handling in templates and computed properties where needed.
- Update enum-driven UI (selects, badges, color maps) to handle new values.

#### 4e. Tests, mocks, fixtures

- Update Vitest mocks, MSW handlers, Cypress fixtures, and any hard-coded
  JSON in tests to match the new shape.
- Add a single test that exercises any newly-surfaced UI element.

#### Ambiguity escape hatch

If a change is genuinely ambiguous (e.g. you can't tell whether a new field
should be surfaced), add a `// TODO(cursor-sync):` comment, leave the type
but skip the UI surfacing, and call it out in the PR description under
"Decisions deferred to reviewer".

### 5. Verify (skip when `DRY_RUN=true`)

Run the project's lint / typecheck / unit tests:

```bash
npm run typecheck
npm run test:unit
```

Fix any breakage caused by your changes. If something is genuinely ambiguous,
leave a `// TODO(cursor-sync):` comment and call it out in the PR description.

### 6. Commit (when not dry-run)

Use logical chunks with Conventional Commits:

- **Do not** add another `chore(schemas): sync myfinance YAMLs from API repo @ …` commit — CI already pushed that on your branch.

**When `SPLIT_INTO_PR_PER_SCHEMA` is `true`**

Every commit subject **must** be `type(scope): description` where `type` is one of
`feat|fix|test|chore|refactor|docs|style|perf|ci|build` and `scope` is either:

- one of the slugs from **Schema slug reference** above (matching the schema file that commit primarily concerns), or
- `shared` for cross-cutting work.

Examples: `feat(invoices-v1): adapt invoices table to new fields`, `test(estatements): update fixtures`, `chore(shared): fix shared date util used by invoices and estatements`.

**When `SPLIT_INTO_PR_PER_SCHEMA` is not `true`** (single combined PR)

Use area-style scopes as before:

- `feat(<area>): adapt <area> to schema changes` (one per affected area)
- `test(<area>): update fixtures for schema changes` (if needed)

### 7. PR body

When Cursor opens the PR automatically (`autoCreatePR: true` — the default when split mode is off), include:

- Source commit SHA: `${SOURCE_SHA}`.
- The three file sets (ADDED / MODIFIED / DELETED).
- The codegen script invocations you ran (or "none — dry run" if applicable).
- **Scopes used** — list every Conventional Commit scope you used (`invoices-v1`, `shared`, etc.) so reviewers and automation can audit split mode.
- **Renamed properties** table: `oldName | newName | files touched`.
- **New properties surfaced** table: `property | UI surface(s) | rationale`.
- **Removed properties** list.
- Any unmapped files or `TODO(cursor-sync)` comments left in the diff.
- If the run aborted per Hard rules, say so prominently at the top.

When split mode is on, Cursor does not auto-create a single combined PR; CI opens an umbrella PR plus one PR per scope from your commits. Still assemble the sections above for reviewers (Cursor PR draft, commit message bodies, or any description field available). At minimum, list **Scopes used** so reviewers can confirm scopes match the slug table.
