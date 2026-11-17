# GitHub Actions CI (gh-ci branch)

An experimental CI path alongside the Tekton pipelines on `main`. A GitHub-hosted
`ubuntu-latest` runner builds the Quarkus server with Maven + Jib and pushes it
to Quay, then proposes the new image digest to the config repo as a pull request.

Tekton is untouched: it clones `main` and never sees this branch, and the images
are pushed under `gh-<sha>` tags instead of `:latest`.

## One-time setup (manual steps)

### 1. Create a fine-grained GitHub PAT for the config repo

1. Go to <https://github.com/settings/personal-access-tokens/new>.
2. Resource owner: your account; Repository access: **Only select repositories**
   → `tkiss28/grumpycat-config`.
3. Permissions: **Contents → Read and write**, **Pull requests → Read and write**.
4. Copy the token (starts with `github_pat_`).

The built-in `GITHUB_TOKEN` cannot open PRs in another repository, which is why
this PAT is needed.

### 2. Quay robot credentials

Reuse the robot from `quay-push-secret` in `cat-ci` (same one the Tekton
pipelines use): the robot's username (`rh-ee-tkiss+<robotname>`) and its token.

### 3. Add Actions secrets to the source repo

On `tkiss28/quarkus-grumpycat`: **Settings → Secrets and variables → Actions →
New repository secret**, three entries:

| Secret name        | Value                                        |
|--------------------|----------------------------------------------|
| `QUAY_USERNAME`    | Quay robot username                          |
| `QUAY_PASSWORD`    | Quay robot token                             |
| `CONFIG_PAT`       | the fine-grained PAT from step 1             |

## Running it

The workflow (`.github/workflows/build.yml`) triggers on every push to the
`gh-ci` branch. To re-run manually:

```bash
git commit --allow-empty -m "trigger ci" && git push origin gh-ci
```

The **Run workflow** button (`workflow_dispatch`) only appears once the workflow
file exists on the default branch, which is why pushes are the trigger for now.

## What it does

1. `mvn -pl quarkus-server -am package` with Jib build+push — credentials via
   the `QUARKUS_CONTAINER_IMAGE_USERNAME/PASSWORD` env vars, exactly like the
   Tekton `maven-caching` task.
2. Reads the pushed image's digest from `quarkus-server/target/jib-image.digest`.
3. Checks out `tkiss28/grumpycat-config`, runs
   `kustomize edit set image ...@sha256:<digest>` on `config/overlays/dev`,
   pushes branch `gh-ci/<sha>` and opens a PR against `main`.

## Verifying a run

- Actions log in `tkiss28/quarkus-grumpycat` → "Build and propose image digest".
- Quay: tag `gh-<commit sha>` on `quay.io/rh-ee-tkiss/quarkus-grumpycat`.
- An open PR in `tkiss28/grumpycat-config` with the digest change.

## Notes and limits

- Merging the PR updates the dev overlay; the next Tekton build-server run
  overwrites the digest again (both build the same source, so that is benign).
- The runner uses Maven Central directly — no Nexus cache, so the first build
  is slower.
- `kustomize` is preinstalled on GitHub-hosted Ubuntu runners.
- The melonjs client is not built here yet; add it as a matrix entry in
  `build.yml` when the server path is green.
