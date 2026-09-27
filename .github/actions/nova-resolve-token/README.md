# nova-resolve-token

Resolves the right token for **cross-repo GitHub Packages reads**. Priority order:

1. **GitHub App installation token** (preferred - auto-managed, granular scope, no human rotation)
   - Generated via `actions/create-github-app-token@v2` when `app-id` and `app-private-key` inputs are provided.
   - Requires a GitHub App installed on both the calling repo AND the target repo.
2. `GITHUB_TOKEN` (works only for same-repo reads; fails with HTTP 401 on cross-repo)
3. `NOVA_PACKAGES_READ_TOKEN` (transitional PAT - emit a `::notice::` encouraging migration to the App)
4. `NOVA_RELEASE_PAT` (legacy PAT - already removed from all callers; emit a `::warning::`)

## Why this exists

The GitHub Actions expression engine does NOT short-circuit on `secrets.X || secrets.Y`:

```yaml
# WRONG: when secrets.X is unset (null), this evaluates to "1" (one char)
# instead of falling back to secrets.Y. Discovered in commit bb67ea7.
packages-read-token: ${{ secrets.NOVA_PACKAGES_READ_TOKEN || secrets.NOVA_RELEASE_PAT }}
```

Doing the comparison in shell via `[ -n "${TOKEN_X}" ]` is correct and well-behaved.

## Inputs

| Input | Required | Description |
|---|---|---|
| `app-id` | no | GitHub App ID (numeric string). If empty, App auth is skipped. |
| `app-private-key` | no | GitHub App private key (PEM contents, multi-line). If empty, App auth is skipped. |
| `app-owner` | no | GitHub user/org that owns the App. Default: `ahincho`. Only used when App creds are set. |

## Outputs

| Output | Description |
|---|---|
| `value` | Resolved token value (string). Empty when no source is available. |
| `source` | Which source was selected: `GITHUB_APP_TOKEN`, `GITHUB_TOKEN`, `NOVA_PACKAGES_READ_TOKEN`, `NOVA_RELEASE_PAT`, or `NONE`. |

## Setup (one-time, for consumers)

### Option A: GitHub App authentication (recommended)

1. Create a GitHub App at <https://github.com/settings/apps/new> (user-level, since this org does not have one yet):
   - **Name**: e.g. `Nova Platform Bot` (must be unique across GitHub)
   - **Homepage URL**: your org/repo URL
   - **Repository permissions**: `Contents: Read-only`, `Packages: Read-only`
   - **No webhook** needed (we use installation tokens imperatively)
   - After creation, note the **App ID** and generate a **private key** (downloads `.pem` file)
2. Install the App on the repos that publish packages AND on the repos that consume them (cross-repo read requires install on both)
3. Add two secrets to each consuming repo (Settings → Secrets and variables → Actions):
   - `NOVA_PLATFORM_APP_ID` — the numeric App ID
   - `NOVA_PLATFORM_APP_PRIVATE_KEY` — paste the **entire contents** of the `.pem` file (multi-line is OK)
4. Wire those secrets into the `nova-resolve-token` invocation in your workflows:
   ```yaml
   - uses: ahincho/nova-shared-02-pipelines/.github/actions/nova-resolve-token@<pinned-sha>
     with:
       app-id: ${{ secrets.NOVA_PLATFORM_APP_ID }}
       app-private-key: ${{ secrets.NOVA_PLATFORM_APP_PRIVATE_KEY }}
   ```
5. (Optional) Once the App is installed everywhere, delete the `NOVA_PACKAGES_READ_TOKEN` PAT from each repo's secrets list.

### Option B: PAT (transitional)

1. Generate a fine-grained PAT at <https://github.com/settings/tokens?type=beta>:
   - **Resource owner**: your org / personal account
   - **Repository access**: only the repos that publish packages (the ones you read from)
   - **Permissions**: `Contents: Read-only`, `Packages: Read-only`
2. Add as repo secret `NOVA_PACKAGES_READ_TOKEN`.
3. Do NOT pass `app-id` / `app-private-key` to `nova-resolve-token`. The action falls back to the PAT automatically.

## Example usage

### With GitHub App (recommended)

```yaml
- name: Nova Resolve Token (GitHub App)
  id: resolve_token
  uses: ahincho/nova-shared-02-pipelines/.github/actions/nova-resolve-token@<pinned-sha>
  with:
    app-id: ${{ secrets.NOVA_PLATFORM_APP_ID }}
    app-private-key: ${{ secrets.NOVA_PLATFORM_APP_PRIVATE_KEY }}

- name: Nova Setup Java
  uses: ahincho/nova-shared-02-pipelines/.github/actions/nova-setup-java@<pinned-sha>
  with:
    java-version: '25'
    build-tool: gradle
    packages-read-token: ${{ steps.resolve_token.outputs.value }}
```

### Without App (PAT fallback)

```yaml
- name: Nova Resolve Token (PAT fallback)
  id: resolve_token
  uses: ahincho/nova-shared-02-pipelines/.github/actions/nova-resolve-token@<pinned-sha>
  # no `with:` block - App auth skipped, falls back to PAT
```

## Debugging

Inspect the `source` output to see which token was selected:

```yaml
- name: Debug token source
  run: echo "Resolved token from: ${{ steps.resolve_token.outputs.source }}"
```

You should see `GITHUB_APP_TOKEN` after setting up the App. Anything else means App auth was skipped (creds empty) or the App is not installed on the target repo.

## Related

- `nova-setup-java` - accepts the resolved `value` via its `packages-read-token` input (already falls back to `github.token` internally if the input is empty).
- `nova-validate-build` - scans tracked files for leaked secrets before any of this runs.
- [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token) - the official action used for App installation token generation.