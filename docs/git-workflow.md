# Git workflow assumptions

`gh-release-flow` encodes one Git and GitHub workflow. This page lists what
that workflow assumes about branches, versions, commits, pull requests and the
release workflow.

The extension enforces some of these assumptions and stops with an error when
one breaks. It cannot see the others, and breaking them gives a wrong result
instead of an error. Each assumption ends with **Enforced** or **Not
enforced**.

## Base branch

- **Releases start from one base branch and merge back into it.** That branch
  is `main`, or the one named by `DEFAULT_BASE_BRANCH`. There is no `develop`
  branch and no long-lived maintenance branch. `start-dev` always branches from
  the tip of the base branch, so the flow has no way to patch an older release
  line. *Not enforced.*
- **The local base branch has no commits of its own.** `start-dev` and the
  cleanup in `merge` update it with `git pull --ff-only`, which fails when the
  local branch has diverged from `origin`. *Enforced: the pull fails and the
  command stops.*
- **Other pull requests may merge into the base branch** between releases, for
  example feature or Dependabot PRs. They ship in the next release branch cut
  after them and appear in its changelog.
- **The base branch does not change while a release branch is open.** If
  another PR, a direct push, or a second release lands on the base branch
  first, those changes ship in this release, because the release merge commit
  contains them. They appear in no changelog: this release's changelog was
  built from the release branch, which lacks them, and the next changelog
  starts at a tag that already contains them. To list them, merge the base
  branch into the release branch and re-run `open-pr` before `merge`. *Not
  enforced.*

## Release branches

- **A release branch is named `dev/vX.Y.Z` or `dev/vX.Y.Z-<prerelease>`.** The
  branch name is the only record of the version. The tag, the PR title and the
  GitHub Release name all come from it. *Enforced by every command and by the
  release workflow from `init`.*
- **No branch is named `dev`.** Git cannot hold `dev` and `dev/v1.2.3` at the
  same time. *Enforced by `start-dev`.*
- **Each release has its own short-lived branch.** `start-dev` creates it from
  the tip of the base branch. After the release workflow succeeds, `merge`
  deletes it locally and on the remote, so build nothing on top of it.
- **The release branch lives in the repository that receives the PR.** A PR
  from a fork gets a read-only token in its release run, so it can never
  publish. *Enforced: `merge` refuses fork PRs and the `init` workflow skips
  them.*
- **`open-pr` and `merge` run with the release branch checked out and no
  changes to tracked files.** Untracked files do not matter. *Enforced.*
- **Nobody else pushes to the release branch while `open-pr` or `merge`
  runs.** *Enforced: `open-pr` refuses a local branch that is behind or has
  diverged, `merge` requires the local head, remote branch and PR head to be
  the same commit, and cleanup keeps the branch if the remote advanced after
  the merge.*

## Versions and tags

- **Versions look like `vMAJOR.MINOR.PATCH`, with an optional prerelease
  suffix such as `-rc.1`.** Build metadata such as `+build.5` is rejected, and
  an uppercase `V` becomes `v`. *Enforced.*
- **A prerelease goes through the same flow as a final release.** It gets its
  own branch and PR and merges into the base branch, so `v1.2.3-rc.1` is on
  `main` before `v1.2.3`. The `v1.2.3` changelog then starts at
  `v1.2.3-rc.1`, not at `v1.2.2`. The `init` workflow publishes any version
  that contains a hyphen as a GitHub prerelease.
- **Each new version is higher than the last.** `start-dev` shows the latest
  release tag but accepts any version whose tag does not exist on `origin`.
  *Not enforced.*
- **Only the release workflow creates tags.** The extension never creates a
  tag itself. The `init` workflow creates the tag through `gh release create`,
  on the merge commit. Do not create tags or GitHub Releases by hand.
  *Partly enforced: `start-dev` refuses a version whose tag already exists on
  `origin`, and every branch push uses `--no-follow-tags`, so local tags never
  reach the remote.*
- **Release tags are on commits in the base branch's history.** The latest
  release is the nearest `v*.*.*` tag behind `origin/<base>`. The changelog's
  previous release is the nearest such tag behind `HEAD`, other than the
  version being released. Both are found by history, not by version number.
  A tag outside the base branch's history is never found. A stray local
  `v*.*.*` tag is used as if it were a release. *Not enforced.*

## Commits and the changelog

- **Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/).**
  Other subjects go under Other Changes. *Not enforced.*
- **Merge commits carry no changelog content.** The changelog skips them, so
  the commits a merge brings in are listed and the merge itself is not.
  Commits by `github-actions[bot]` and commits whose subject is `changelog`
  are skipped too.
- **Author names follow `.mailmap`.** Without one, each spelling of a name is
  listed as a separate contributor.
- **The repository is on github.com.** Commit and compare links in the
  changelog always point at `https://github.com/`, even when the remote is a
  GitHub Enterprise host.

## Pull requests and merging

- **Each release branch has one open PR into the base branch.** `open-pr`
  reuses an open PR with the same head and base from the push repository, or
  creates one titled `Release vX.Y.Z`.
- **The release branch has at least one commit the base branch lacks.**
  GitHub refuses a pull request with nothing to merge, so a release of changes
  that were all merged into the base branch by other PRs needs a commit of its
  own on the release branch, such as a documentation change. *Enforced by
  GitHub: `open-pr` stops where GitHub refuses to create the PR.*
- **The PR body is generated, and it becomes the release notes.** Every
  `open-pr` run regenerates the body, replacing text edited in by hand. The
  `init` workflow publishes the body as it stands at merge time.
- **The repository allows merge commits and has no merge queue.** `merge` runs
  `gh pr merge --merge --match-head-commit <head>`. *Enforced: a squash-only or
  rebase-only repository fails at the merge. If a merge queue takes the PR
  instead of merging it, `merge` stops and asks to be re-run once GitHub
  merges the PR.*
- **Branch protection is satisfied before `merge`.** The extension does not
  request reviews or bypass protection rules. If a required review is missing,
  the merge fails and the branch is kept.
- **At least one CI check runs on the release PR, and every check passes.**
  A skip-CI marker such as `[skip ci]` in the last commit message blocks the
  release until a new commit is pushed. *Enforced by `merge` and by the `init`
  workflow.*

## Release workflow

- **The release workflow is on the base branch before the release PR
  exists.** Its file is `release.yml`, or the one named by
  `RELEASE_WORKFLOW`.
- **It runs on the `pull_request` event.** `merge` finds the run with
  `gh run list --event pull_request --commit <release head>`, created no
  earlier than the merge. A workflow triggered by `push` or by a tag is never
  found. *Enforced: `merge` stops and keeps the branch.*
- **It creates the tag and the GitHub Release, titled with the tag.** If the
  release has no title, `merge` sets it to the version and prints a warning.
- **The release branch is deleted only after the workflow succeeds.** If the
  workflow fails, the branch is kept for debugging, and re-running `merge`
  resumes from the workflow watch.

## Local setup

- **`origin` is the GitHub repository.** `start-dev` fetches and pushes to
  `origin`, checks for an existing tag there, and reads the latest release
  from `origin/<base>`. `open-pr` and `merge` use the remote the branch tracks,
  falling back to `origin`.
- **No other worktree has the base branch checked out.** Cleanup checks out
  the base branch. *Enforced: cleanup stops and says how to resume.*
- **GitHub CLI 2.40 or newer is installed and authenticated** with permission
  to push branches and merge pull requests.

## Outside this workflow

These setups conflict with the assumptions above:

- Squash or rebase merges, and merge queues.
- Release PRs from forks.
- Maintenance branches that patch older release lines.
- Tags or GitHub Releases created by hand.
- Changelog links to a GitHub Enterprise host.
