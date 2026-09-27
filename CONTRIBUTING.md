# Contributing to nova-devops

Thanks for your interest in improving the CI/CD infrastructure that powers ~30 Nova Platform libraries.

## Scope of this repo

`nova-devops` ships **reusable GitHub Actions workflows** and **composite actions** consumed via `ahincho/nova-shared-02-pipelines/.github/{workflows,actions}/...@main` by every Java + NestJS library in the ecosystem. A change here propagates to every downstream repository on the next CI run.

## Branching & commits

- Single branch: `main`. No long-lived feature branches.
- Conventional Commits enforced locally by `lefthook` + `commitlint` (see `package.json`).
  - Allowed types: `feat`, `fix`, `chore`, `refactor`, `docs`, `ci`, `test`, `perf`, `build`.
- Signed commits encouraged (will be required once branch protection is enabled).

## Pull request process

1. Open a PR against `main`.
2. PR title MUST follow Conventional Commits (validated by CI).
3. At least 1 approving review is required.
4. All CI checks must be green before merge:
   - `CodeQL Advanced`
   - `Dependabot` (informational)
   - `Release Please` (informational)
   - `NVD Mirror Update` (informational)
5. Squash-merge with the conventional commit title.

## Adding a new reusable workflow

1. Create `.github/workflows/reusable-<name>.yml`.
2. Document it in `README.md`:
   - Description, parameters table, secrets table, output examples.
   - At least one usage example showing how a consumer would invoke it.
3. Cross-reference any related workflows / composite actions.
4. Verify with `actionlint` locally if possible.
5. Open a PR referencing at least one consumer repo (in a follow-up PR if needed).

## Adding a new composite action

1. Create `.github/actions/<name>/action.yml` + `<name>/README.md`.
2. Document all inputs / outputs in the README.
3. Pin third-party `uses:` to a floating major tag (`@vN`) consistent with the rest of the repo.
4. Avoid `curl ... | sh` patterns - prefer pinned actions.

## Local testing

### Workflows

`act` works for simple cases but cannot replicate org-level secrets or composite action resolution. Use real runners in a fork for full validation.

### PowerShell scripts

```powershell
# Requires Pester v5+
pwsh -Command "Invoke-Pester ./tests"
```

### Composite actions

`actionlint` is recommended:

```bash
actionlint .github/workflows/*.yml .github/actions/*/action.yml
```

## Security

- Never commit secrets. Use GitHub Secrets or `gh secret set`.
- The `nova-validate-build` composite action scans for common secret patterns at build time.
- If you discover a vulnerability, open a GitHub Security Advisory (private) instead of a public issue.