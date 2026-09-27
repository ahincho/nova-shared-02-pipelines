# nova-publish-aggregator

Dispatches `publish` to the correct registry based on the `registry` input. Wraps the differences between GitHub Packages, Maven Central, Sonatype staging, and Nexus.

## What it does

Resolves effective visibility (input > env var > default `public`), validates against repo visibility, and runs the appropriate build-tool command for the target registry.

| Registry | Gradle | Maven |
|---|---|---|
| `github-packages` | `./gradlew publish -Pvisibility=...` | `mvn deploy -DskipTests` |
| `maven-central` | `./gradlew publishToSonatype closeAndReleaseSonatypeStagingRepository` | `mvn deploy -P central` |
| `sonatype-staging` | Same as `maven-central` | Same as `maven-central` |
| `nexus` | `./gradlew publish -Pvisibility=...` | `mvn deploy -DskipTests` |

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `registry` | ✅ | — | `github-packages` / `maven-central` / `nexus` / `sonatype-staging` |
| `build-tool` | ✅ | — | `maven` / `gradle` |
| `visibility` | ❌ | `''` (defaults to `public`) | `public` / `private` |
| `java-version` | ❌ | `25` | Java version (informational) |
| `dry-run` | ❌ | `false` | If true, only print commands |

## Visibility resolution

```
input.visibility  >  "public"
```

Composite actions cannot read the `vars` context directly. Callers that want
the `vars.NOVA_PACKAGE_VISIBILITY` fallback must resolve it themselves at the
workflow level and pass the result via the `visibility` input, e.g.:

```yaml
visibility: ${{ inputs.visibility != '' && inputs.visibility || vars.NOVA_PACKAGE_VISIBILITY }}
```

Validated against `github.event.repository.visibility`:
- Public repo + private package → ❌ error
- Private repo + public package → ❌ error

## Example usage

```yaml
- name: Publish to GitHub Packages
  uses: ahincho/nova-shared-02-pipelines/.github/actions/nova-publish-aggregator@main
  with:
    registry: github-packages
    build-tool: gradle
    visibility: public
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Why this exists

The existing publish workflows (e.g., `reusable-publish-gradle-maven-central.yml`) hardcode their registry in the filename. This aggregator provides a single point of entry where the registry is selected at runtime, which simplifies:

- Matrix workflows (build once, publish to many registries)
- Workflows that need to publish to different registries based on context (e.g., main branch → GitHub Packages, tag → Maven Central)
- Reducing workflow file proliferation

## Related

- `reusable-publish-gradle-*.yml` — pre-built registry-specific workflows (used as-is for simple cases)
- `nova-gather-facts` — collects version, used implicitly by Gradle publish
- `nova-setup-gpg` — required for Maven Central publish
