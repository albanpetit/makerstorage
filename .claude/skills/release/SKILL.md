---
name: release
description: Decide whether a new SemVer version tag is warranted for Makerstorage, compute the next version from the commits since the last tag, and (on confirmation) create the annotated tag and GitHub release. Use when the user asks to cut a release, tag a version, or whether it's time to release.
argument-hint: "[version]"
disable-model-invocation: true
---

This is the single source of truth for versioning rules. `/commit` and `/merge` read this file instead of carrying their own copy.

`$ARGUMENTS` may contain an explicit version (e.g. `v0.8.0`); if so, skip the computation in step 3 but still sanity-check it against the commit range and warn if it doesn't match SemVer expectations.

## 1. Gather context

- Latest tag: `git describe --tags --abbrev=0 --match "v*" 2>/dev/null` (empty if none exists).
- Commits since it: `git log <lasttag>..main --oneline` (or all of `main` if there's no tag).
- Current branch: `git branch --show-current`. Tags are only ever cut from `main` (trunk-based flow, see `CONTRIBUTING.md`). If you're not on `main`, stop and say so.

## 2. Is a tag warranted?

Yes when the range contains at least one of:
- a commit that completes a **user-facing feature or milestone** (a `feat` that finishes a coherent chunk of work);
- several accumulated `feat`/`fix` commits with nothing released;
- a single notable `fix`/`perf` with user impact that deserves a patch release on its own.

No when the range is purely `test`, `docs`, `chore`, `refactor`, `deps`, or visibly work-in-progress. Say why and stop.

## 3. Next version (SemVer against the latest tag)

- any `feat` in the range → bump **MINOR** (`v0.7.0` → `v0.8.0`)
- only `fix`/`perf` → bump **PATCH** (`v0.7.0` → `v0.7.1`)
- breaking change while still `0.x` → bump **MINOR** (don't bump MAJOR until the app is declared stable)
- no tags yet → `v0.1.0`

## 4. Propose, then act only on confirmation

Show the user: last tag, proposed version, and a 3–6 bullet human summary of what's shipping (grouped Features / Fixes — not the raw log).

Then, depending on who called this:
- **From `/commit`** → only *suggest*. Print the commands for the user to run and do nothing else:
  ```
  git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z
  gh release create vX.Y.Z --generate-notes --title "vX.Y.Z"
  ```
- **From `/merge` or invoked directly** → on explicit confirmation, create the tag locally: `git tag -a vX.Y.Z -m "vX.Y.Z"`.
  Pushing the tag (`git push origin vX.Y.Z`) and creating the GitHub release (`gh release create … --generate-notes`) are **separate, shared-state actions**: ask again and only run them on an explicit go-ahead in the current turn.

## Guardrails

- Never move, delete, or re-point an existing tag.
- Never tag a commit that isn't on `main`.
- Never tag when the last `/ci` run on that commit wasn't green (`TIMEOUT`/`BLOCKED` steps count as not green — say so and let the user decide).
