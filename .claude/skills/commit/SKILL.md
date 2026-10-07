---
name: commit
description: Analyze the staged and unstaged changes, craft a Conventional Commits message for this project, run the pre-commit checks, and create the commit after the user confirms. Use when the user asks to commit their work.
disable-model-invocation: true
---

Analyze the staged and unstaged changes in this repository, then craft and create a git commit following the project's Conventional Commits convention.

## Commit format

```
type(scope): short description
```

**Types:** `feat`, `fix`, `refactor`, `test`, `docs`, `deps`, `chore`

**Scopes** (combine with spaces if multiple apply): `model`, `api`, `ui`, `db`, `pages`, `auth`, `config`

**Rules:**
- lowercase everything
- imperative mood ("add", not "added")
- no period at the end
- keep the subject line under 72 characters
- combine multiple scopes with a space: `fix(model api)` or `feat(ui pages)`
## Steps

1. Run `git status` and `git diff HEAD` to understand all changes (staged and unstaged)
2. Determine the best type and scope(s) from the changes
3. Show the proposed commit message to the user and ask for confirmation or edits
4. Run the checks below. If any fail, show the failure output and stop — do not create the commit until the user has fixed the issue or explicitly told you to proceed anyway
5. If confirmed and checks pass, stage all modified tracked files (`git add -u`) and create the commit
6. Show the resulting commit hash and message
7. Evaluate whether this is a good moment to cut a release tag (see below). If it is, tell the user — do NOT create the tag yourself.

## Tag / release suggestion

After committing, read `.claude/skills/release/SKILL.md` and apply its rules in **suggest-only** mode ("From `/commit`"): only nudge when the commit lands on `main` and a tag is warranted, propose the next version, and print the commands for the user to run. Never run `git tag`, `git push --tags`, or `gh release create` yourself unless the user explicitly asks.

## Pre-commit checks

Run the checks as described in `.claude/skills/ci/SKILL.md` (sequential, with timeouts, Vite-hang aware). For a small, localized change `quick` mode is enough before committing; say which mode you used. Skip the `Setup` step. A `TIMEOUT`/`BLOCKED` step is not a pass: report it and let the user decide whether to commit anyway.

Do NOT push. Do NOT amend existing commits. Do NOT add a `Co-Authored-By` trailer to the commit message.