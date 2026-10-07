---
name: ci
description: Run Makerstorage's full check suite (rubocop, bundler-audit, brakeman, Rails tests, system tests, seeds, TypeScript) safely — sequentially, with timeouts, working around the known Vite test-build hang — and summarize what passed or failed. Use before declaring work done, before committing or merging, or when the user asks to run CI, the tests, or the checks.
argument-hint: "[quick]"
---

Run the project's checks the way `config/ci.rb` (`bin/ci`) does, but robustly enough that a hung step can't stall the session, then report a single summary.

`$ARGUMENTS` = `quick` → only run lint + the test files related to the current diff (see "Quick mode"). Anything else / empty → full run.

## Ground rules

- **Run steps one at a time, never in parallel.** All test processes share `storage/test.sqlite3`; two concurrent `bin/rails test` runs fail with `SQLite3::BusyException: database is locked`.
- **Wrap every step in `timeout`** (values below). A step that times out is reported as `TIMEOUT`, not as a pass.
- **Never kill processes with `pkill -f <pattern>` / `pgrep -f`** where the pattern also appears in your own command line — it matches (and kills) your own shell. Kill by explicit PID instead.
- Don't fix anything while running the checks. Collect results first, then report.

## Steps (full run)

1. **Lint** — `timeout 180 bin/rubocop`
2. **Gem audit** — `timeout 120 bin/bundler-audit`
3. **Brakeman** — `timeout 300 bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`
4. **Vite test build probe** — `RAILS_ENV=test timeout 240 bin/vite build`
   - The test env has `autoBuild: true` (`config/vite.json`), so every controller/integration test that renders a page triggers this build. In the dev container it has been observed to hang with no output.
   - If it **succeeds**: continue to step 5 normally.
   - If it **times out**: do NOT run `bin/rails test` as a whole (it would hang). Run only the non-rendering directories in step 5b and report controllers/integration/system as `BLOCKED (vite build hang)`.
5. **Rails tests**
   - a. Vite OK → `timeout 900 bin/rails test`
   - b. Vite blocked → for each of `test/models test/services test/jobs test/mailers test/initializers`: `PARALLEL_WORKERS=1 timeout 300 bin/rails test <dir>`
   - If a full run hangs, isolate it file by file: `PARALLEL_WORKERS=1 timeout 30 bin/rails test <file>` and report the file(s) that time out.
6. **System tests** — only if step 4 succeeded and Chrome/Selenium is reachable: `timeout 900 bin/rails test:system`. Otherwise mark `SKIPPED` with the reason (infra gap, not a code failure).
7. **Seeds** — `env RAILS_ENV=test timeout 180 bin/rails db:seed:replant`
8. **TypeScript** — `timeout 300 npm run check`. It has also been seen to hang in the container; a timeout is reported as `TIMEOUT`, not as a type error.

## Quick mode

- `bin/rubocop` on the changed Ruby files only (`git diff --name-only HEAD -- '*.rb'`).
- For every changed `app/models/x.rb` run `test/models/x_test.rb`; for `app/controllers/x_controller.rb` run `test/controllers/x_controller_test.rb`; for `app/services/**` run the matching `test/services/**` file — each with `PARALLEL_WORKERS=1 timeout 120`.
- Say clearly that this was a quick run and the full suite still has to pass before a merge.

## Report

End with one table, one row per step: `PASS` / `FAIL` / `TIMEOUT` / `BLOCKED` / `SKIPPED`, plus the test counts (`N runs, N assertions, N failures, N errors`) where available. For every `FAIL`, quote the relevant lines of output (failing test name + assertion/error), not the whole log. State plainly whether the suite is green; a run with `TIMEOUT` or `BLOCKED` steps is **not** green.
