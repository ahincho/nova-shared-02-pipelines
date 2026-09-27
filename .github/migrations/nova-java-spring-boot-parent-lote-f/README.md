# Migration bundle: nova-java-spring-boot-parent from DEPRECATED inline publish to release-please + tag-driven flow

**Source repo**: [ahincho/nova-java-14-spring-boot-parent](https://github.com/ahincho/nova-java-14-spring-boot-parent)
**Triggered by**: nova-devops Lote F (DEPRECATED workflow migration)
**Pinned SHA**: `300f6695c82197f50b2cfa0831bd146ed549a279` (refresh per nova-devops CHANGELOG.md Lote E)

## Why migrate

`nova-java-spring-boot-parent/.github/workflows/publish.yml` inlines a custom `mvn deploy` workflow with a hand-crafted `~/.m2/settings.xml` to work around the cross-repo read token limitation in the DEPRECATED `reusable-publish-maven.yml`. The new flow:

- Uses **release-please** to generate a release PR from Conventional Commits (no manual version bumps)
- On merge, release-please pushes a `vX.Y.Z` tag
- The tag triggers **publish-on-tag.yml** which deploys via `reusable-release-maven-publish.yml`
- Cross-repo reads (`nova-bom` from `pe.edu.nova.java:nova-bom:1.0.x`) are wired via the `NOVA_PACKAGES_READ_TOKEN` secret (this repo already has it ✓)
- Replaces the inline workaround (~50 lines of bash + settings.xml) with a 5-line `uses:` call
- Replaces floating `@main` refs with **SHA-pinned refs** (Lote E hardening)

## Files in this bundle

```
.github/
  workflows/
    release-please.yml       # NEW - creates/updates release PR on push to main
    publish-on-tag.yml       # NEW - triggered by tag push, deploys via reusable
.release-please-config.json  # NEW - release-please config (single package)
```

## Prerequisites

- The `NOVA_PACKAGES_READ_TOKEN` secret must already exist on this repo (it does ✓, per `gh api repos/.../actions/secrets`)
- No other changes needed

## How to apply

### Recommended: gh CLI bundle

```bash
gh repo clone ahincho/nova-java-14-spring-boot-parent nova-java-spring-boot-parent-tmp
cd nova-java-spring-boot-parent-tmp
git checkout -b lote-f-migration

git rm .github/workflows/publish.yml

# Copy files from the migration bundle
NOVA_DEVOPS=/path/to/nova-devops   # or clone it in parallel
cp $NOVA_DEVOPS/.github/migrations/nova-java-spring-boot-parent-lote-f/.github/workflows/release-please.yml \
   .github/workflows/
cp $NOVA_DEVOPS/.github/migrations/nova-java-spring-boot-parent-lote-f/.github/workflows/publish-on-tag.yml \
   .github/workflows/
cp $NOVA_DEVOPS/.github/migrations/nova-java-spring-boot-parent-lote-f/.release-please-config.json .

git add -A
git commit -m "Lote F: migrate from inline publish workaround to release-please + tag-driven flow

- Delete .github/workflows/publish.yml (was inlining mvn deploy + custom settings.xml
  to work around the cross-repo read token gap in DEPRECATED reusable-publish-maven)
- Add .github/workflows/release-please.yml: creates release PR on push to main
- Add .github/workflows/publish-on-tag.yml: triggered by tag push, deploys via
  reusable-release-maven-publish with NOVA_PACKAGES_READ_TOKEN for cross-repo reads
- Add .release-please-config.json: release-please config for single package

Refs: ahincho/nova-shared-02-pipelines CHANGELOG.md Lote F"

git push -u origin lote-f-migration
gh pr create --title "Lote F: migrate to release-please flow (remove inline workaround)" \
             --body "Replaces \`.github/workflows/publish.yml\` (inline mvn deploy + custom settings.xml workaround) with the standard nova-devops release-please + tag-driven flow. The cross-repo read of \`pe.edu.nova.java:nova-bom\` is now wired via \`NOVA_PACKAGES_READ_TOKEN\` (already present on this repo)."
```

### Manual copy (alternative)

Same as the nova-bom bundle — see `.github/migrations/nova-bom-lote-f/README.md`.

## After merge

```bash
git commit --allow-empty -m "feat: initial release via release-please (Lote F)"
git push
```

release-please opens a PR bumping `1.0.0 → 1.0.1`. Merge → tag `v1.0.1` → `publish-on-tag.yml` runs with `NOVA_PACKAGES_READ_TOKEN` → mvn deploy succeeds (resolves `nova-bom` cross-repo).

## Key differences from the deprecated inline workflow

| Aspect | DEPRECATED `publish.yml` | NEW `publish-on-tag.yml` |
|---|---|---|
| Trigger | `workflow_dispatch` only (manual) | `push: tags` (auto) + `workflow_dispatch` |
| Version bump | Manual edit of pom.xml | release-please on merge |
| Cross-repo reads | Custom `settings.xml` (50 lines) | `NOVA_PACKAGES_READ_TOKEN` via reusable |
| `@main` refs | Yes (Lote E risk) | SHA-pinned |
| Releases | Manual | Automatic via Conventional Commits |
| `package-name` config | Hardcoded | `packages.*.package-name` in release-please-config.json |

## Rollback

```bash
git revert <merge-commit-sha>   # reverts the migration commit
git push
# Old publish.yml returns; can still be invoked via workflow_dispatch
```

## Verification checklist

- [ ] `release-please.yml` + `publish-on-tag.yml` present in `.github/workflows/`
- [ ] `publish.yml` deleted
- [ ] `.release-please-config.json` at repo root
- [ ] All SHA pins = `300f6695c82197f50b2cfa0831bd146ed549a279`
- [ ] `NOVA_PACKAGES_READ_TOKEN` still present on repo (unchanged)
- [ ] PR passes CI (CodeQL)
- [ ] Push `feat:` commit → release-please opens release PR
- [ ] Merge release PR → tag pushed → `publish-on-tag.yml` succeeds