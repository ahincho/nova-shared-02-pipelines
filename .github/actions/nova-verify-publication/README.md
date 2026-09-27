# nova-verify-publication

Downloads the artifacts a job has just published to GitHub Packages and **fails the job if any of
them cannot be downloaded**.

## Why this exists

A publish step can finish green without leaving anything a consumer can download. In July 2026
`nova-api-standard-quarkus-extension` was published five times with the run green, while
`maven.pkg.github.com` answered 404 for its `.pom` and `.jar`; only `maven-metadata.xml` was
updated. Nobody noticed until a consumer failed to resolve it weeks later. ADR-039, in
`nova-shared-01-docs`, makes this check part of every publish workflow, so the run that
publishes is the one that says whether the publication worked.

The action asks for each file only **after** the publish step. A path requested before the upload
may get a 404 that stays cached for a while, and the check would then fail on an artifact that
is fine. Each file is retried until `timeout-seconds`, because a freshly uploaded file can take a
few seconds to become downloadable.

## Inputs

| Input | Required | Description |
|---|---|---|
| `group-id` | yes | Maven `groupId` of the published artifacts, e.g. `pe.edu.nova.java.libs`. |
| `artifact-ids` | yes | Space-separated `artifactId`s the job published, one per module of a multi-module build. |
| `version` | yes | Published version. A leading `v` is stripped, so a tag such as `v1.2.3` works as-is. |
| `extensions` | no | Space-separated extensions to download per artifact. Default `pom jar`; use `pom` for a BOM or a parent POM. |
| `repository` | no | `owner/name` of the repository whose registry holds the artifacts. Default: the calling repository. |
| `token` | yes | Token with `packages: read` on that repository, usually `github.token`. |
| `timeout-seconds` | no | How long to keep retrying each file. Default `300`. |

## Usage

Right after the publish step of `publish-on-tag.yml`:

```yaml
      - name: Verify the publication can be downloaded
        if: steps.detect.outputs.should_publish == 'true'
        uses: ahincho/nova-shared-02-pipelines/.github/actions/nova-verify-publication@main
        with:
          group-id: pe.edu.nova.java.starters
          artifact-ids: nova-api-standard-quarkus-extension
          version: ${{ steps.detect.outputs.tag }}
          token: ${{ github.token }}
```

The job needs `packages: read`, which `packages: write` already includes.
