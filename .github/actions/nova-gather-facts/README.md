# nova-gather-facts

Collects build facts (version, branch, commit SHA, snapshot detection) and exposes them as outputs for downstream steps.

## What it collects

- **version**: From `gradle.properties` (default), `package.json`, env var `NOVA_VERSION`, or fallback
- **branch**: From `GITHUB_REF_NAME` (env) or `git rev-parse`
- **commit-sha** / **commit-sha-short**: Full and 7-char SHA
- **is-snapshot**: `true` if version contains `-SNAPSHOT`, `-RC`, `-BETA`, `-ALPHA`, or `-MILESTONE`
- **is-tag**: `true` if ref matches `vX.Y.Z` pattern
- **build-number**: GitHub Actions run number

## Inputs

| Input | Default | Description |
|---|---|---|
| `version-source` | `gradle-properties` | `file` / `gradle-properties` / `env` / `package-json` |
| `version-file` | `gradle.properties` | Path to version file (when source is `file`) |
| `fallback-version` | `0.0.0` | Version when source is unavailable |

## Outputs

| Output | Example |
|---|---|
| `version` | `1.0.0` / `0.1.0-SNAPSHOT` / `1.0.0-RC1` |
| `branch` | `main` / `v1.0.0` |
| `commit-sha` | `7348225a8dc7d81ed0bfb5f815fde980f183a537` |
| `commit-sha-short` | `7348225` |
| `is-snapshot` | `true` / `false` |
| `is-tag` | `true` / `false` |
| `build-number` | `42` |

## Example usage

```yaml
- name: Gather build facts
  id: facts
  uses: ahincho/nova-shared-02-pipelines/.github/actions/nova-gather-facts@main

- name: Use facts
  run: |
    echo "Building ${{ steps.facts.outputs.version }} from ${{ steps.facts.outputs.branch }}"
    if [ "${{ steps.facts.outputs.is-snapshot }}" = "true" ]; then
      echo "This is a snapshot build"
    fi
```

## Why this exists

Centralizes the logic for extracting version, branch, and commit info from different sources. Avoids duplicating this across every workflow and provides consistent output for downstream steps.

## Related

- `nova-publish-aggregator` — uses `version` to construct package coordinates
- `nova-validate-build` — validates prerequisites before build
