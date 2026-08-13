#!/usr/bin/env bash
# Point this clone's git hooks at tools/hooks.
#
#     tools/install-hooks.sh          enable
#     tools/install-hooks.sh --off    back to .git/hooks
#
# core.hooksPath rather than a copy or a symlink into .git/hooks: the hook then
# lives in the tree, is reviewed like any other file, and updates with a pull
# instead of having to be re-installed. It is per-clone config, so it is not
# something this repository can turn on for you — hence this script.
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "not a git repository" >&2; exit 1; }

if [ "${1:-}" = "--off" ]; then
    git config --unset core.hooksPath 2>/dev/null || true
    echo "hooks disabled — back to .git/hooks"
    exit 0
fi

chmod +x tools/hooks/* 2>/dev/null || true
git config core.hooksPath tools/hooks

echo "hooks enabled — core.hooksPath = tools/hooks"
echo
echo "  pre-commit runs, against the staged tree only:"
echo "    shell and python syntax"
echo "    tools/check-tokens.sh"
echo "    tools/check-cascade.sh"
echo
echo "  git commit --no-verify skips it; tools/install-hooks.sh --off undoes this."
