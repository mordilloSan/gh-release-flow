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

Its `init` command also starts new repositories: run in a project folder, it
creates the GitHub repository and gives it the files, settings and rulesets
kept in your account's [repository defaults](#repository-defaults).

## Requirements

- Bash and Git.
- [GitHub CLI](https://cli.github.com/) 2.40 or newer, installed and
  authenticated.
- A Git repository with an `origin` remote and a `main` branch, unless you
  configure another base branch. With
  [repository defaults](#repository-defaults), `init` creates both.
- For `init` with repository defaults, admin access to the repository, which
  its settings and rulesets need. When Git pushes over HTTPS with GitHub CLI's
  credentials, the token also needs the `workflow` scope to push the workflow
  files; `gh auth refresh -s workflow` adds it.
- No branch named `dev`. Git cannot hold both `dev` and `dev/v1.2.3`.
- Release branches pushed to the repository that receives the PR. `merge`
  refuses PRs from forks, because their release workflow cannot publish.
- Merge commits allowed on the base branch, and no merge queue. `merge` merges
  the PR directly with a merge commit.
- A GitHub Actions release workflow named `release.yml`, unless you configure
  another workflow. [`init`](#init---force) writes one for you.

The release workflow must run for the `pull_request` event, be associated with
the release branch's head commit, and publish the expected tag or GitHub
Release. The `merge` command uses those details to find the exact workflow run.
A GitHub Release is named after its tag: pass `--title "$TAG"` to
`gh release create`, because a release created with `--notes` and no `--title`
has no name.

[Git workflow assumptions](docs/git-workflow.md) lists everything the flow
assumes about branches, tags, commits and merges, and which assumptions it
enforces.

## Install

```bash
gh extension install mordilloSan/gh-release-flow
```

Upgrade an existing installation to the latest `main` from any directory with:

```bash
gh release-flow upgrade
```

GitHub CLI checks for a newer version once a day when the extension runs and
prints an upgrade notice when one is available.

Optionally add user-wide Make targets, so `make init`, `make start-dev`,
`make open-pr` and `make merge-release` work in every folder:

```bash
gh release-flow setup-make
```

Display the available commands and the installed version with:

```bash
gh release-flow help
gh release-flow version
```

## Quick start

```bash
# In a new project folder, set up the repository from your account's defaults.
# Without defaults, this writes the release workflow; commit it to main.
gh release-flow init

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

### `init [--force]`

Sets up the repository in the current folder. With
[repository defaults](#repository-defaults) in your account's `.github`
repository, it creates the GitHub repository when there is none and gives it
the default files, settings and rulesets. Without them, it writes the release
workflow only, as it always did.

```bash
gh release-flow init
gh release-flow init --force
```

It runs these steps in order. A step that fails stops the run. Answering no to
a question skips that step only, except where noted. Pressing Enter, or running
without a terminal, answers no.

1. **Defaults.** It works out the owner: the owner of the `origin` remote, or,
   without `origin`, the account GitHub CLI is signed in to. It then downloads
   `<owner>/.github/defaults/` through the GitHub API. When there is no such
   folder, it says so, writes the release workflow as described under
   [Without defaults](#without-defaults), and stops there.
2. **Git.** Outside a Git working tree, it runs `git init -b main` (the base
   branch) in the current folder. The current branch must be the base branch;
   otherwise it stops and asks you to switch.
3. **GitHub repository.** It uses the repository behind `origin`. Without
   `origin`, it asks `Create <owner>/<folder> (public)? [y/N]` and runs
   `gh repo create <owner>/<folder> --public --source . --remote origin`. A no
   stops the run: link an existing repository with
   `git remote add origin <URL>`, then run `init` again.
4. **Files.** It copies each file under `defaults/files/` that the repository
   does not have, with its placeholders filled, then writes the release
   workflow from its built-in template. It lists each file as new, same or
   kept. A file you already have that differs is kept; `--force` replaces it.
5. **Commit and push.** If it wrote any file, it lists every commit a push of
   the base branch would publish, the new one and your own unpushed commits
   included, and asks `Commit and push these to <owner>/<repo> main? [y/N]`.
   On yes, it commits exactly the files it wrote, as
   `chore: add repository defaults`, and pushes the base branch, which then
   tracks `origin` if it tracked nothing. Nothing else is committed, even if it
   is staged. When `origin`'s base branch has commits that yours lacks, `init`
   stops before writing any file: pull first. When the repository already has a
   branch ruleset, it does not push: the files stay written and uncommitted,
   for you to bring in through a pull request.
6. **Settings.** It lists the settings files and asks `Apply? [y/N]`, then
   makes one API call per file. Settings are not read back and compared:
   every run asks again and sends them again, which changes nothing that is
   already set. CodeQL default setup is held back until the base branch is on
   GitHub, so it has code to analyse.
7. **Rulesets.** Always last. It lists the rulesets the repository does not
   have by name and asks `Create? [y/N]`. A ruleset with the same name is
   kept, never updated. A branch ruleset is held back while any of the
   default files is not on `origin`'s base branch, because it would then
   require a pull request for the push that brings them; run `init` again once
   they are there. Tag rulesets do not wait.

The run ends with one summary line per step: done, already done, skipped,
held back or declined. A second run on a finished repository writes no file,
creates nothing, and sends the settings again. If a settings or ruleset call
fails, `init` stops and says which calls were made and which were not; run it
again once the cause is fixed.

`make init`, from [`setup-make`](#setup-make), runs `gh release-flow init`.
Run `gh release-flow init --force` directly to replace files.

#### Without defaults

Without `<owner>/.github`, or without its `defaults/` folder, `init` writes a
known-good release workflow, at `.github/workflows/release.yml`, or at the
file named by `RELEASE_WORKFLOW`. It needs a Git working tree, works from any
folder inside the repository, writes at its root, and never commits. It does
not run `git init` or create a GitHub repository.

```bash
gh release-flow init
git add .github/workflows/release.yml
git commit -m 'ci: add release workflow'
```

An existing file with the same content is left alone. A different one is
refused, so your edits are never lost, until you review it and pass `--force`
to replace it. With defaults, a different release workflow is kept and listed
as kept, like any other file.

#### The release workflow

The workflow runs when a pull request into the base branch
(`DEFAULT_BASE_BRANCH`, `main` by default) is merged. It does nothing unless
the PR came from a `dev/vX.Y.Z` branch in the same repository. It then:

1. Requires every other check on the PR to have passed (or been skipped), and
   at least one to exist, as `merge` does. The release workflow itself is
   left out of that count.
2. Creates the GitHub Release for the tag in the branch name, titled with the
   tag, with the PR body (the changelog from `open-pr`) as its notes. A
   `dev/v1.2.3-rc.1` branch makes a prerelease.

It publishes no assets, so add `gh release create` arguments such as file
paths if you ship any. Commit the workflow to the base branch before the first
`start-dev`, so GitHub runs it for the release PR; with defaults, `init`
offers to commit and push it. `RELEASE_WORKFLOW` must be a file name ending in
`.yml` or `.yaml`.

### `start-dev [version]`

Prepares a release branch from the configured base branch.

```bash
gh release-flow start-dev v1.2.3
gh release-flow start-dev v1.2.3-rc.1
VERSION=v1.2.3 gh release-flow start-dev
```

The command:

1. Refuses to run when tracked files have staged or unstaged changes, except on
   the base branch. There it lists the changes once the version is known and
   asks whether to move them to the release branch. Pressing Enter, or running
   without a terminal, refuses as before.
2. Fetches `origin`, then reads the version from the argument, then `VERSION`,
   or prompts for it, first showing the latest release tag on the base branch.
3. Normalizes an uppercase `V` prefix to lowercase.
4. Validates the version and resulting `dev/<version>` Git branch name. It
   refuses to continue if a `dev` branch exists, or if the version's tag
   already exists on `origin`.
5. Checks out the base branch and fast-forward pulls it.
6. Checks out an existing local release branch, checks out one that exists only
   on `origin`, or creates and publishes a new one.

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
2. Uses the remote the branch tracks (`branch.<name>.remote`), falling back
   to `origin`. Unless `REPO` is set, GitHub CLI uses that remote's repository,
   and the command prints its name.
3. Publishes a missing remote branch or pushes local commits when the local
   branch is strictly ahead.
4. Refuses to continue if the local branch is behind or has diverged from the
   remote branch.
5. Reuses an open PR from the push repository with the same head and base
   branches, or creates one titled `Release <version>`.
6. Generates the PR body from the repository's commit history, asking GitHub
   about each commit for its pull request, its author's login and any advisory
   its `Security:` footer names (see [Generated changelog](#generated-changelog)).
7. Waits briefly for CI checks to register, then watches them to completion.
8. Prints the PR URL and exits unsuccessfully if checks fail or are still
   pending when monitoring ends.

Every run regenerates the PR body, so an existing PR always shows the current
changelog. Text edited into the body by hand is replaced. If GitHub reports no checks after the registration retries, the
command warns and returns without watching; `merge` will still require checks
before it can merge the PR.

Ctrl+C stops the command immediately. Re-run `open-pr` to resume check
monitoring. It will reuse the existing branch and PR.

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
2. Refuses PRs from forks.
3. Verifies the local commit, remote branch, and PR head are the same commit.
4. Requires registered, successful PR checks on that commit.
5. Shows the release version, PR, commit count, and exact head commit.
6. Requests confirmation unless `CONFIRM=0`.
7. Creates a merge commit with `--match-head-commit`, preventing a changed PR
   head from being merged accidentally.
8. Finds the configured release workflow run for the release head commit that
   was created no earlier than the PR merge, and watches it to completion.

After the workflow succeeds, it:

1. Checks out and fast-forward pulls the base branch.
2. Verifies the release commit is contained in the base branch.
3. Verifies the remote release branch has not advanced since the merge.
4. Deletes the remote branch with a commit-specific force-with-lease, then
   deletes the local branch.
5. Prints the GitHub Release URL when one is available. If that release has no
   title, it sets the title to the version and warns that the release workflow
   should pass `--title`.

If the PR is already merged, `merge` resumes at workflow monitoring and
cleanup. If the workflow fails, cannot be identified, or is interrupted, the
release branch is kept for debugging and the command can be run again. If a
cleanup step fails after switching to the base branch, the error says how to
resume.

`merge-release` is an alias for `merge`.

### `setup-make`

Installs user-wide Make targets that run the commands from any folder:

| Target | Runs |
| --- | --- |
| `make init` | `gh release-flow init` |
| `make start-dev` | `gh release-flow start-dev` |
| `make open-pr` | `gh release-flow open-pr` |
| `make merge-release` | `gh release-flow merge-release` |
| `make rf-version` | `gh release-flow version` |
| `make rf-upgrade` | `gh release-flow upgrade` |

Variables pass through, for example `make start-dev VERSION=v1.2.3`. Command
options do not, so run `gh release-flow init --force` directly.

```bash
gh release-flow setup-make
```

It writes two files and adds two lines to `~/.bashrc`, and to `~/.zshrc` when
that file exists:

- `~/.config/make/release-flow.mk` holds the targets. The shell profile adds
  it to `MAKEFILES`, so GNU Make loads it before every Makefile.
- `~/.config/make/release-flow.sh` holds a `make` shell function. With it,
  `make help` ends with a line that lists the targets, after the project's
  own `help` output when the Makefile has a `help` target. Plain `make` does
  the same when the Makefile's default goal is `help`, whether it sets
  `.DEFAULT_GOAL := help` or `help` is its first target (a default target that
  only depends on `help` does not count). In a folder without a Makefile,
  plain `make` prints only that line. Other `make` runs are unchanged.

Run it again at any time to rewrite both files. It says when a new terminal
is needed to load the changes. A `release-flow.mk` that `setup-make` did not
write is replaced only after you confirm.

If a project Makefile already defines one of these targets, such as its own
`init`, make warns "overriding recipe" on every run there; delete those targets
from the project Makefile. Make cannot load files from a home path that contains spaces, so
`setup-make` refuses to run there.

### `upgrade`

Upgrades the installed extension to the latest commit on `main`. It runs
`gh extension upgrade release-flow` and works from any directory. When the
Make targets from `setup-make` are installed, it then runs the upgraded
`setup-make` to refresh them, so `make rf-upgrade` updates both.

```bash
gh release-flow upgrade
```

### `version`

Prints the installed extension version. `--version` is an alias.

The version is the release tag of the extension's own Git clone, which is how
`gh extension install` installs it, so nothing is bumped by hand for a release.
A checkout ahead of the last release prints a form like `v1.7.0-3-g1a2b3c4`,
and a copy of the script outside its clone prints `unknown`.

```console
$ gh release-flow version
gh-release-flow v1.3.0
```

### `help`

Prints command-line usage. `--help` and `-h` are aliases.

```console
$ gh release-flow help
Usage:
  gh release-flow init [--force]
  gh release-flow start-dev [version]
  gh release-flow open-pr
  gh release-flow merge
  gh release-flow setup-make
  gh release-flow upgrade
  gh release-flow version
  gh release-flow help
```

## Repository defaults

`init` sets up new repositories from defaults that belong to your account,
not to gh-release-flow. They live in the `defaults/` folder of the account's
`.github` repository, `<owner>/.github`, which GitHub already reads for an
account's default community health files. Edit them there, in one place, and
every later `init` uses them. `init` downloads them through the GitHub API
and reads them as data; it never runs anything from them.

```text
defaults/
  files/                              copied into the repository, path for path
    LICENSE
    SECURITY.md
    .github/CODEOWNERS
    .github/workflows/check.yml
  settings/                           one file per GitHub API call
    repo.json
    actions-permissions.json
    actions-workflow.json
    vulnerability-alerts
    automated-security-fixes
    private-vulnerability-reporting
    immutable-releases
    code-scanning-default-setup.json
  rulesets/                           one ruleset per file
    main.json
    release-tags.json
```

The owner is the owner of the `origin` remote, or, without `origin`, the
account GitHub CLI is signed in to. Without `<owner>/.github`, or without its
`defaults/` folder, `init` [writes the release workflow only](#without-defaults).
Any of the three folders, and any file in them, may be left out. A file
outside them is reported and skipped.

### Files

Every file under `defaults/files/` is copied to the same path in the
repository, unless the repository already has a file there. These
placeholders are replaced in every copied file, and nothing else is
templated:

| Placeholder | Replaced with |
| --- | --- |
| `{{owner}}` | The repository owner, such as `octocat`. |
| `{{repo}}` | The repository name. |
| `{{year}}` | The current year, such as `2026`. |

A file without placeholders is copied byte for byte. Files are copied as
regular files: symbolic links are refused, and the executable bit is not
kept. The release workflow always comes from gh-release-flow's own template,
so `defaults/files/.github/workflows/release.yml`, or the file named by
`RELEASE_WORKFLOW`, is skipped.

### Settings

Each file in `defaults/settings/` is named after the API call it makes. A
`.json` file is sent as-is as the request body. A file without an extension
means a `PUT` without a body, which turns that feature on, so leave it empty.
A missing file leaves that setting alone. A file name this version of
gh-release-flow does not know is reported and skipped, so an older version
never guesses what a newer file means.

| File | Call |
| --- | --- |
| `repo.json` | `PATCH /repos/{owner}/{repo}` |
| `actions-permissions.json` | `PUT /repos/{owner}/{repo}/actions/permissions` |
| `actions-workflow.json` | `PUT /repos/{owner}/{repo}/actions/permissions/workflow` |
| `vulnerability-alerts` | `PUT /repos/{owner}/{repo}/vulnerability-alerts` |
| `automated-security-fixes` | `PUT /repos/{owner}/{repo}/automated-security-fixes` |
| `private-vulnerability-reporting` | `PUT /repos/{owner}/{repo}/private-vulnerability-reporting` |
| `immutable-releases` | `PUT /repos/{owner}/{repo}/immutable-releases` |
| `code-scanning-default-setup.json` | `PATCH /repos/{owner}/{repo}/code-scanning/default-setup` |

The body of each `.json` file is the one the GitHub REST API documents for
that call, for example:

```json
{
  "allow_merge_commit": true,
  "allow_squash_merge": false,
  "allow_rebase_merge": false,
  "has_wiki": false
}
```

### Rulesets

Each `.json` file in `defaults/rulesets/` holds one ruleset, in the shape that
`POST /repos/{owner}/{repo}/rulesets` accepts, with a top-level `name` and a
`target` of `branch` or `tag`. `init` creates each ruleset the repository does
not have by name. One with the same name is kept and never updated, so change
an existing ruleset on GitHub, or delete it there and run `init` again.

```json
{
  "name": "release tags",
  "target": "tag",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "rules": [{ "type": "deletion" }, { "type": "update" }]
}
```

To start from a ruleset you already use, open it in a repository's settings
under Rules, then Rulesets, and choose Export ruleset. In the exported file,
delete `id`, `source_type` and `source`: they describe the ruleset it was
exported from, and the create call does not take them. Keep `name`, `target`,
`enforcement`, `bypass_actors`, `conditions` and `rules`. A ruleset read with
`gh api` also carries `node_id`, `_links`, `created_at`, `updated_at` and
`current_user_can_bypass`; delete those too. Use `~DEFAULT_BRANCH` in
`conditions.ref_name.include` to target whatever the default branch is.

### Order

`init` applies the defaults in this order, so the base branch is never
protected before the files it needs are on it:

1. The files, then their commit and push.
2. The settings, in the order of the table above. GitHub turns on automated
   security fixes only after vulnerability alerts. CodeQL default setup comes
   last, after the push, so it has code to analyse; while the base branch is
   not on GitHub, it is held back.
3. The rulesets. Branch rulesets are created only once every default file is
   on the base branch on GitHub; otherwise they would require a pull request
   for the push that brings the files. Tag rulesets do not wait.

## Generated changelog

`open-pr` builds the pull request body from Git history, and the release
workflow publishes that body as the release notes. It selects the nearest
reachable release tag, shaped like `v1.2.3` or `v1.2.3-rc.1`, other than the
current version, and includes non-merge commits from that tag through `HEAD`.
With no previous tag, it uses the full history. Merge commits, commits authored
by `github-actions[bot]`, and commits whose subject is `changelog` are omitted.

The body has three parts: **What's Changed**, **New Contributors** when there
are any, and a **Full Changelog** link. It has no introduction: to add one,
edit the published release on GitHub. An immutable release keeps its notes and
title editable.

### Sections

Each commit is listed once, under the section of its
[Conventional Commit](https://www.conventionalcommits.org/) type:

| Prefix | Section |
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

Two sections come first:

- **Breaking Changes** lists every commit marked `!` (as in `feat!:`) or with
  a `BREAKING CHANGE:` footer, by the footer's text when it has one. The
  commit is also listed under its type.
- **Security** lists every commit with a `Security:` footer, in place of its
  type's section. The footer holds either a GitHub security advisory id, such
  as `GHSA-c2f3-g4h5-j6m7`, or a severity: `low`, `moderate` (or `medium`),
  `high` or `critical`. For an advisory, the entry links it and shows its
  severity and the people it credits as reporter or finder, read from GitHub;
  an advisory GitHub cannot show keeps its link without a severity. Any other
  value is listed under the commit's type, with a warning.

### Entries

An entry is the commit's subject without its prefix, with the scope in bold:
`feat(api): add widget` becomes `**api**: add widget`. In parentheses it links
the pull request the commit came through, other than a release PR, or else the
commit; then any issues its footers name with `Fixes`, `Closes`, `Resolves` or
`Refs`, as in `Fixes #12, #21`.

The author is named as `@login` only when it is someone other than the
repository's owner, and never for a bot. A commit whose author GitHub cannot
name is listed without one. **New Contributors** names each author with no
commit in the previous release, and the change that brought them; a first
release has no such section. GitHub shows the avatars of the accounts a
release mentions, so a release made by the owner alone shows none.

A commit with every footer:

```text
fix(auth): check the session token

Why the change was needed, in as many paragraphs as it takes.

Security: GHSA-c2f3-g4h5-j6m7
Fixes #12
BREAKING CHANGE: sessions saved before this release are signed out
```

`git commit --trailer 'Security: moderate'` adds a footer without editing the
message.

### Lookups

Pull requests, logins and advisories come from the GitHub API, one call per
commit and one per new author, so a release with many commits takes a few
seconds longer. Without an answer, an entry keeps its commit link and no author.
The repository used in links and lookups is resolved from `REPO`, then
`GITHUB_REPOSITORY`, then the repository the branch is pushed to. Links always
point at github.com.

## Configuration

All configuration is provided through environment variables.

| Variable | Default | Used by | Purpose |
| --- | --- | --- | --- |
| `DEFAULT_BASE_BRANCH` | `main` | all commands | Branch from which releases start and into which release PRs merge; `init` writes it into the workflow trigger and, with defaults, creates, commits to and pushes it. |
| `RELEASE_WORKFLOW` | `release.yml` | `merge`, `init` | Workflow file or name passed to `gh run list --workflow`; `init` writes this file name under `.github/workflows/`. |
| `VERSION` | prompt (shows the latest release tag) | `start-dev` | Version used when no command argument is provided. |
| `REPO` | repository the branch is pushed to | `open-pr`, `merge` | Repository targeted by GitHub CLI, exported as `GH_REPO`; also used for changelog links. |
| `PR` | auto-detected | `merge` | Specific PR number to validate and merge. |
| `CONFIRM` | `1` | `merge` | Set to `0` to skip the merge confirmation prompt. |
| `GITHUB_REPOSITORY` | repository the branch is pushed to | `open-pr` | Fallback `owner/repo` used only for generated changelog links. |

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

- `open-pr` and `merge` refuse staged or unstaged changes to tracked files.
  `start-dev` refuses them too, except on the base branch, where it offers to
  move them to the release branch. Git refuses that move rather than overwrite
  a changed file. Untracked files do not block the flow.
- `open-pr` never overwrites a remote branch and refuses stale or diverged
  histories.
- `merge` refuses missing checks, fork PRs, and mismatched local, remote, or PR
  commits.
- Remote cleanup uses `--force-with-lease` for the exact merged commit.
- Branches are deleted only after a successful release workflow and an ancestry
  check on the updated base branch.
- Both `open-pr` and `merge` are resumable by running the same command again.
- `init` asks before each outward action, never replaces a file without
  `--force`, commits only the files it wrote in that run, and never pushes
  over a branch ruleset. When a settings or ruleset call fails, it stops and
  lists what was applied and what was not. Running it again is safe.

## Shell function map

The extension is a single Bash executable. Its public interface is the
commands above; these internal functions implement that interface.

| Function | Responsibility |
| --- | --- |
| `die` | Prints a consistent error and exits non-zero. |
| `tree_dirty` | Reports staged or unstaged tracked-file changes. |
| `require_clean` | Rejects running outside a Git working tree and staged or unstaged tracked-file changes. |
| `require_gh` | Verifies that GitHub CLI is available. |
| `use_push_repo` | Resolves the release branch's push repository and points GitHub CLI at it unless `REPO` is set. |
| `find_pr` | Finds a branch PR owned by that push repository. |
| `latest_tag` | Prints the latest release tag on the fetched base branch. |
| `tool_version` | Prints the release tag of the tool's own Git clone, or `unknown` outside one. |
| `read_version` | Reads, normalizes, and validates a version, then derives its release branch. |
| `read_release_branch` | Validates the current branch and extracts its version. |
| `previous_tag` | Finds the nearest reachable release tag. |
| `generate_changelog` | Sorts commits into sections, reads their footers, looks up pull requests, logins and advisories, and adds the new contributors and the compare or release link. |
| `generate_pr_body` | Resolves repository and tag context and writes the temporary PR body. |
| `start_dev` | Updates the base branch and checks out or creates the release branch. |
| `open_pr` | Synchronizes the release branch, creates or updates its PR, and monitors checks. |
| `merge_release` | Validates and merges the PR, watches the release workflow, and cleans up branches. |
| `release_workflow_template` | Prints the release workflow for a base branch. |
| `confirm` | Asks a `[y/N]` question on the terminal. |
| `write_release_workflow` | Writes the release workflow into the repository, refusing to replace a different file without `--force`: `init` without defaults. |
| `fetch_defaults` | Downloads `<owner>/.github/defaults/`, validates its paths and rulesets, and reports unknown files. |
| `join_list` | Joins items with a separator. |
| `stop_partway` | Stops `init` after a failed call, listing the calls made and not made. |
| `fill_placeholders` | Replaces `{{owner}}`, `{{repo}}` and `{{year}}` in a copied file. |
| `init_workflow` | Validates `init`'s arguments, finds the owner and their defaults, and falls back to the release workflow alone without them. |
| `init_from_defaults` | Runs `init` with defaults: Git, the GitHub repository, files, commit and push, settings, rulesets, and the summary. |
| `setup_make` | Writes the user-wide Make targets and `make` shell function, and adds them to the shell profile. |
| `usage` | Prints command-line usage. |
| `main` | Validates arguments, resolves aliases, and dispatches commands. |

## Make compatibility

The extension accepts the environment variables used by the previous Make
flow. [`setup-make`](#setup-make) installs targets that delegate to it for
every folder. A single project can instead define its own:

```make
.PHONY: init start-dev open-pr merge-release

init start-dev open-pr merge-release:
	gh release-flow $@
```

## Development

Run the self-contained integration test with:

```bash
make test
```

It creates temporary local repositories and a fake `gh` executable to exercise
release workflow generation, repository setup from a fake defaults repository, branch creation, PR creation and body refresh, changelog rendering, stale and
diverged branch refusals, merge guards, the merge itself, already-merged
recovery, safe branch cleanup, the Make targets, and version normalization. It ignores your Git
configuration and never modifies the working repository.

Validate the shell scripts with:

```bash
make check
```
