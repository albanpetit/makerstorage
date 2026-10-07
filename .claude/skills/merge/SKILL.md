---
name: merge
description: Evaluate whether the current branch is ready to merge into main (or the branch given as argument), run the full check suite, and perform the merge plus an optional version tag after the user confirms. Use when the user asks to merge or ship a branch.
argument-hint: "[target-branch]"
disable-model-invocation: true
---

Target branch: `$ARGUMENTS` (defaults to `main` when empty).

Evaluate whether now is a good time to merge the current branch into `main` (or a branch passed as an argument), and if it is, do the merge — after running the full check suite, with a properly crafted merge message, and a new version tag if one is warranted.

This mirrors `/commit`'s "propose → confirm → check → execute" shape, but for the bigger, harder-to-reverse step of folding a finished branch back into `main`.

## Steps

1. Gather state:
- `git status` — the working tree must be clean (no staged/unstaged/untracked changes that matter). If not, stop and point the user at `/commit` (or ask them to stash) first.
- `git branch --show-current` — if this is already the target branch, there's nothing to merge; stop.
- `git fetch origin --quiet`, then compare local target vs `origin/<target>`. If local `<target>` is behind, fast-forward it (`git merge --ff-only origin/<target>` while on `<target>`) before evaluating anything else.
- `git log <target>..HEAD --oneline` (what the branch adds) and `git log HEAD..<target> --oneline` (what target has that the branch doesn't). If the branch adds nothing, stop — nothing to merge.

2. Check mergeability without mutating anything: diff the merge-base against both tips (e.g. `git merge-tree "$(git merge-base <target> HEAD)" <target> HEAD`) to see whether a real merge would conflict. If `<target>` has diverged and would conflict, stop and report exactly which files conflict. Do not attempt to auto-resolve — recommend the user rebase the branch onto `<target>` or resolve manually, then re-run this command.

3. Run the **full** check suite as described in `.claude/skills/ci/SKILL.md` (not quick mode) on the current branch. Additionally run `npm run check` against `<target>` (e.g. via `git worktree`) and compare error counts: only treat type errors as a blocker if the branch introduces *new* ones; call out pre-existing failures without letting them block the merge. System tests may be skipped with a note when Selenium isn't reachable. A step reported as `TIMEOUT`/`BLOCKED` (e.g. the Vite test-build hang) is not green — surface it and let the user decide.

If anything genuinely fails, stop, show the failure output, and do not merge — even if asked to "just merge it anyway." Surface the failure and let the user decide.

4. Decide the merge strategy:
- **Fast-forward possible** (`<target>` is an ancestor of `HEAD`): plan `git merge --ff-only`. This is the common case for a solo feature branch — no merge commit gets created, so no merge message is needed. Say so explicitly.
- **Not fast-forward, but non-conflicting**: plan a real merge commit and draft its message (see format below).

5. Summarize what's actually shipping — turn `git log <target>..HEAD --oneline` into a short human summary, not just the raw log. Show the user:
- The readiness checklist (checks passed, no conflicts, clean tree)
- The merge strategy, and the drafted merge commit message if one applies
- Whether a version tag looks warranted and the proposed version (see Tag section)

Ask for confirmation before touching anything.

6. On confirmation: switch to `<target>` and perform the merge. If a tag was agreed on, create it now (`git tag -a vX.Y.Z -m "vX.Y.Z"`) pointing at the new tip.

7. Ask **separately** whether to push `<target>` (and the tag, if any) to `origin`. Pushing is shared-state and hard to reverse — never push without an explicit go-ahead in the current turn, regardless of what was confirmed in step 5.

8. Report the resulting commit(s) and tag. Ask whether to delete the now-merged local branch — never delete it, and never touch the remote branch, without being asked.

## What "good timing" means

Don't merge just because the checks pass. Also weigh:
- Does the branch read as a finished, coherent unit of work (not something visibly mid-flight — half-implemented feature, commit messages like "wip"/"fixup"/"tmp")?
- Is `<target>` unlikely to be actively worked on by someone else right now (check for very recent commits on `<target>` that might indicate concurrent work)?
- Are there other local branches that look like they were meant to land before this one?

If any of this is unclear or borderline, say so and ask rather than guessing.

## Merge commit message format (non-fast-forward only)

```
Merge branch '<branch>' into <target>

<2-4 sentence summary of what the branch actually adds/fixes, written for
someone skimming `git log`, not a recap of every intermediate commit.>
```

## Tag / release

Read `.claude/skills/release/SKILL.md` and apply its rules to the commits the merge brings into `<target>` ("From `/merge`" mode). Unlike `/commit`, this command *does* create the tag locally when the user confirms it in step 5 — but pushing it is still gated by the separate push confirmation in step 7.

## Guardrails

- Never force-push. Never `git reset --hard` on `<target>`. Never auto-resolve a conflict — stop and report it instead.
- Never push (branch or tag) without an explicit go-ahead in the current turn.
- Never delete a local or remote branch without being asked.
- If the check suite fails, stop. A red build is a reason not to merge, not an obstacle to route around.