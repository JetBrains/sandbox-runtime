---
name: sync-upstream
description: Use when bringing a new anthropics/sandbox-runtime release into this JetBrains fork, resolving conflicts of an upstream merge, backporting an unreleased upstream fix, or repairing a sync that was squashed or rebased. Not for cutting a JetBrains release or for ordinary fork changes; both are covered by docs/jetbrains-build.md.
---

# Sync the fork with upstream

`main` is upstream [`anthropics/sandbox-runtime`](https://github.com/anthropics/sandbox-runtime) plus the JetBrains delta described in `MODIFICATIONS`. Every shipped build's source must stay reachable from `main` (Apache-2.0 §4(b)), so history is never rewritten: upstream releases come in as merge commits, and JetBrains changes land as squash-merged PRs.

## Rules

- Merge upstream **release tags** (`vX.Y.Z`), never `upstream/main` or single upstream commits. The exception is a backport (see below).
- One sync PR per upstream tag, from a branch `jb/merge-upstream-vX.Y.Z` off `origin/main`. It contains the merge plus only the edits that the merge requires. Unrelated fork changes go in their own PRs.
- Merge the sync PR with **Create a merge commit** (`gh pr merge --merge`), never squash or rebase. A squashed sync loses upstream's ancestry, so the next sync re-conflicts on everything and `scripts/check-modifications.sh` fails on `main`.
- Never rebase, amend or force-push a sync branch after the merge commit exists. To pick up a newer `main`, merge `origin/main` into the sync branch.
- Never stack a squash-merged PR on top of an open sync PR. Wait until the sync has landed and branch off `main`.
- Never force-push or revert on `main` to undo a sync. Fix forward with a new PR.
- When to sync: right away for upstream security fixes (check the [advisories](https://github.com/anthropics/sandbox-runtime/security/advisories)), when Junie needs an upstream fix or feature, and otherwise about once per upstream release. Skipping intermediate tags is fine. Merge the newest tag.
- Opening, merging and tagging are shared-repository actions. Do them only when the task asks for them.

## Procedure

1. Prepare the clone once: `git remote add upstream https://github.com/anthropics/sandbox-runtime.git` and `git config rerere.enabled true`, so conflict resolutions replay on later syncs.
2. Pick the tag: `git fetch origin && git fetch upstream --tags`, then `gh release list -R anthropics/sandbox-runtime --limit 5`. The current base is the `Upstream base:` line in `MODIFICATIONS`. `git merge-base --is-ancestor vX.Y.Z origin/main` succeeding means that tag is already merged.
3. Read what changes: run `git log --oneline --no-merges <base tag>..vX.Y.Z` and `git diff <base tag> vX.Y.Z --stat`. Look closer at:
   - `src/sandbox/*-sandbox-utils.ts`, `sandbox-config.ts`, `sandbox-manager.ts` and `src/cli.ts`: this is where the delta lives.
   - `dependencies` in `package.json`: each new runtime package needs a license review.
   - The Bun and Node pins in `.github/workflows/integration-tests.yml`.
4. Merge: `git switch -c jb/merge-upstream-vX.Y.Z origin/main`, then `git merge --no-ff vX.Y.Z -m "chore: merge upstream vX.Y.Z"`.
5. Resolve conflicts:
   - `.github/workflows/release.yml`, `.github/workflows/integration-tests.yml`, `package.json` and `package-lock.json` take upstream's version (`git checkout --theirs <path>`). The fork never changes them, and `package.json` `version` is never bumped.
   - In other upstream files, keep upstream's code and re-apply the delta on top as additive, opt-in code. Never drop upstream behavior to keep ours.
   - If upstream now does what one of our changes did, take upstream's version and remove that change from the fork.
   - JetBrains-only files (listed at the end of `docs/jetbrains-build.md`) keep ours.
6. Update in the same PR:
   - `MODIFICATIONS`: set `Upstream base: vX.Y.Z (<git rev-parse 'vX.Y.Z^{commit}'>)`. Regenerate the file list from `git diff --name-only --diff-filter=a vX.Y.Z` (the check prints the expected list). Edit or delete each `Modification:` paragraph that the merge made inaccurate.
   - `JB_VERSION`: `X.Y.Z-jb.1`.
   - If upstream's Bun or Node pin changed, set the same versions in `release-junie.yml` and `jetbrains-checks.yml`.
   - If the bundle gained or lost a package, update `PACKAGES` in `scripts/collect-third-party-licenses.sh` and the `THIRD-PARTY` row in `docs/jetbrains-build.md`, after checking the license: no copyleft without legal sign-off, and record the elected license for dual-licensed packages.
   - Fix version numbers and file names that went stale in `docs/jetbrains-build.md`.
7. Verify locally with the pinned Bun (older Bun versions fail the TLS and proxy tests):
   - `npm ci`, then `npm run build`, `npm run typecheck`, `npm run lint:check` and `bun test`
   - `scripts/check-modifications.sh`
   - `scripts/collect-third-party-licenses.sh`
8. Open the PR titled `chore: merge upstream vX.Y.Z`. Fill in the description:
   - **Why**: the upstream changes Junie needs, and any advisories it fixes.
   - **What**: what upstream changed, the conflicts and how they were resolved, and which delta changed or went away.
   - **Validation**: what actually ran.
   - **Notes**: "Merge with Create a merge commit".
9. Before merging, require green `Tests` on every platform and green `JetBrains checks`. Also do a release dry run with `gh workflow run release-junie.yml --ref jb/merge-upstream-vX.Y.Z`: it builds and smoke-tests all four binaries and skips publishing.
10. After the merge commit lands, confirm `git merge-base --is-ancestor vX.Y.Z origin/main` and green `JetBrains checks` on `main`. Then cut `jb-vX.Y.Z-jb.1` as described in "Cutting a release" in `docs/jetbrains-build.md`. Bump the pinned version and SHA-256 digests in Junie's packaging (see its `docs/sandbox-srt-bundling.md`) only after the release is published.

## Backporting an unreleased upstream fix

Use this only when a needed fix, usually a security fix, is on `upstream/main` but not yet tagged.

- Apply it with `git cherry-pick -x <sha>` in a normal squash-merged PR.
- Add a `Modification:` paragraph that names the upstream commit. Also bump the `-jb.<n>` suffix of `JB_VERSION`, because the upstream base stays the same.
- At the next sync, the tag brings the same change. Resolve it to upstream's version and delete the paragraph.

## Repairing a squashed or rebased sync

`check-modifications.sh` fails on `main` because the `Upstream base` tag is no longer an ancestor of `main`, and `release-junie.yml` refuses to publish.

- Fix it forward from a new `jb/merge-upstream-vX.Y.Z` branch off `origin/main` by merging the same tag again: `git merge --no-ff vX.Y.Z`. The content is already on `main`, so this usually merges cleanly. Resolve any remaining conflicts to `main`'s side.
- Merge that PR with a merge commit. Do not revert the squashed commit and do not force-push.
