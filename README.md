# gh-release-flow

Create, review, merge, and monitor GitHub releases from `dev/v*` branches.

## Install

```bash
gh extension install mordilloSan/gh-release-flow
```

Upgrade later with `gh extension upgrade release-flow`.

## Use

```bash
gh release-flow start-dev v1.2.3
gh release-flow open-pr
gh release-flow merge
```

The defaults are the `main` base branch, `release.yml` workflow, and an
interactive merge confirmation. Override them with environment variables:

```bash
DEFAULT_BASE_BRANCH=trunk RELEASE_WORKFLOW=publish.yml gh release-flow merge
REPO=owner/project gh release-flow open-pr
CONFIRM=0 gh release-flow merge
```

`VERSION`, `REPO`, `PR`, and `CONFIRM` remain compatible with the previous Make
flow. A Makefile can preserve its old targets with:

```make
.PHONY: start-dev open-pr merge-release

start-dev open-pr merge-release:
	gh release-flow $@
```

The extension accepts `merge-release` as an alias for `merge`.
