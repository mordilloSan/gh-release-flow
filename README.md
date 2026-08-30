# gh-release-flow

`gh-release-flow` is a GitHub CLI extension that manages a release from a
`dev/v*` branch:

```text
start-dev -> commit changes -> open-pr -> merge -> release workflow -> cleanup
```

It creates the release branch, opens and monitors the release pull request,
merges it only when the branch and PR are synchronized, watches the configured
GitHub Actions release workflow, and removes the release branch after that
workflow succeeds.

The extension does not create a tag or GitHub Release itself. That remains the
responsibility of your release workflow.

## Requirements

- Bash and Git.
- [GitHub CLI](https://cli.github.com/) installed and authenticated.
- A Git repository with an `origin` remote and a `main` branch, unless you
  configure another base branch.
- A GitHub Actions release workflow named `release.yml`, unless you configure
  another workflow.
- A recent GitHub CLI version that supports
  `gh pr merge --match-head-commit`.

The release workflow must run for the `pull_request` event, be associated with
the release branch's head commit, and publish the expected tag or GitHub
Release. The `merge` command uses those details to find the exact workflow run.

## Install

```bash
gh extension install mordilloSan/gh-release-flow
```

Upgrade an existing installation with:

```bash
gh extension upgrade release-flow
```

Display the available commands with:

```bash
gh release-flow --help
```

## Quick start

```bash
# Update main and create dev/v1.2.3.
gh release-flow start-dev v1.2.3

# Make and commit the release changes, then publish the branch and open its PR.
gh release-flow open-pr

# After the checks pass, merge the PR and watch the release workflow.
gh release-flow merge
```

Run `open-pr` and `merge` while checked out on the release branch. Release
branches must use `dev/v1.2.3` or `dev/v1.2.3-rc.1` format.

## Command reference

### `start-dev [version]`

Prepares a release branch from the configured base branch.

```bash
gh release-flow start-dev v1.2.3
gh release-flow start-dev v1.2.3-rc.1
VERSION=v1.2.3 gh release-flow start-dev
```

The command:

1. Refuses to run when tracked files have staged or unstaged changes.
2. Reads the version from the argument, then `VERSION`, or prompts for it.
3. Normalizes an uppercase `V` prefix to lowercase.
4. Validates the version and resulting `dev/<version>` Git branch name.
5. Fetches `origin`, checks out the base branch, and fast-forward pulls it.
6. Checks out an existing local release branch or creates and publishes a new
   one.

Accepted versions follow `vMAJOR.MINOR.PATCH` with an optional prerelease
suffix, such as `v2.0.0-beta.2`.

### `open-pr`

Publishes the current release branch, opens its pull request, and watches its
CI checks.

```bash
gh release-flow open-pr
```

The command:

1. Verifies the current branch is a valid `dev/v*` release branch and the
   tracked working tree is clean.
2. Uses the branch's configured push remote, falling back to `origin`.
3. Publishes a missing remote branch or pushes local commits when the local
   branch is strictly ahead.
4. Refuses to continue if the local branch is behind or has diverged from the
   remote branch.
5. Reuses an open PR from the push repository with the same head and base
   branches, or creates one titled `Release <version>`.
6. Generates the PR body from the repository's commit history.
7. Waits briefly for CI checks to register, then watches them to completion.
8. Prints the PR URL and exits unsuccessfully if checks fail or remain pending
   after monitoring is interrupted.

If an existing PR receives newly pushed commits, its generated body is
refreshed. If GitHub reports no checks after the registration retries, the
command warns and returns without watching; `merge` will still require checks
before it can merge the PR.

Re-run `open-pr` to resume check monitoring. It will reuse the existing branch
and PR.

### `merge`

Merges the release PR, watches the release workflow, and safely cleans up the
release branch.

```bash
gh release-flow merge
CONFIRM=0 gh release-flow merge
PR=123 gh release-flow merge
```

For an open PR, the command:

1. Finds the PR from the push repository for the current release branch, or
   validates the PR selected by `PR` against that repository.
2. Requires registered, successful PR checks.
3. Verifies the local commit, remote branch, and PR head are the same commit.
4. Shows the release version, PR, commit count, and exact head commit.
5. Requests confirmation unless `CONFIRM=0`.
6. Creates a merge commit with `--match-head-commit`, preventing a changed PR
   head from being merged accidentally.
7. Finds the configured release workflow run for the release head commit that
   was created no earlier than the PR merge, and watches it to completion.

After the workflow succeeds, it:

1. Checks out and fast-forward pulls the base branch.
2. Verifies the release commit is contained in the base branch.
3. Verifies the remote release branch has not advanced since the merge.
4. Deletes the remote branch with a commit-specific force-with-lease, then
   deletes the local branch.
5. Prints the GitHub Release URL when one is available.

If the PR is already merged, `merge` resumes at workflow monitoring and
cleanup. If the workflow fails, cannot be identified, or is interrupted, the
release branch is kept for debugging and the command can be run again.

`merge-release` is an alias for `merge`.

## Generated changelog

`open-pr` builds the pull request body from Git history. It selects the nearest
reachable `v*` tag other than the current version and includes non-merge commits
from that tag through `HEAD`. With no previous tag, it uses the full history.

Conventional Commit prefixes are grouped as follows:

| Prefix | PR section |
| --- | --- |
| `feat` | Features |
| `fix` | Bug Fixes |
| `perf` | Performance |
| `refactor` | Refactoring |
| `docs` | Documentation |
| `style` | Style |
| `test` | Tests |
| `build` | Build |
| `ci` | CI/CD |
| `chore` | Chores |
| anything else | Other Changes |

Scoped prefixes such as `feat(api):` are supported. Each entry includes the
subject, linked short commit hash, and author name as plain text. Merge commits,
commits authored by `github-actions[bot]`, and commits whose subject is
`changelog` are omitted. The body ends with unique contributors and a
full-changelog link.

The repository used in commit links is resolved from `REPO`, then
`GITHUB_REPOSITORY`, then the `origin` URL.

## Configuration

All configuration is provided through environment variables.

| Variable | Default | Used by | Purpose |
| --- | --- | --- | --- |
| `DEFAULT_BASE_BRANCH` | `main` | all commands | Branch from which releases start and into which release PRs merge. |
| `RELEASE_WORKFLOW` | `release.yml` | `merge` | Workflow file or name passed to `gh run list --workflow`. |
| `VERSION` | prompt | `start-dev` | Version used when no command argument is provided. |
| `REPO` | current repository | `open-pr`, `merge` | Repository passed to GitHub CLI as `--repo`; also used for changelog links. |
| `PR` | auto-detected | `merge` | Specific PR number to validate and merge. |
| `CONFIRM` | `1` | `merge` | Set to `0` to skip the merge confirmation prompt. |
| `GITHUB_REPOSITORY` | derived from `origin` | `open-pr` | Fallback `owner/repo` used only for generated changelog links. |

Examples:

```bash
DEFAULT_BASE_BRANCH=trunk gh release-flow start-dev v1.2.3
RELEASE_WORKFLOW=publish.yml gh release-flow merge
REPO=owner/project gh release-flow open-pr
PR=123 CONFIRM=0 gh release-flow merge
```

`REPO` changes the repository targeted by `gh` commands; Git operations still
use the current checkout and its configured remotes.

## Safety and recovery

- Every command refuses staged or unstaged changes to tracked files. Untracked
  files do not block the flow.
- `open-pr` never overwrites a remote branch and refuses stale or diverged
  histories.
- `merge` refuses missing checks and mismatched local, remote, or PR commits.
- Remote cleanup uses `--force-with-lease` for the exact merged commit.
- Branches are deleted only after a successful release workflow and an ancestry
  check on the updated base branch.
- Both `open-pr` and `merge` are resumable by running the same command again.

## Shell function map

The extension is a single Bash executable. Its public interface is the three
commands above; these internal functions implement that interface.

| Function | Responsibility |
| --- | --- |
| `die` | Prints a consistent error and exits non-zero. |
| `require_clean` | Rejects staged or unstaged tracked-file changes. |
| `require_gh` | Verifies that GitHub CLI is available. |
| `push_repo_owner` | Resolves the owner of the release branch's push repository. |
| `find_pr` | Finds a branch PR owned by that push repository. |
| `read_version` | Reads, normalizes, and validates a version, then derives its release branch. |
| `read_release_branch` | Validates the current branch and extracts its version. |
| `previous_tag` | Finds the nearest reachable release tag. |
| `generate_changelog` | Groups commits, renders contributors, and adds compare or release links. |
| `generate_pr_body` | Resolves repository and tag context and writes the temporary PR body. |
| `start_dev` | Updates the base branch and checks out or creates the release branch. |
| `open_pr` | Synchronizes the release branch, creates or updates its PR, and monitors checks. |
| `merge_release` | Validates and merges the PR, watches the release workflow, and cleans up branches. |
| `usage` | Prints command-line usage. |
| `main` | Validates arguments, resolves aliases, and dispatches commands. |

## Make compatibility

The extension accepts the environment variables used by the previous Make
flow. Existing targets can delegate directly to it:

```make
.PHONY: start-dev open-pr merge-release

start-dev open-pr merge-release:
	gh release-flow $@
```

## Development

Run the self-contained integration test with:

```bash
./test
```

It creates temporary local repositories and a fake `gh` executable to exercise
PR creation, changelog rendering, already-merged recovery, safe branch cleanup,
and version normalization without modifying the working repository.

Validate the shell scripts with:

```bash
make check
```
