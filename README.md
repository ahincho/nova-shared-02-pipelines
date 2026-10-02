# nova-devops

Centralized repository of reusable workflows and composite actions for GitHub Actions, powering the CI/CD pipelines of the `pe.edu.nova` Java library ecosystem and of Python projects managed with [uv](https://docs.astral.sh/uv/).

This repository provides a standardized CI/CD pipeline with dedicated variants for **Maven** and **Gradle KTS**, native dependency caching, security scanning (CodeQL, OWASP Dependency-Check, SonarCloud, SBOM), automated versioning via [release-please](https://github.com/googleapis/release-please), and tag-based publication to GitHub Packages. Python projects get a build pipeline (ruff, pytest) with uv, Python and dependency caching.

> All workflows and composite actions are referenced using **commit SHAs** (Lote Q, July 2026). Pinning to a branch (`@main`) or a SemVer tag (`@vX.Y.Z`) is **not supported** and breaks reproducibility. The canonical internal action SHA is `300f6695c82197f50b2cfa0831bd146ed549a279`. The Python pieces came later: pin them to `8e875e2a349c1853074c4990f2b9878295041194` or a newer commit.

## Table of Contents

- [Repository Layout](#repository-layout)
- [Branches and Versioning Policy](#branches-and-versioning-policy)
- [Available Reusable Workflows](#available-reusable-workflows)
  - [Build Pipelines](#build-pipelines)
  - [Quality and Security Pipelines](#quality-and-security-pipelines)
  - [Publish Pipelines](#publish-pipelines)
  - [Release Orchestration](#release-orchestration)
  - [Standalone Workflows](#standalone-workflows)
- [Available Composite Actions](#available-composite-actions)
- [Pester Test Suite](#pester-test-suite)
- [PowerShell Operator Scripts](#powershell-operator-scripts)
- [Migrations](#migrations)
- [Security Posture](#security-posture)
- [Required Secrets and Variables](#required-secrets-and-variables)
- [Consumer Repository Example](#consumer-repository-example)
- [Library Ecosystem](#library-ecosystem)
- [Branch Protection Rules](#branch-protection-rules)
- [Dependabot Configuration](#dependabot-configuration)

## Repository Layout

```
.github/
  workflows/                          # 18 reusable + standalone workflows
    codeql.yml                        # CodeQL static analysis
    codeql-watchdog.yml               # Fails while main has open CodeQL alerts (medium+)
    nvd-mirror-update.yml             # OWASP NVD mirror maintenance
    publish-on-tag.yml                # Local caller for tag-based publish
    reusable-build-gradle.yml         # Build + test + lint + javadoc (Gradle)
    reusable-build-maven.yml          # Build + test + lint + javadoc (Maven)
    reusable-build-matrix.yml         # Matrix build across Java/Gradle versions
    reusable-build-python.yml         # Lint + format check + tests (Python, uv)
    reusable-owasp-check.yml          # OWASP Dependency-Check (SCA)
    reusable-package-retention.yml    # Cleanup old SNAPSHOTs on GitHub Packages
    reusable-publish-gradle.yml       # DEPRECATED — use reusable-release-publish.yml
    reusable-publish-maven.yml        # DEPRECATED — use reusable-release-publish.yml
    reusable-release-maven-publish.yml # Maven tag-based release publish
    reusable-release-please.yml       # release-please orchestrator
    reusable-release-publish.yml      # Gradle tag-based release publish
    reusable-sbom.yml                 # CycloneDX SBOM generation
    reusable-sonarcloud-gradle.yml    # SonarCloud + JaCoCo (Gradle)
    reusable-sonarcloud-maven.yml     # SonarCloud + JaCoCo (Maven)
  actions/                            # 9 composite actions
    nova-gather-facts/
    nova-publish-aggregator/
    nova-resolve-token/
    nova-setup-gpg/
    nova-setup-java/
    nova-setup-node/
    nova-setup-python/
    nova-validate-build/
    nova-verify-publication/
  migrations/                         # Bundle migrations applied via gh CLI
    nova-bom-lote-f/
    nova-java-spring-boot-parent-lote-f/
tests/                                # Pester 5.7.1 test suite (243 tests)
scripts/                              # PowerShell operator scripts
  apply-nova-labels.ps1
  apply-nova-metadata.ps1
  rotate-nova-tokens.ps1
```

## Branches and Versioning Policy

| Branch | Protection | Purpose |
|---|---|---|
| `main` | Strict (1 review, enforce_admins, CodeQL required) | Production. All releases target this branch. |
| `dev` | Soft (1 review, no enforce_admins, CodeQL required) | Integration. Feature branches land here before `main`. |

**This repository does not use Semantic Versioning for workflows or composite actions.** The reference is always a **40-character commit SHA** (see Lote Q in CHANGELOG). The only tag in this repository is `nvd-mirror`, which is a binary data artifact (mirror of the OWASP NVD dataset) auto-updated by the `nvd-mirror-update.yml` workflow. It is not a SemVer release.

**Implication for consumers:** every library repository must reference this repository using a pinned commit SHA:

```yaml
uses: ahincho/nova-shared-02-pipelines/.github/workflows/reusable-XYZ.yml@300f6695c82197f50b2cfa0831bd146ed549a279
uses: ahincho/nova-shared-02-pipelines/.github/actions/nova-XYZ@300f6695c82197f50b2cfa0831bd146ed549a279
```

Pinning to `@main`, `@vX.Y.Z`, or a non-SHA ref is **out of scope** and breaks reproducibility guarantees.

## Available Reusable Workflows

All `reusable-*.yml` workflows are invoked via `workflow_call`. They are consumed by lightweight caller workflows in the consumer repository (typically `.github/workflows/ci.yml`).

### Build Pipelines

#### `reusable-build-maven.yml`
Compiles a Maven project, runs the test suite, enforces Checkstyle, and generates JavaDoc.

| Input | Type | Required | Default | Description |
|---|---|---|---|---|
| `java-version` | string | no | `'25'` | JDK version to use |

**Secrets required:** none.

**Artifacts produced:**

- `test-reports` — Surefire test reports
- `javadoc` — Generated JavaDoc HTML

**Pipeline steps:**

| Step | Command |
|---|---|
| Build and test | `mvn verify` |
| Lint (Checkstyle) | `mvn checkstyle:check` |
| JavaDoc | `mvn javadoc:javadoc` |

#### `reusable-build-gradle.yml`
Same purpose as the Maven variant, for Gradle KTS projects.

| Input | Type | Required | Default | Description |
|---|---|---|---|---|
| `java-version` | string | no | `'25'` | JDK version to use |

**Pipeline steps:** `./gradlew build`, `./gradlew checkstyleMain checkstyleTest`, `./gradlew javadoc`.

#### `reusable-build-matrix.yml`
Matrix build that runs the Gradle pipeline across multiple Java/Gradle version combinations. Used in this repository to validate that workflows themselves remain green across supported runtime versions.

#### `reusable-build-python.yml`
Lints, checks formatting and runs the test suite of a Python project managed with uv, on top of the `nova-setup-python` composite action.

| Input | Type | Required | Default | Description |
|---|---|---|---|---|
| `python-version` | string | no | `''` | Python version. Empty reads `.python-version`, then `requires-python` |
| `uv-version` | string | no | `''` | uv version. Empty reads `required-version` from `uv.toml` or `pyproject.toml`, then installs the latest release |
| `working-directory` | string | no | `'.'` | Directory with `pyproject.toml` and `uv.lock` |
| `cache` | boolean | no | `true` | Cache uv packages and the uv-managed Python in the caller repository |
| `lint` | boolean | no | `true` | Run `ruff check` |
| `format` | boolean | no | `true` | Run `ruff format --diff` |
| `test` | boolean | no | `true` | Run `pytest` |

**Secrets required:** none.

**Pipeline steps:**

| Step | Command |
|---|---|
| Setup | `nova-setup-python`: uv, Python, cache, `uv sync --locked` |
| Lint | `uv run --no-sync ruff check --output-format=github .` |
| Format check | `uv run --no-sync ruff format --diff .` |
| Tests | `uv run --no-sync pytest` |

ruff and pytest come from the consumer's own `uv.lock`; the workflow installs neither. It declares no workflow-level concurrency: inside a called workflow `github.workflow` is the caller's name, so a group shared with the caller deadlocks and GitHub cancels the run. The caller declares its own.

### Quality and Security Pipelines

#### `reusable-sonarcloud-maven.yml`
Generates JaCoCo coverage and runs SonarCloud analysis for Maven projects.

| Input | Type | Required | Default | Description |
|---|---|---|---|---|
| `java-version` | string | no | `'25'` | JDK version to use |
| `sonar-org` | string | yes | — | SonarCloud organization |
| `sonar-project-key` | string | yes | — | SonarCloud project key |
| `sonar-host-url` | string | no | `'https://sonarcloud.io'` | SonarQube/SonarCloud URL |
| `sonar-coverage-exclusions` | string | no | `''` | Comma-separated coverage exclusions |
| `sonar-quality-gate` | string | no | `'true'` | Wait for quality gate result |
| `sonar-branch` | string | no | `${{ github.head_ref \|\| github.ref_name }}` | Branch to analyze |
| `build-tool` | string | no | `'maven'` | Must be `'maven'` |

**Secrets required:** `NOVA_SONAR_TOKEN`.

#### `reusable-sonarcloud-gradle.yml`
Same purpose for Gradle projects. Same inputs as the Maven variant (with `build-tool` defaulting to `'gradle'`).

#### `reusable-owasp-check.yml`
Runs OWASP Dependency-Check against the project, producing an HTML report of known CVEs in transitive dependencies.

#### `reusable-sbom.yml`
Generates a CycloneDX SBOM for the consumer project using [anchore/sbom-action](https://github.com/anchore/sbom-action) (replaces the deprecated `anchore/syft-action@v1`).

#### `codeql.yml`
Runs GitHub CodeQL static analysis on every push and pull request. Backed by the `github/codeql-action` SHA-pinned to commit `e0647621c2984b5ed2f768cb892365bf2a616ad1`.

### Publish Pipelines

#### `reusable-release-publish.yml` (Gradle — official, Sprint 3+)
Triggered by a `vX.Y.Z` tag push (created by release-please). Validates the tag format, syncs the version into `gradle.properties`, resolves package visibility, and publishes to GitHub Packages.

This is the **official** publication path for Gradle projects as of Sprint 3. It replaces the deprecated `reusable-publish-gradle.yml`.

#### `reusable-release-maven-publish.yml` (Maven — official, Sprint 3+)
Same as above, for Maven projects. Validates the tag format (with environment-variable indirection to prevent CodeQL code-injection false positives), syncs the version into `pom.xml`, and publishes to GitHub Packages.

This is the **official** publication path for Maven projects as of Sprint 3. It replaces the deprecated `reusable-publish-maven.yml`.

#### `reusable-publish-gradle.yml` / `reusable-publish-maven.yml` (DEPRECATED)
> **Deprecated as of 2026-07-21.** Use `reusable-release-publish.yml` (Gradle) or `reusable-release-maven-publish.yml` (Maven) instead. These workflows remain in the repository for legacy consumer projects that have not yet migrated.

### Release Orchestration

#### `reusable-release-please.yml`
Runs [release-please](https://github.com/googleapis/release-please) from Google to automate Conventional Commits-based releases. On every push to the target branch, it analyzes commit history, opens (or updates) a release PR that bumps the version, updates `CHANGELOG.md`, and merges it to create a GitHub Release and a `vX.Y.Z` tag. The tag then triggers the publish pipeline.

| Input | Type | Required | Default | Description |
|---|---|---|---|---|
| `release-type` | string | no | `'java'` | One of `java`, `gradle`, `maven`, `python`, `node`, `go`, `rust`, `php`, `ruby`, `elixir` |
| `package-name` | string | no | repo name | Package name (for multi-package repos) |
| `config-file` | string | no | `'.release-please-config.json'` | Path to release-please config |
| `manifest-file` | string | no | `''` | Path to release-please manifest (multi-repo) |
| `node-version` | string | no | `'20'` | Node.js version |
| `target-branch` | string | no | `'main'` | Target branch for release PRs |

**Secrets required:** `GH_TOKEN` (with `contents:write` and `pull-requests:write`).

### Repository Hygiene

#### `reusable-main-guard.yml`
Flags commits that reach a branch without going through a merged pull request. Private repositories on GitHub's free plan cannot use branch protection or rulesets, so a direct push to `main` cannot be rejected; this workflow makes it visible instead. On every push it asks GitHub for the merged pull request associated with the commit, retrying while the association catches up with the merge. When there is none, it leaves a comment on the commit mentioning whoever pushed it and fails the run.

| Input | Type | Required | Default | Description |
|---|---|---|---|---|
| `retries` | number | no | `3` | Attempts to find the pull request before giving up |
| `retry-delay-seconds` | number | no | `10` | Seconds between attempts |
| `message` | string | no | English text | Comment left on the commit, after the mention, so each repository can use its own language |

The caller must grant `contents: write` and `pull-requests: read`.

```yaml
name: Guard main
on:
  push:
    branches: [main]
permissions:
  contents: write
  pull-requests: read
jobs:
  guard:
    uses: ahincho/nova-shared-02-pipelines/.github/workflows/reusable-main-guard.yml@<sha>
```

It complements branch protection, it does not replace it: the commit is already on the branch when the run turns red. Pair it with a local `pre-push` hook that refuses pushes to `main`.

### Standalone Workflows

These workflows are not reusable. They run directly in this repository.

#### `nvd-mirror-update.yml`
Scheduled weekly rebuild of the shared OWASP dependency-check NVD database. Produces an H2 + JSON mirror committed to the `nvd-mirror` tag. All `reusable-owasp-check.yml` consumers point to this tag to share a single, fast database.

#### `codeql.yml`
Scheduled and pull-request-triggered CodeQL scan of this repository's own workflows and composite actions.

#### `publish-on-tag.yml`
Local caller that invokes `reusable-release-publish.yml` when a `vX.Y.Z` tag is pushed. Lives in this repository as a reference pattern for consumer repositories.

## Available Composite Actions

| Action | Purpose |
|---|---|
| `nova-setup-java` | JDK setup with Gradle/Maven dependency cache and build-file validation |
| `nova-setup-node` | Node.js setup with `node_modules` cache and `npm ci` |
| `nova-setup-python` | uv and Python setup with the GitHub Actions cache and `uv sync --locked` |
| `nova-setup-gpg` | GPG key import for artifact signing (inputs only; no `secrets.*` access) |
| `nova-resolve-token` | Resolves a short-lived installation token for a GitHub App |
| `nova-gather-facts` | Collects repository facts (visibility, default branch, languages) for downstream jobs |
| `nova-validate-build` | Validates `pom.xml` / `gradle.properties` / `package.json` existence and required fields |
| `nova-publish-aggregator` | Aggregates multi-module publish outputs for GitHub Packages |
| `nova-verify-publication` | Downloads what a publish step just uploaded to GitHub Packages and fails the job if it cannot |

The workflows here pin the composite actions to the same canonical commit (`300f6695c82197f50b2cfa0831bd146ed549a279`), with two exceptions: `nova-setup-python`, which `reusable-build-python.yml` pins to the commit that added it (`1012c24789a8457006e3d51276801c67bac160e3`), and `nova-resolve-token`, pinned to `9b546b19f87b8f05620544c5cf12cc5e0e36b66d`, the commit that makes it take its tokens as inputs: the canonical commit predates the action, and every version before that one references the `secrets` context and fails to load. No workflow here calls `nova-verify-publication`: each repository's `publish-on-tag.yml` calls it right after its publish step.

## Pester Test Suite

A 243-test Pester 5.7.1 suite covers workflow structure, input surfaces, security-critical patterns (env-var indirection, SHA pinning), and migrations.

```powershell
$env:PSModulePath = "$env:USERPROFILE\Documents\PowerShell\Modules;" + $env:PSModulePath
Import-Module Pester -RequiredVersion 5.7.1
Invoke-Pester ./tests
```

| Test file | Coverage |
|---|---|
| `apply-nova-labels.Tests.ps1` | Operator script for `apply-nova-labels.ps1` (Scheme B labels) |
| `apply-nova-metadata.Tests.ps1` | Operator script for `apply-nova-metadata.ps1` |
| `migrations.Tests.ps1` | Migration bundle structure and content |
| `nova-resolve-token.Tests.ps1` | GitHub App token resolution action |
| `nova-setup-python.Tests.ps1` | uv and Python setup action: inputs, SHA pins, env-var wiring, cache and sync behaviour |
| `reusable-build-python.Tests.ps1` | Python build workflow: triggers, inputs, hardening, SHA pins, step wiring |
| `reusable-package-retention.Tests.ps1` | SNAPSHOT cleanup workflow |
| `reusable-sonarcloud.Tests.ps1` | SonarCloud workflow input surface, env-var wiring, SHA-pinning |
| `rotate-nova-tokens.Tests.ps1` | Operator script for `rotate-nova-tokens.ps1` |

## PowerShell Operator Scripts

Operator utilities for managing the multi-repo Nova ecosystem. Run from a workstation with `gh` CLI authenticated against the `ahincho` organization.

| Script | Purpose |
|---|---|
| `scripts/apply-nova-labels.ps1` | Apply Scheme B labels across 32 consumer repositories |
| `scripts/apply-nova-metadata.ps1` | Apply repository topics, description, and homepage |
| `scripts/rotate-nova-tokens.ps1` | Phase 1 issue + Phase 2 delete of `NOVA_RELEASE_PAT` secrets |

## Migrations

`release-please` migration bundles for consumer repositories that pre-date the current release model. Apply with the `gh` CLI:

```bash
gh repo clone nova-bom-lote-f ./nova-bom
cp -r ./.github/workflows/* ./nova-bom/.github/workflows/
cd ./nova-bom
git checkout -b chore/migrate-to-release-please
git commit -am "chore: migrate to release-please"
gh pr create --base main --title "chore: migrate to release-please"
```

Available bundles:

- `nova-bom-lote-f`
- `nova-java-spring-boot-parent-lote-f`

## Security Posture

| Layer | Status | Reference |
|---|---|---|
| CodeQL static analysis | 0 alerts (medium or higher) | Lote Q, July 2026 |
| Action SHA pinning | 14 actions, 68 `uses:` refs | Lote Q, July 2026 |
| Code-injection (env var pattern) | 0 alerts (was 7) | Lote Q, July 2026 |
| Dependabot | Active, weekly schedule, version updates enabled | `dependabot.yml` |
| Branch protection on `main` | 1 review, enforce_admins, CodeQL required | Repo settings |
| Branch protection on `dev` | 1 review, CodeQL required (no enforce_admins) | Repo settings |
| Secret scanning | Enabled with push protection | Repo settings |

## Required Secrets and Variables

Each consumer repository needs the following secrets (items marked _optional_ are only required for the workflows that consume them):

| Secret | Consumed by | Required |
|---|---|---|
| `GITHUB_TOKEN` | All publish workflows | Auto-provided by GitHub |
| `NOVA_SONAR_TOKEN` | `reusable-sonarcloud-{maven,gradle}.yml` | Optional (only if SonarCloud is enabled) |
| `NOVA_APP_ID` / `NOVA_APP_PRIVATE_KEY` | `nova-resolve-token` | Optional (only for short-lived App tokens) |

Repository variables (not secrets):

| Variable | Consumed by | Default | Description |
|---|---|---|---|
| `NOVA_PACKAGE_VISIBILITY` | `reusable-publish-*` (deprecated) | `'public'` | Default package visibility (overridable by `visibility` input) |

## Consumer Repository Example

A complete caller workflow for a Gradle library consumer:

### `.github/workflows/ci.yml`

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main, dev]

permissions: {}

jobs:
  build:
    uses: ahincho/nova-shared-02-pipelines/.github/workflows/reusable-build-gradle.yml@300f6695c82197f50b2cfa0831bd146ed549a279
    with:
      java-version: '25'
    secrets: inherit

  sonar:
    if: github.event_name == 'pull_request'
    uses: ahincho/nova-shared-02-pipelines/.github/workflows/reusable-sonarcloud-gradle.yml@300f6695c82197f50b2cfa0831bd146ed549a279
    with:
      sonar-org: ahincho
      sonar-project-key: ahincho_nova-<name>
      java-version: '25'
    secrets: inherit

  owasp:
    uses: ahincho/nova-shared-02-pipelines/.github/workflows/reusable-owasp-check.yml@300f6695c82197f50b2cfa0831bd146ed549a279
    with:
      java-version: '25'
```

### `.github/workflows/release-please.yml`

```yaml
name: Release Please

on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    uses: ahincho/nova-shared-02-pipelines/.github/workflows/reusable-release-please.yml@300f6695c82197f50b2cfa0831bd146ed549a279
    with:
      release-type: java
      package-name: nova-<name>
    secrets:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### `.github/workflows/publish-on-tag.yml`

```yaml
name: Publish on Tag

on:
  push:
    tags: ['v[0-9]+.[0-9]+.[0-9]+']

jobs:
  publish:
    uses: ahincho/nova-shared-02-pipelines/.github/workflows/reusable-release-publish.yml@300f6695c82197f50b2cfa0831bd146ed549a279
    secrets: inherit
```

### `.release-please-config.json`

```json
{
  "packages": {
    ".": {
      "package-name": "nova-<name>",
      "release-type": "java",
      "bump-minor-pre-major": true,
      "bump-patch-for-minor-pre-major": true,
      "draft": false,
      "prerelease": false
    }
  }
}
```

### `.release-please-manifest.json`

```json
{
  ".": "0.1.0"
}
```

### Python (uv) consumer

`.github/workflows/ci.yml` for a Python project with `pyproject.toml`, `uv.lock` and `.python-version` at the repository root:

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  build:
    uses: ahincho/nova-shared-02-pipelines/.github/workflows/reusable-build-python.yml@8e875e2a349c1853074c4990f2b9878295041194
```

A check that only one project needs runs in its own job with the composite action. `save-cache: 'false'` makes it restore the cache without racing the `build` job to upload the same key:

```yaml
  project-check:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          persist-credentials: false
      - uses: ahincho/nova-shared-02-pipelines/.github/actions/nova-setup-python@8e875e2a349c1853074c4990f2b9878295041194
        with:
          save-cache: 'false'
      - run: uv run --no-sync python scripts/check.py
```

## Library Ecosystem

| Library | Repo | Build Tool | Sonar Project Key |
|---|---|---|---|
| mask-utils | `nova-mask-utils` | Maven | `ahincho_nova-mask-utils` |
| api-standard | `nova-api-standard` | Gradle KTS | `ahincho_nova-api-standard` |
| date-utils | `nova-date-utils` | Gradle KTS | `ahincho_nova-date-utils` |
| mapper-utils | `nova-mapper-utils` | Gradle KTS | `ahincho_nova-mapper-utils` |
| spring-boot-parent | `nova-java-spring-boot-parent` | Gradle KTS | `ahincho_nova-java-spring-boot-parent` |
| bom | `nova-bom` | Maven | `ahincho_nova-bom` |

## Branch Protection Rules

### `main`
- 1 approving review
- CODEOWNERS enforcement
- Dismiss stale approvals on push
- `enforce_admins: true`
- Required status check: `CodeQL Advanced / analyze (actions)` (strict)

### `dev`
- 1 approving review
- CODEOWNERS enforcement
- Dismiss stale approvals on push
- `enforce_admins: false`
- Required status check: `CodeQL Advanced / analyze (actions)` (strict)

## Dependabot Configuration

Dependabot runs weekly (Monday 06:00 UTC) with two package ecosystems:

- **github-actions** — version updates for `actions/*`, `github/*` (actions-major-bump group) and `gradle/actions`, `googleapis/*`, `anchore/*`, `sonarsource/*`, `astral-sh/*`, `github/codeql-action` (third-party-actions group)
- **npm** — version updates for `@commitlint/*` and `lefthook` (major updates ignored)

Configuration lives in `.github/dependabot.yml`. Group definitions use only schema-valid keys (`applies-to`, `patterns`); non-schema fields (e.g. `update-strategy`) are intentionally omitted.

---

**Maintained by:** `ahincho` — see `CODEOWNERS` for review routing.
**CHANGELOG:** see `CHANGELOG.md` for release history (Lote A through Lote Q).
**Plan of record:** see `nova-devops.md` for the active working plan and bitácora.

## License

Eclipse Public License 2.0 — see [LICENSE](LICENSE).

Copyright © 2026 Angel Hincho.
