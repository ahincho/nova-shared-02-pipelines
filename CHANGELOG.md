# Changelog

All notable changes to `nova-devops`. The repo does **not** use SemVer - workflows and composite actions are referenced by `@main` and change continuously. This changelog is for human reference only and does not feed any release pipeline.

Format loosely follows [Keep a Changelog](https://keepachangelog.com).

## 2026-10-08 - LaTeX build of a given tag

The CV repository published every on-demand build as a GitHub release (`ai-engineer-en-v0.2.0`), which filled the release list with builds that are not versions. Its CD now compiles a release tag into a workflow artifact instead, and the build recipe needs to check out that tag.

### Added
- `ref` input in `reusable-latex-build.yml`: the tag, branch or commit to check out. Empty keeps the commit that triggered the run, so existing callers do not change.
- README: the recommended model for LaTeX repositories (CI on every change, release-please for immutable `vX.Y.Z` tags with notes only, CD by hand that builds a tag into an artifact), with a CD example.
- 1 Pester test: the checkout passes `ref`. The `persist-credentials` check now accepts other keys before it under `with:`. Removing the `ref:` line fails the new test. Pester suite: 276 → 277.

## 2026-10-07 - LaTeX lint and build

The CV repository built its PDFs with an inline TeX Live job and had no lint. A second LaTeX project is about to start, so both steps move here.

### Added
- `reusable-latex-lint.yml`: chktex over the tracked `.tex` files, installed from Ubuntu's package so the job pulls no TeX Live image. Each file is linted on its own with `-I0`: following `\input` reported files twice and failed on paths built from macros. Every warning is a GitHub annotation on its line, and the job fails when there is one unless `fail-on-warnings` is false. The caller's `.chktexrc` is loaded when it exists. chktex exits 2 when it finds warnings, so the count comes from the annotations, and stdin is closed because chktex reads it when it has nothing else to read.
- `reusable-latex-build.yml`: runs the caller's build command inside `xu-cheng/texlive-action` (scheme `full` or `small`, the two the action ships) and uploads `artifact-path` as `artifact-name` when a name is given. Meant to be called from a matrix, one job per document.
- Neither declares concurrency, and both are read-only, time-bounded and SHA-pinned (`texlive-action` v3 at `22c0432`).
- 18 Pester tests in `tests/reusable-latex.Tests.ps1`. A copy of the lint workflow without `-I0` and with `${{ inputs.paths }}` inside `run:` fails two of them. Pester suite: 258 → 276.

## 2026-10-07 - Outputs for release-please

`reusable-release-please.yml` declared no outputs, so a caller could not tell whether the run had created a release. That matters because a release created with `GITHUB_TOKEN` does not trigger other workflows: a tag-push or `on: release` workflow never runs after it, so a caller that passes `GITHUB_TOKEN` can only build the release assets in the same run, and for that it needs to know that the release exists.

### Added
- Seven outputs, taken from `googleapis/release-please-action`: `release-created`, `releases-created`, `paths-released`, `tag-name`, `version`, `sha` and `pr-created`. Existing callers do not change. First consumer: `curriculum-vitae`, which compiles each CV and publishes it as its own release when the release PR is merged.
- 6 Pester tests in `tests/reusable-release-please.Tests.ps1`. Pester suite: 252 → 258.

### Fixed
- The README listed `release-type`, `package-name` and `node-version` as inputs, which the workflow does not have, and left out `path`. The table now matches the workflow.

## 2026-10-02 - Guard for commits that skip pull requests

Two commits reached `main` of a private consumer repository without a pull request in a few hours, and each one left every open pull request out of date. Branch protection and rulesets are not available on the organization's free plan, so GitHub cannot reject those pushes.

### Added
- `reusable-main-guard.yml`: on a push to a guarded branch, looks up the merged pull request of the commit and, when there is none, comments on the commit mentioning whoever pushed it and fails the run. The comment text is an input, so each repository writes it in its own language.

## 2026-09-30 - OWASP report upload for Gradle repositories

The `Upload OWASP Report` step of `reusable-owasp-check.yml` never found the report of a Gradle repository, so the `owasp-dependency-check-report` artifact was not uploaded. In job 109773891663 of `nova-plaza-03-spring-boot-orders` the log says `Writing HTML report to: .../build/reports/dependency-check-report.html` and then `No files were found with the provided path`.

### Fixed
- The step looked for `**/build/reports/dependency-check/dependency-check-report.html`. The `org.owasp.dependencycheck` Gradle plugin, which `NovaSecurity` applies in `nova-java-24-gradle-toolchain`, writes `build/reports/dependency-check-report.html`, and no Gradle repository sets `outputDirectory`. The pattern is now `**/build/reports/dependency-check-report.html`; the Maven one, `**/target/dependency-check-report.html`, stays.

## 2026-09-28 - Metadata and label scripts match the 32 repositories

`scripts/apply-nova-labels.ps1` and `scripts/apply-nova-metadata.ps1` each listed 32 repositories, but 11 of them no longer existed and 11 that exist were missing.

### Removed
- The four NestJS repositories from before the three-package collapse (`nova-nestjs-commons`, `-observability-starter`, `-parent` and `-starter`), deleted on 2026-09-28.
- The four `nova-java-notifications*` repositories and the three `demo-notifications-*` ones, which no longer exist.

### Added
- Examples 02, 03, 05, 06, 07 and 08, `nova-java-06-keycloak`, `nova-java-07-architecture-rules`, `nova-java-11-keycloak-quarkus-extension`, `nova-nestjs-01-platform` and `nova-nestjs-02-profile-utp`. Each gets its type, lifecycle, framework and area labels plus the standard tail; the description is the one the repository has on GitHub today.
- Topics for `nova-example-08-nestjs-generated` and `nova-nestjs-02-profile-utp`, the two repositories with none, taken from their siblings.

## 2026-09-27 - OWASP false positives of the Gradle plugin

### Added
- 12 entries in `docs/owasp-suppressions.json` for `nova-java-16-spring-boot-gradle-plugin`. NVD matches `io.spring.gradle:dependency-management-plugin` 1.1.7 as Spring Framework 1.1.7, which brings 11 Spring Framework CVEs (Spring4Shell among them), and `spring-boot-loader-tools` 4.0.8 as Spring Tools 4.0.8, which brings CVE-2022-31691 from the IDE extensions. Neither artifact is the product the CVE describes, and the GitHub Advisory Database has no advisory for either. Each entry names only its package, so the same CVE still fails any other artifact.

## 2026-09-27 - Pull request CI runs again

From 2026-07-21 no pull request in a Java repository got a working CI run. Two defects, both from the Lotes A-R-P hardening, stacked on each other.

### Fixed
- `nova-resolve-token` referenced the `secrets` context, which a composite action does not have, so GitHub refused to load it (`Unrecognized named-value: 'secrets'`) and every build, matrix, OWASP and SBOM job failed at that step. The PATs now arrive as inputs (`packages-read-token`, `legacy-token`), and `github-token` defaults to `github.token`. `GITHUB_TOKEN` also moves from second to last place: it is always present, so it used to win every time, and it cannot read another repository's packages.
- The five callers pass both PATs and pin the action to `9b546b1`, the commit that fixes it.
- Every reusable workflow built its concurrency group from `github.workflow`, which inside a called workflow is the caller's name. The build, matrix, OWASP, SBOM and Sonar workflows called by one CI run therefore shared a group and cancelled one another. Each group now carries the reusable's own name: twelve workflows change, and `reusable-package-retention.yml` already had its own group.
- 8 Pester tests, among them a guard against the `secrets` context in the action and one that no two reusables share a group. Pester suite: 235 → 243.

## 2026-09-27 - Publication check

### Added
- `.github/actions/nova-verify-publication/` - composite action that downloads the `.pom` and `.jar` (or whatever `extensions` lists) of every artifact a job has just published to GitHub Packages, and fails the job when one cannot be downloaded. A green publish step did not prove it in July, when the Quarkus extension was published five times without a downloadable artifact. It retries each file until `timeout-seconds` (default 300) and asks for nothing before the upload, so it cannot seed a cached 404. Every input is validated and reaches bash through env vars (Lote R). Called from each repository's `publish-on-tag.yml`, as ADR-039 in `nova-shared-01-docs` requires. 12 Pester tests. Pester suite: 223 → 235.

## 2026-09-23 - Python (uv) support

### Added
- `.github/actions/nova-setup-python/` - composite action that installs uv and Python, restores and saves the GitHub Actions cache (uv packages and the uv-managed CPython) and runs `uv sync --locked`. `cache: 'true'` maps to setup-uv's `enable-cache: auto`, which skips the cache on release, tag push, `pull_request_target` and `workflow_run` events. The cache key hashes `uv.lock` and `.python-version` only, so pyproject edits that leave the lockfile untouched keep the cache. `UV_PYTHON_PREFERENCE=only-managed` keeps the interpreter independent of the runner image, unless the caller already set a preference. `save-cache: 'false'` lets a secondary job restore without racing the main job for the same key. Every boolean input is validated, so a typo fails instead of silently disabling the cache or the sync. 19 Pester tests.
- `.github/workflows/reusable-build-python.yml` - `ruff check --output-format=github`, `ruff format --diff` and `pytest` on top of `nova-setup-python`, each behind a toggle and run through `uv run --no-sync`. ruff and pytest come from the consumer's `uv.lock`. No workflow-level concurrency: inside a called workflow `github.workflow` is the caller's name, so a shared group deadlocks. `permissions: contents: read`, `timeout-minutes: 15`, `persist-credentials: false`. Pins `nova-setup-python` to `1012c24`, the commit that adds it. 14 Pester tests. Pester suite: 190 → 223.
- Dependabot groups `astral-sh/*` (setup-uv) with the other third-party actions.

## 2026-07-21 - Code quality and supply-chain hardening

### Added
- `.github/workflows/codeql.yml` - CodeQL static analysis on every PR (language: actions).
- `.github/dependabot.yml` - weekly automated PRs for `github-actions` and `npm` ecosystems.
- `LICENSE` (MIT).
- `CONTRIBUTING.md`.
- `CODEOWNERS` - auto-assigns @ahincho to all changes; stricter ownership on security-sensitive files.
- `tests/` - Pester smoke tests for the 3 PowerShell automation scripts.
- `.github/actions/nova-resolve-token/` - composite action that resolves the packages-read token safely in bash, replacing the buggy `secrets.X || secrets.Y` short-circuit pattern.
- **Lote H1 - GitHub App authentication in `nova-resolve-token`**: the composite now optionally accepts `app-id` + `app-private-key` inputs and uses `actions/create-github-app-token@v2` to mint installation tokens for cross-repo GitHub Packages reads. Resolution priority: GITHUB_APP_TOKEN > GITHUB_TOKEN > NOVA_PACKAGES_READ_TOKEN (PAT) > NOVA_RELEASE_PAT (PAT, legacy). When a PAT is selected, a `::notice::` annotation is emitted to nudge migration. The action is fully backwards-compatible: callers that do NOT pass the new inputs fall back to the existing PAT/GITHUB_TOKEN path unchanged. The 5 caller workflows (reusable-build-{gradle,maven,matrix}, reusable-owasp-check, reusable-sbom) were updated to pass the App creds via `secrets.NOVA_PLATFORM_APP_ID` / `secrets.NOVA_PLATFORM_APP_PRIVATE_KEY` - those inputs are empty strings when the secrets are unset, so the conditional App step is skipped transparently. Pester test coverage expanded from 32 to 50 tests (18 new for the composite + App wiring).

### Lote H1 manual setup (one-time, by @ahincho)
The new App auth path is wired in code but inert until the GitHub App is created and installed. Steps:

1. Create the App at <https://github.com/settings/apps/new> (user-level - this org has no org-level App slot yet):
   - **Name**: `Nova Platform Bot` (must be unique on github.com)
   - **Homepage URL**: <https://github.com/ahincho>
   - **Repository permissions**: `Contents: Read-only`, `Packages: Read-only`
   - **No webhook** needed
   - After creation: note the **App ID** (numeric), generate a **private key** (downloads `.pem`)
2. Install the App on every repo that **publishes** packages (source of truth for `pe.edu.nova.java:*` artifacts) AND on every repo that **consumes** them (cross-repo reads require install on both sides).
3. For each consuming repo, add two secrets (Settings → Secrets and variables → Actions):
   - `NOVA_PLATFORM_APP_ID` — the numeric App ID
   - `NOVA_PLATFORM_APP_PRIVATE_KEY` — paste the **entire** `.pem` contents (multi-line is OK)
4. (Optional, after the App is installed everywhere) Delete the `NOVA_PACKAGES_READ_TOKEN` PAT secret from each repo.
5. Verify by running a build and inspecting the `source` output of `resolve_token` - should show `GITHUB_APP_TOKEN`.
- `.github/workflows/reusable-package-retention.yml` - **Lote H2 - Maven package retention**: reusable workflow that deletes old SNAPSHOT (>30d) and pre-release (>90d) Maven package versions from GitHub Packages to reduce storage costs. Supports `package-pattern` filter, `dry-run` mode, and `fail-on-error` flag. Designed to be called per-repo via `workflow_call` from a thin wrapper that declares `permissions: packages: write` (reusable workflows inherit the INTERSECTION of permissions, so the caller MUST opt in to write scope). Concurrency group `package-retention-<repo>` with no cancel-in-progress (destructive ops should queue, not race). 25 new Pester tests cover workflow structure, permissions, concurrency, bash script integrity, and bash syntax (via Git Bash `bash -n`). Total Pester suite: 50 → 77.

### Lote H2 consumer-side setup (per repo that publishes Maven packages)
Each repo that publishes to GitHub Packages Maven should add a thin wrapper workflow. Example (drop in `.github/workflows/retention.yml` in the publishing repo):

```yaml
name: Retention - Cleanup Old Maven Packages
on:
  schedule:
    - cron: '0 3 * * 0'  # weekly Sunday 3am
  workflow_dispatch: {}

# CRITICAL: caller permissions are intersected with reusable. Without this,
# the reusable workflow silently downgrades to packages:read and every
# DELETE call returns HTTP 403.
permissions:
  contents: read
  packages: write

jobs:
  retention:
    uses: ahincho/nova-devops/.github/workflows/reusable-package-retention.yml@<pinned-sha>
    with:
      package-pattern: 'pe.edu.nova.java'
      snapshot-retention-days: 30
      prerelease-retention-days: 90
      # First run: dry-run: true to inspect the step summary without deleting anything
      dry-run: false
```

To find the current pinned SHA, see the `Lote E pin-bumping procedure` section above (same SHA `300f6695c82197f50b2cfa0831bd146ed549a279` until next bump).
- Branch protection on `main` (1 review, code-owner reviews, conversation resolution, strict CodeQL status check, admins enforced).

### Changed
- `reusable-sbom.yml` - replaced insecure `curl|sh` syft installer with pinned `anchore/syft-action@v1` (third-party action, signed).
- `reusable-publish-gradle.yml` and `reusable-publish-maven.yml` - marked DEPRECATED. Use `reusable-release-publish.yml` instead.
- Bumped all third-party GitHub Actions from v4 to v5 (Node 24 runtime):
  - `actions/checkout` v4 → v5 (13 sites).
  - `actions/setup-java` v4 → v5 (3 sites).
  - `actions/cache` v4 → v5 (1 site).
  - `actions/upload-artifact` v4 → v5 (7 sites).
  - `gradle/actions/setup-gradle` v4 → v5 (1 site).
- Added explicit `permissions:` blocks to all 14 workflows (least-privilege; was implicitly inheriting the repo's default which had `contents: write` for everything).
- Added `concurrency:` blocks to all 14 workflows. PR runs cancel-in-progress on a new push; tag-driven publishes never cancel (destructive); the daily NVD mirror uses a shared group without cancellation.
- Added `timeout-minutes:` to every job (15 jobs across 14 workflows). CodeQL: 30. Builds: 30. Build matrix: 60. OWASP: 45. SBOM: 15. Release-please: 15. Release-publish: 60. SonarCloud: 30. NVD mirror: 90.
- `reusable-build-matrix.yml` - fixed a missed `secrets.NOVA_PACKAGES_READ_TOKEN || secrets.NOVA_RELEASE_PAT` env var that escaped the Lote B replacement; now uses `steps.resolve_token.outputs.value`.
- Bumped `googleapis/release-please-action` v4 → v5 (Node 24 runtime; no API/inputs change). Now bundles release-please 17.6.0 (was 17.3.0 in v4.4.1).
- `reusable-release-please.yml` - **BREAKING for any consumer that passes them**: removed the dead `release-type:` and `node-version:` inputs. `release-type` was never read by the action (per the existing inline comment, passing it caused release-please to IGNORE `.release-please-config.json`, which broke `skip-snapshot` and other settings - see commit bb67ea7-era investigation). `node-version` was never used (no `actions/setup-node` step exists). Consumers should rely on `.release-please-config.json` for `packages.*.release-type` instead.
- **Lote E - SHA-pinning of internal refs**: all 28 references to internal nova-devops composites (and the single workflow-to-workflow call from `publish-on-tag.yml` to `reusable-release-publish.yml`) are now pinned to a specific commit SHA on `main` instead of floating `@main`. Pinned SHA: `300f6695c82197f50b2cfa0831bd146ed549a279` (the HEAD at the time of pinning; local HEAD matches remote `main`). Composites affected: `nova-resolve-token` (5 sites), `nova-setup-java` (8), `nova-validate-build` (5), `nova-gather-facts` (7), `nova-publish-aggregator` (2). Header comment added to the top of all 9 affected workflow files explaining the pin and pointing here for the bumping procedure. **THIS IS A BREAKING CHANGE FOR EXTERNAL CONSUMERS** who pin to `@main` - they must either (a) bump their own references to this SHA, or (b) wait for the next push + re-pin cycle.

### Pin-bumping procedure (Lote E follow-up)
When you commit + push changes to `nova-devops/.github/{actions,workflows}/`, all internal refs in the 9 affected workflow files reference a now-stale SHA. To keep consumers in sync:

1. After `git push origin main`, get the new HEAD SHA:
   ```bash
   git rev-parse origin/main
   # or
   gh api repos/ahincho/nova-devops/branches/main --jq .commit.sha
   ```
2. In all 9 affected workflows, replace `300f6695c82197f50b2cfa0831bd146ed549a279` with the new SHA. Affected files:
   - `.github/workflows/reusable-build-{gradle,maven,matrix}.yml`
   - `.github/workflows/reusable-owasp-check.yml`
   - `.github/workflows/reusable-sbom.yml`
   - `.github/workflows/reusable-release-publish.yml`
   - `.github/workflows/reusable-publish-{gradle,maven}.yml`
   - `.github/workflows/publish-on-tag.yml`
3. Update the header comment in each of those files (the line `# to commit <old-sha> on main`).
4. Add a CHANGELOG entry under "Lote E" with the new SHA + date.
5. Commit + push (one commit is fine; the header line is informational).

**Alternative future strategy** (not yet adopted): tag-based pinning (`@v1`, `@v2`) would let consumers get automatic security patches while still being tamper-evident. Not adopted now because the repo explicitly avoids SemVer per the `nvd-mirror` precedent.
- **Lote F - Cross-repo read token + reusable Maven publish + consumer migration bundles**:
  - **`reusable-release-publish.yml`** (Gradle variant): added `packages-read-token` input AND `NOVA_PACKAGES_READ_TOKEN` secret. Priority: `secrets.NOVA_PACKAGES_READ_TOKEN || inputs.packages-read-token` (secret wins so the consumer doesn't need to pass it in two places). Wired through to `nova-setup-java` so Maven consumers reading other Nova repos (e.g. `pe.edu.nova.java:nova-bom` from `nova-java-spring-boot-parent`) no longer need the inline `~/.m2/settings.xml` workaround.
  - **`reusable-release-maven-publish.yml`** (NEW): Maven sibling of the Gradle variant. Tag-triggered (`vX.Y.Z`), uses `nova-publish-aggregator` with `build-tool: maven` + the new `packages-read-token` plumbing. Same `NOVA_PACKAGES_READ_TOKEN` secret support.
  - **`publish-on-tag.yml`** (nova-devops wrapper): rewritten as a 2-job dispatcher (`publish-gradle` default for tag-push, `publish-maven` for explicit `workflow_dispatch` with `build-tool=maven`). Forwards `NOVA_PACKAGES_READ_TOKEN` via `secrets:` block (secrets context is not allowed in `with:` for reusable workflow calls).
  - **`.github/migrations/nova-bom-lote-f/`** and **`.github/migrations/nova-java-spring-boot-parent-lote-f/`**: portable migration bundles for the 2 remaining consumers of the DEPRECATED `reusable-publish-maven.yml`. Each contains the new `release-please.yml` + `publish-on-tag.yml` (Maven-direct) + `.release-please-config.json` + a `README.md` with step-by-step application instructions (manual copy OR `gh` CLI bundle). The bundles cannot be applied automatically from this session because the OAuth token lacks `workflow` scope - the `gh auth refresh --scopes workflow` would add it but is interactive. Application is a one-line `git push` per consumer repo once @ahincho has a token with the right scope, or copy-paste from the bundle's `README.md`.
  - **Discovery result (F scope)**: via `gh search code`, only 2 of @ahincho's ~100 repos actually use the DEPRECATED `reusable-publish-maven.yml`: `nova-bom` (multi-module Maven BOM, calls reusable directly) and `nova-java-spring-boot-parent` (inline `mvn deploy` workaround for cross-repo reads). 16 other Java repos already use the new `release-please.yml` flow since 2026-07-15 (well before this Lote). 0 Gradle consumers use the DEPRECATED `reusable-publish-gradle.yml` - that marker was theoretical.
  - **Pester**: 77 → 92 (+15 for migration bundle integrity).

### Lote F consumer migration (manual)

To apply the migration to `nova-bom` and `nova-java-spring-boot-parent`:

```bash
# Option A: with workflow-scope token (one-time auth refresh)
gh auth refresh --scopes workflow

# Then for each repo:
gh repo clone ahincho/<repo> <repo>-tmp
cd <repo>-tmp
git checkout -b lote-f-migration
git rm .github/workflows/publish.yml

NOVA_DEVOPS=$(git rev-parse --show-toplevel)/../nova-devops   # adjust
cp $NOVA_DEVOPS/.github/migrations/<repo>-lote-f/.github/workflows/release-please.yml .github/workflows/
cp $NOVA_DEVOPS/.github/migrations/<repo>-lote-f/.github/workflows/publish-on-tag.yml .github/workflows/
cp $NOVA_DEVOPS/.github/migrations/<repo>-lote-f/.release-please-config.json .

git add -A
git commit -m "Lote F: migrate from DEPRECATED reusable-publish-maven to release-please + tag-driven flow"
git push -u origin lote-f-migration
gh pr create --title "Lote F: migrate to release-please flow"
```

Option B (no token scope needed): follow the manual copy instructions in each bundle's `README.md`.

### Lote F known limitation: @main refs in non-migrated consumer repos
16 other Java repos (e.g. `nova-java-mask-utils`, `nova-java-date-utils`) already use the new `release-please.yml` flow but still pin to `@main` for the reusable calls (e.g. `uses: ahincho/nova-devops/.github/workflows/reusable-release-please.yml@main`). These should be SHA-pinned in a future Lote (call it Lote E-consumer or Lote G) but are out of scope for F.
- **Lote M - SLSA v1.0 Level 3 provenance attestation**: both `reusable-release-publish.yml` (Gradle) and `reusable-release-maven-publish.yml` (Maven) now emit a build provenance attestation via `actions/attest-build-provenance@v2` after each successful `Publish to GitHub Packages` step. The attest step is **skipped on dry-run** (no real artifact to attest). SLSA provenance is the verifiable record of WHO built the artifact, WHAT source code was used (commit SHA + workflow file SHA), and HOW it was built (workflow run ID, trigger, OIDC identity). It does NOT embed in the artifact itself - it's a separate attestation that consumers can verify with `gh attestation verify`. **Pester: 92 → 100 (+8 new tests covering action presence, subject-path, ordering, dry-run guard).**

### Lote M consumer-side verification

After installing/using a Nova Platform Maven or Gradle artifact, a consumer can verify the provenance:

```bash
# Download the .jar (or .pom for transitive verification)
curl -sLO https://maven.pkg.github.com/ahincho/pe-edu-nova-java/com/example/my-artifact/1.0.0/my-artifact-1.0.0.jar

# Verify the attestation
gh attestation verify my-artifact-1.0.0.jar --owner ahincho
```

The output includes:
- **Build provenance**: commit SHA, workflow file SHA, trigger event, OIDC issuer
- **SLSA Level**: 3 (highest level practically achievable via GitHub Actions; would require hardened build platforms for L4)
- **Verification status**: ✓ if all checks pass

This catches:
- Artifacts built from an unapproved commit
- Artifacts built by a tampered workflow file
- Artifacts built by an unexpected identity (compromised token)

It does NOT catch:
- Malicious code IN the source (use CodeQL + OWASP for that)
- Compromised source repo (out of scope for provenance)

### Lote M known limitation: Maven consumers don't auto-verify
Unlike npm (`npm install --attestations`) or pip (`pip install --require-hashes` with attestation), Maven does not natively check attestations during `mvn dependency:resolve`. Verification is opt-in via the consumer's CLI. For high-assurance workflows, integrate `gh attestation verify` into your consumer CI before adopting the artifact.

### Lote M future work
- **Lote M' (suggested)**: emit a CycloneDX SBOM attestation via `actions/attest-sbom` (sibling action) for complete artifact inventory
- **Lote M'' (suggested)**: gate Maven `dependency:resolve` on attestation verification in consumer repos (custom Maven enforcer rule or pre-build hook)
- **Lote R - SonarCloud full parametrization (configurable, parametrizable)**: both `reusable-sonarcloud-gradle.yml` and `reusable-sonarcloud-maven.yml` rewritten to expose **19 (Gradle) / 18 (Maven) `workflow_call` inputs** covering every SonarCloud knob. The original 3-input surface (`java-version`, `sonar-org`, `sonar-project-key`) is preserved; 15-16 new inputs add the missing configuration. **Main hardening**: `wait-for-quality-gate` defaults to `true` (workflow now FAILS when the quality gate fails, instead of just reporting findings silently). **Pester: 100 → 131 (+31 tests covering input surface, defaults, command-line wiring, Lote E SHA-pin compliance).**

### Lote R input reference (SonarCloud reusables)

| Input | Type | Default | Purpose |
|---|---|---|---|
| `sonar-org` | string | *required* | SonarCloud organization key |
| `sonar-project-key` | string | *required* | SonarCloud project key |
| `java-version` | string | `'25'` | Java version for the runner |
| `gradle-version` (Gradle only) | string | `''` | Override Gradle wrapper version |
| `jacoco-report-path` | string | `build/reports/.../jacocoTestReport.xml` (Gradle) / `target/site/jacoco/jacoco.xml` (Maven) | JaCoCo XML report glob (multi-module: `**/target/*.xml`) |
| `sonar-host-url` | string | `https://sonarcloud.io` | SonarCloud or self-hosted SonarQube |
| `wait-for-quality-gate` | bool | **`true`** | **Main hardening**: fail workflow on QG failure |
| `quality-gate-timeout` | number | `300` | Max seconds to wait for QG result |
| `coverage-threshold` | number | `0` | Min overall coverage % (0 = no minimum) |
| `new-code-coverage-threshold` | number | `80` | Min coverage on NEW code (Nova convention) |
| `sonar-sources` | string | `src/main/java` | Comma-separated source paths |
| `sonar-tests` | string | `src/test/java` | Comma-separated test paths |
| `sonar-exclusions` | string | `**/generated/**,**/build/**,**/*.class` (Gradle) / `**/target/**` (Maven) | Source exclusions |
| `sonar-test-exclusions` | string | `''` | Test exclusions |
| `sonar-coverage-exclusions` | string | `''` | Coverage exclusions |
| `branch` | string | `''` (auto) | Branch to analyze. Empty = auto-detect (PR number for `pull_request`, ref_name otherwise) |
| `pull-request-base` | string | `''` (auto) | Target branch for PR analysis |
| `fail-on-missing-token` | bool | `false` | Fail when `NOVA_SONAR_TOKEN` is unset (was: always skip-with-warning) |
| `dry-run` | bool | `false` | Map to `-Dsonar.scanner.dumpToFile=true` (analyze locally without upload) |

### Lote R consumer-side example

```yaml
# Minimal (Nova defaults - quality gate enforced, 80% new-code coverage)
sonar:
  uses: ahincho/nova-devops/.github/workflows/reusable-sonarcloud-maven.yml@<sha>
  with:
    sonar-org: my-org
    sonar-project-key: my-project
  secrets:
    NOVA_SONAR_TOKEN: ${{ secrets.NOVA_SONAR_TOKEN }}

# Custom - 90% new-code coverage, multi-module JaCoCo paths, custom exclusions
sonar:
  uses: ahincho/nova-devops/.github/workflows/reusable-sonarcloud-maven.yml@<sha>
  with:
    sonar-org: my-org
    sonar-project-key: my-project
    new-code-coverage-threshold: 90
    jacoco-report-path: '**/target/site/jacoco/jacoco.xml'
    sonar-exclusions: '**/generated/**,**/target/**,**/*.class,**/openapi/generated/**'
  secrets:
    NOVA_SONAR_TOKEN: ${{ secrets.NOVA_SONAR_TOKEN }}
```

### Lote R known limitations
- The `wait-for-quality-gate` enforcement requires the project to have a Quality Gate configured in SonarCloud. Projects with "Use global default" inherit `Sonar way` which works out of the box.
- `dry-run` via `sonar.scanner.dumpToFile` writes to `.scannerwork/` for local inspection; it does NOT execute the actual analysis. For full offline analysis, remove `dry-run: true`.
- Self-hosted SonarQube is supported via `sonar-host-url` but the workflow assumes HTTPS (no plain-HTTP fallback).
- **Lote P - Pin strategy reversal: SHA → `@main` / `@dev` branches**. **SUPERSEDES Lote E**. The original Lote E (SHA-pinning to commit `300f6695...`) was a supply-chain hardening experiment, but the manual bump ceremony across 9 files was not sustainable. Replaced with branch-based pins:
  - **`@main`** (default for ALL internal refs + consumer bundles) — points to the latest commit on the stable branch. Auto-updates on every merge.
  - **`@dev`** (optional, opt-in for bleeding-edge) — points to the latest commit on the development branch where new features land first.
  - **Trade-off**: less ceremony, auto-update, but loses tamper-evidence (a malicious commit merged to `main` immediately propagates to all consumers). Acceptable for this single-owner org; for multi-org or compliance-sensitive setups, SHA-pinning can be re-adopted per consumer.

### Lote P workflow (dev → main promotion)

1. Push feature work to `dev` branch (`git push origin dev`)
2. CI runs on `dev` (CodeQL, Pester, actionlint, OWASP, SBOM)
3. Internal refs using `@dev` pick up the change immediately for in-repo testing
4. After validation, PR `dev` → `main` (requires review + CodeQL status check via existing branch protection)
5. Merge to `main` → ALL consumers auto-update (no SHA bump ceremony)
6. release-please triggers on `main` push → tag → publish flow runs unchanged

### Lote P files changed

**Workflows** (10): all `.github/workflows/*.yml` with internal `@<sha>` refs now use `@main`. Header comments rewritten to reference `@main` + `@dev` strategy instead of "pinned to commit X".

**Migration bundles** (4): `nova-bom-lote-f/` and `nova-java-spring-boot-parent-lote-f/` — `.github/workflows/*.yml` updated to `@main`. README bumping procedure rewritten.

**Caller workflows** (5): `reusable-build-{gradle,maven,matrix}.yml`, `reusable-owasp-check.yml`, `reusable-sbom.yml` — added `NOVA_PLATFORM_APP_ID` + `NOVA_PLATFORM_APP_PRIVATE_KEY` to the `workflow_call.secrets:` block to silence actionlint warnings that had been latent since Lote H1 (the `secrets.X` refs in the nova-resolve-token `with:` block now have matching declarations in the callers' secrets list).

### Lote P validation
- **YAML**: all 10 workflows + 4 bundle YAML files parse cleanly.
- **actionlint**: 0 real errors across the workflow set (was 10 before the caller-secret-declaration fix; those errors had been latent since Lote H1).
- **Pester**: 131/131 still passing. Test surface updated: 3 SHA-pin assertions replaced with `@main` branch-pin assertions + 2 SHA-absent guards in the Lote P compliance tests.

### Lote P known limitations
- **Loss of tamper-evidence**: a malicious commit merged to `main` propagates to all consumers immediately. For high-assurance consumers, SHA-pin manually per-call (`uses: ...@<40-char-sha>`).
- **Branch protection on `dev`**: the `dev` branch was created locally but branch protection rules (CI must pass) are NOT yet applied remotely. **Action item for @ahincho**: open a PR or run `gh api repos/ahincho/nova-devops/branches/dev/protection` to configure.
- **Consumers on `@main` will see EVERY change immediately**: no opt-in delay. Consumers wanting a slower rollout can pin to a specific SHA manually.

## 2026-07-13 - NVD mirror + false-positive suppressions registry

### Added
- `docs/owasp-suppressions.json` registry of documented FP CVEs.
- Dynamic FP suppression generation in `reusable-owasp-check.yml`.

### Changed
- `nvd-mirror-update.yml` - restores yesterday's mirror for fast incremental updates.

## 2026-07-12 - OWASP analyzer defaults

### Changed
- `reusable-owasp-check.yml` - disabled analyzers for ecosystems absent from Nova Maven repos (cargo, dart, swift, etc.).

## Sprint 3 (NOVA-SEMVER-13) - 2026-Q2

### Added
- `reusable-release-please.yml` - Conventional Commits to release-PR automation.
- `reusable-release-publish.yml` - publish-on-tag workflow triggered by release-please tags.

### Removed
- Inline `version-bump + publish` chain (replaced by release-please + tag-driven publish).

## Sprint 1 (NOVA-SEMVER-04)

### Added
- `nova-setup-java`, `nova-setup-node`, `nova-setup-gpg` composite actions.
- `reusable-build-{gradle,maven}.yml`, `reusable-publish-{gradle,maven}.yml`.