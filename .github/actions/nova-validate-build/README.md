# nova-validate-build

Validates Nova Platform build prerequisites before running Gradle or Maven.

## What it checks

- **Java version**: Detects Java major version. Fails if below `min-java-version` input.
- **Secrets**: Scans tracked files for common secret patterns (AWS keys, RSA/SSH private keys, GitHub PATs, GitLab PATs, Slack tokens). Excludes `*.md`, `docs/`, and `CHANGELOG.md`. Disabled if `enforce-no-secrets: false`.
- **Gradle/Maven metadata**: Warns (not fails) if `gradle.properties` is missing `group` or `version`, or if `pom.xml` is missing `<groupId>` or `<version>`.
- **lefthook installation**: If `lefthook.yml` and `package.json` (with `lefthook` dep) are present, checks if `.git/hooks/commit-msg` is registered. Warns (not fails) if missing — this is a local-dev concern, not a build blocker.

## Inputs

| Input | Default | Description |
|---|---|---|
| `min-java-version` | `25` | Minimum required Java major version |
| `enforce-no-secrets` | `true` | If true, fail on secret pattern matches |

## Outputs

| Output | Description |
|---|---|
| `validation-result` | `PASS` (action exits non-zero on failure) |
| `java-version-detected` | Detected Java version string (e.g., `25.0.1`) |

## Example usage

```yaml
- name: Validate build prerequisites
  uses: ahincho/nova-shared-02-pipelines/.github/actions/nova-validate-build@main
  with:
    min-java-version: '25'
```

## Why this exists

Prevents the classic "it worked on my machine" issue. Validates that the build environment has the right Java version and no committed secrets before the expensive build steps run.

## Related

- `nova-setup-java` — sets up Java in the runner
- `nova-gather-facts` — collects version, branch, commit SHA
