# Migration bundle: nova-bom from DEPRECATED publish flow to release-please + tag-driven flow

**Source repo**: [ahincho/nova-java-13-bom](https://github.com/ahincho/nova-java-13-bom)
**Triggered by**: nova-devops Lote F (DEPRECATED workflow migration)
**Pinned SHA**: `300f6695c82197f50b2cfa0831bd146ed549a279` (refresh per nova-devops CHANGELOG.md Lote E)

## Why migrate

`nova-bom/.github/workflows/publish.yml` calls `ahincho/nova-shared-02-pipelines/.github/workflows/reusable-publish-maven.yml@main`, marked **DEPRECATED as of 2026-07-21**. The new flow:

- Uses **release-please** to generate a release PR from Conventional Commits (no manual version bumps)
- On merge, release-please pushes a `vX.Y.Z` tag
- The tag triggers **publish-on-tag.yml** which deploys to GitHub Packages
- Replaces floating `@main` refs with **SHA-pinned refs** (Lote E hardening)

## Files in this bundle

```
.github/
  workflows/
    release-please.yml       # NEW - creates/updates release PR on push to main
    publish-on-tag.yml       # NEW - triggered by tag push, deploys all 4 poms
.release-please-config.json  # NEW - release-please config for 4-module BOM
```

## How to apply

### Option A: Manual copy (safest)

1. Clone the target repo: `git clone https://github.com/ahincho/nova-java-13-bom.git`
2. Create a branch: `git checkout -b lote-f-migration`
3. **Delete** the old file: `rm .github/workflows/publish.yml`
4. Copy the new files from this bundle into the target repo:
   ```bash
   # from the nova-devops repo root
   cp .github/migrations/nova-bom-lote-f/.github/workflows/release-please.yml \
      nova-bom/.github/workflows/
   cp .github/migrations/nova-bom-lote-f/.github/workflows/publish-on-tag.yml \
      nova-bom/.github/workflows/
   cp .github/migrations/nova-bom-lote-f/.release-please-config.json \
      nova-bom/
   ```
5. Commit: `git add -A && git commit -m "Migrate from DEPRECATED reusable-publish-maven to release-please + tag-driven flow"`
6. Push: `git push -u origin lote-f-migration`
7. Create PR via `gh pr create --title "Lote F: migrate to release-please flow" --body "..."`
8. Merge after approval

### Option B: gh CLI bundle (recommended)

```bash
gh repo clone ahincho/nova-java-13-bom nova-bom-tmp
cd nova-bom-tmp
git checkout -b lote-f-migration

# Copy files from the migration bundle
git checkout main -- .github/workflows/publish.yml  # capture the deleted file in the diff
git rm .github/workflows/publish.yml

# From the nova-devops repo (parallel clone or local checkout):
NOVA_DEVOPS=$(git rev-parse --show-toplevel)/../nova-devops   # adjust path
cp $NOVA_DEVOPS/.github/migrations/nova-bom-lote-f/.github/workflows/release-please.yml \
   .github/workflows/
cp $NOVA_DEVOPS/.github/migrations/nova-bom-lote-f/.github/workflows/publish-on-tag.yml \
   .github/workflows/
cp $NOVA_DEVOPS/.github/migrations/nova-bom-lote-f/.release-please-config.json .

git add -A
git commit -m "Lote F: migrate to release-please + tag-driven flow"
git push -u origin lote-f-migration
gh pr create --title "Lote F: migrate to release-please flow" \
             --body "$(cat $NOVA_DEVOPS/.github/migrations/nova-bom-lote-f/PR_BODY.md)"
```

## After merge

The first release will be created automatically by release-please on the next push to `main` (provided there are Conventional Commits since the last release). To force the very first release:

```bash
# Push an empty commit with feat: prefix to trigger release-please
git commit --allow-empty -m "feat: initial release via release-please (Lote F)"
git push
```

release-please will open a PR that bumps all 4 poms to `1.0.3` (or whichever is the next semver from current `1.0.2`). Merge the PR → tag `v1.0.3` is pushed → `publish-on-tag.yml` deploys.

## Rollback

If anything fails:

1. Revert the merge commit on `main`
2. The old `publish.yml` is gone from the new commits but git history retains it; restore via `git checkout <pre-merge-sha> -- .github/workflows/publish.yml && git commit`
3. Re-publish manually via workflow_dispatch on the old `publish.yml`

## Verification checklist

After applying:

- [ ] `release-please.yml` exists in `.github/workflows/`
- [ ] `publish-on-tag.yml` exists in `.github/workflows/`
- [ ] `publish.yml` is deleted
- [ ] `.release-please-config.json` exists at repo root
- [ ] All SHA pins in the new files reference `300f6695c82197f50b2cfa0831bd146ed549a279`
- [ ] `gh pr create` opens a PR; CI passes (CodeQL)
- [ ] After merge, push a `feat:` commit and verify release-please opens a release PR