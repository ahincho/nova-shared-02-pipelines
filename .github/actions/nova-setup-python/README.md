# nova-setup-python

Installs [uv](https://docs.astral.sh/uv/) and Python, restores and saves the GitHub Actions cache, and syncs the project's locked dependencies. It is the Python counterpart of `nova-setup-java`.

## What it does

1. **Validates** the inputs and the project: `pyproject.toml` and `uv.lock` must exist in `working-directory`, and `cache`, `save-cache` and `sync` must be `'true'` or `'false'`.
2. **Installs uv** with `astral-sh/setup-uv`, pinned by SHA.
3. **Selects Python**: `python-version` when given, otherwise the project's `.python-version`, otherwise `requires-python`. uv always uses its own managed CPython (`UV_PYTHON_PREFERENCE=only-managed`), never the interpreter of the runner image.
4. **Caches** the uv package cache and the managed Python in the calling repository's GitHub Actions cache. The key hashes `uv.lock` and `.python-version`.
5. **Syncs** with `uv sync --locked`, which fails when `uv.lock` is out of date with `pyproject.toml`.
6. **Writes a job summary** with the uv and Python versions and whether each cache was restored.

## Inputs

| Input | Default | Description |
|---|---|---|
| `python-version` | `''` | Python version, e.g. `'3.14'`. Empty reads `.python-version`, then `requires-python` |
| `uv-version` | `''` | uv version, e.g. `'0.12.18'`. Empty reads `required-version` from `uv.toml` or `pyproject.toml`, then installs the latest release |
| `working-directory` | `'.'` | Directory with `pyproject.toml` and `uv.lock`, relative to the repository root |
| `cache` | `'true'` | Cache uv packages and the managed Python. Maps to setup-uv's `enable-cache: auto` |
| `save-cache` | `'true'` | Upload the cache at the end of the job. Set `'false'` on secondary jobs that share the key |
| `sync` | `'true'` | Run `uv sync --locked` after the setup |

## Outputs

| Output | Example |
|---|---|
| `uv-version` | `0.12.18` |
| `python-version` | `3.14.7` (empty when `sync` is `'false'`) |
| `cache-hit` | `true` / `false` |
| `python-cache-hit` | `true` / `false` |

## Example usage

```yaml
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
    with:
      persist-credentials: false

  - name: Nova Setup Python
    id: python
    uses: ahincho/nova-shared-02-pipelines/.github/actions/nova-setup-python@<pinned-sha>

  - name: Run a project script
    run: uv run --no-sync python scripts/check.py
```

The environment is already synced, so later steps use `uv run --no-sync`: nothing can re-resolve dependencies after `--locked` checked them.

A job that runs next to another job using this action with the same lockfile should pass `save-cache: 'false'`. Both jobs compute the same key, and only the first upload succeeds; the second one fails with a conflict warning.

## Cache behaviour

- The cache belongs to the repository that calls the action, not to `nova-devops`.
- A run on the default branch creates a cache that every branch and pull request can restore. A cache created in a pull request is only visible to that pull request.
- Changing `uv.lock` or `.python-version` changes the key, so the next run starts cold and saves a new cache.
- With `cache: 'true'`, setup-uv still skips the cache on `release`, tag pushes, `pull_request_target` and `workflow_run` events, to keep a poisoned cache away from privileged jobs.

## Why this exists

Every Python repository needs the same four steps before running anything: install uv, pick the interpreter, restore the cache and install the locked dependencies. Getting them subtly wrong fails silently: a pyproject edit that busts the cache on every run, a runner-image Python that changes under the project, or a sync that resolves versions nobody locked. This action does them once, with those decisions made explicit.

## Related

- `reusable-build-python.yml` - lint, format check and tests on top of this action
- `nova-setup-java` - the equivalent setup for Maven and Gradle projects
