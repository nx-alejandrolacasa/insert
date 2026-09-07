---
name: ship-it
description: Commit, push and cut a GitHub release for the current work on Insert. Use when the user says "ship it" or an equivalent ("looks good, ship it", "let's release this", "cut a release") in this repo. Decides patch vs minor from the actual changes, bumps build.sh's version fallback, tags, pushes, and lets CI build the DMG and publish the release.
---

# Ship it

Insert releases by pushing a `vX.Y.Z` tag — `.github/workflows/release.yml` then
builds, packages the DMG and publishes the GitHub Release. This skill is the
whole path from "the change is good" to a tag on `origin`.

## Steps

1. **Make sure the work is committed.** If there are unstaged or uncommitted
   changes, commit them first with a normal descriptive message (see the
   top-level commit-message guidance — why, not what, 1-2 sentences). Don't
   fold the version bump into that commit; it's its own commit, see step 4.

2. **Find the last release.** `git describe --tags --abbrev=0` (or
   `git tag --sort=-v:refname | head -1`) for the last `vX.Y.Z`, then
   `git log --oneline <lasttag>..HEAD` for what's shipping.

3. **Decide patch or minor from those commits**, not from a fixed rule — read
   them the way the project's own history does it (`git log --oneline
   v0.19.0..v0.19.1` vs `v0.19.0..v0.20.0` are worth diffing again if this
   judgment call gets harder). In practice:
   - **Patch** (`Z+1`): a single narrow correctness fix, or a small change with
     no new user-visible capability and no change to an existing UI's
     placement/behavior.
   - **Minor** (`Y+1`, `Z→0`): anything that changes what a user sees or how a
     control behaves — a redesign, a moved or reworked control, a new setting,
     a new capability — or more than one such commit since the last tag.
   - This project has never cut a major version; don't start unless the user
     asks for one explicitly.
   - If it's ambiguous, say what you're leaning toward and why in one line
     rather than silently picking — this is a judgment call, not arithmetic.

4. **Bump the version fallback.** Edit `build.sh`'s
   `VERSION="${INSERT_VERSION:-X.Y.Z}"` line to the new version. Commit it
   alone, message in the estabished style: `Bump the local version fallback to
   X.Y.Z`.

5. **Tag and push, together.** The tag must point at the bump commit:
   ```
   git tag vX.Y.Z
   git push origin main
   git push origin vX.Y.Z
   ```
   Pushing the tag is what triggers CI — nothing else here builds or releases
   anything.

6. **Report, don't wait.** Tell the user the version, why patch/minor, and the
   Actions run URL (`https://github.com/nx-alejandrolacasa/insert/actions`) or
   `gh run list --workflow=release.yml -L1` if `gh` is available. Don't poll
   for the build to finish — it's a few minutes on a `macos-26` runner and the
   user can check.

## Don't

- Don't invent a major version bump.
- Don't skip the separate bump commit and hand-edit the version into a feature
  commit — every prior release keeps it isolated, which is what makes
  `git log --oneline` read as one bump per release.
- Don't force-push or re-tag an existing version.
