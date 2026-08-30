.PHONY: check

check:
	shellcheck gh-release-flow test && shfmt -d gh-release-flow test && actionlint
