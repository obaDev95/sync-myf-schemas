You are working in the `ui-myfinance` repo. Your job is to bring `schemas/` back in sync
with the latest myfinance YAMLs in the public repo
`Maersk-Global/API-JSON-Schema-Definitions` and adapt the UI code to match.

## Inputs (from the launching workflow)

- ONLY filter:    ${ONLY}            # empty = all myfinance files
- DRY_RUN:        ${DRY_RUN}          # "true" => report only, no commits
- Triggered by:   ${ACTOR}
- CHANGED_FILES:  ${CHANGED_FILES}   # JSON array — each entry is { "remote": "<path in public repo>", "local": "<path in schemas/>", "status": "added|modified|deleted" }
- SOURCE_SHA:     ${SOURCE_SHA}      # commit of the public repo you are syncing from

## Schema → codegen script mapping

Use this table to determine which `npm run codegen-*` script to run for each
changed local schema file. If a changed file is not in this table, list it
under "Unmapped files" in the PR description.

| Local schema file                                      | npm script                           |
|--------------------------------------------------------|--------------------------------------|
| `schemas/myfinance-invoices-API.v1.yml`                | `codegen-invoices`                   |
| `schemas/myfinance-invoices-API.v2.yaml`               | `codegen-invoices-v2`                |
| `schemas/myfinance-submit-proof-of-payment-API.v1.yaml`| `codegen-proof-of-payment`           |
| `schemas/PNC_PaymentAvailability-API.v1.yaml`          | `codegen-payment-availability`       |
| `schemas/PNC_BankProfiles-API.v1.yaml`                 | `codegen-bank-profiles`              |
| `schemas/myfinance-export-documents-API.v1.yml`        | `codegen-export-documents`           |
| `schemas/myfinance-refund-request-API.v1.yaml`         | `codegen-refund-request`             |
| `schemas/myfinance-estatements-API.v1.yml`             | `codegen-estatements`                |
| `schemas/myfinance-workflows-API.v1.yaml`              | `codegen-workflows`                  |

## Steps

### 1. Clone the public source pinned to SOURCE_SHA

```bash
git clone https://github.com/Maersk-Global/API-JSON-Schema-Definitions /tmp/api-src
git -C /tmp/api-src checkout ${SOURCE_SHA}
```

### 2. Trust the pre-computed CHANGED_FILES list

**Do NOT re-enumerate the public repo.** The workflow's `detect-drift` job
already diffed the public repo against `schemas/` and gave you the exact file
list with statuses. Parse CHANGED_FILES as JSON and use it directly.

### 3. Dry-run gate

If `DRY_RUN=true`: write a markdown report to `SYNC_REPORT.md` listing:
- The three file sets (ADDED / MODIFIED / DELETED).
- The per-file codegen scripts you would run.
- The UI changes you would apply (per the contract in step 6).

Do NOT commit schema or UI changes; commit only the report.

### 4. Copy schemas

For each file with status `added` or `modified`: copy the remote file into
`schemas/<local filename>`.
For each file with status `deleted`: remove the local schema file.

### 5. Run codegen scripts

For each changed local schema file, look up the matching `npm run codegen-*`
command from the mapping table above and run it. If a file has no matching
script, leave a TODO comment in the PR description under "Unmapped files".

### 6. Adapt the UI to the schema diff (mandatory)

For each MODIFIED schema, run a structural diff against the previous version:

```bash
git diff HEAD -- schemas/<filename>
```

Then apply the matching code changes:

#### 6a. Renamed properties (`oldName` → `newName`)

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

#### 6b. Added properties

- Always type them in the generated client / interface.
- Decide UI surfacing per property:
  * If the property is user-facing data (e.g. a new invoice column, a new
    customer attribute), surface it in the relevant table column, detail
    panel, form field, filter, or tooltip — match the conventions of the
    nearest sibling property.
  * If it is internal/metadata-only, type it but do not surface it.
- Document each surfacing decision in the PR description under
  "New properties surfaced".

#### 6c. Removed / deprecated properties

- Delete references in templates, components, stores, tests, mocks, fixtures.
- Confirm the UI still renders without the field (no broken bindings, no
  `undefined` in templates, no orphan i18n keys).

#### 6d. Type-only changes

(`string` → `string | null`, enum value added/removed, required → optional)

- Tighten or loosen TypeScript types accordingly.
- Add null-handling in templates and computed properties where needed.
- Update enum-driven UI (selects, badges, color maps) to handle new values.

#### 6e. Tests, mocks, fixtures

- Update Vitest mocks, MSW handlers, Cypress fixtures, and any hard-coded
  JSON in tests to match the new shape.
- Add a single test that exercises any newly-surfaced UI element.

#### Ambiguity escape hatch

If a change is genuinely ambiguous (e.g. you can't tell whether a new field
should be surfaced), add a `// TODO(cursor-sync):` comment, leave the type
but skip the UI surfacing, and call it out in the PR description under
"Decisions deferred to reviewer".

### 7. Verify

Run the project's lint / typecheck / unit tests:

```bash
npm run typecheck
npm run test:unit
```

Fix any breakage caused by your changes. If something is genuinely ambiguous,
leave a `// TODO(cursor-sync):` comment and call it out in the PR description.

### 8. Commit

Use logical chunks with Conventional Commits:

- `chore(schemas): sync myfinance YAMLs from API repo @ ${SOURCE_SHA}`
- `feat(<area>): adapt <area> to schema changes` (one per affected area)
- `test(<area>): update fixtures for schema changes` (if needed)

### 9. PR body

The PR will be opened automatically by the API (`autoCreatePR: true`). In the
PR body, include:

- Source commit SHA: `${SOURCE_SHA}`.
- The three file sets (ADDED / MODIFIED / DELETED).
- The codegen script invocations you ran.
- **Renamed properties** table: `oldName | newName | files touched`.
- **New properties surfaced** table: `property | UI surface(s) | rationale`.
- **Removed properties** list.
- Any unmapped files or `TODO(cursor-sync)` comments left in the diff.
