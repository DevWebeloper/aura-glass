#!/usr/bin/env bash
# Assert the Blur My Shell patch applies to the pinned ref and leaves valid JS.
#
# install_bms applies patches/blur-my-shell-subwindows.patch to BMS_REF and
# dies if it does not apply, which is a user's desktop finding out. And a patch
# that applies can still reference a name it never declares: KI-27's
# MESSAGE_CORNER_EFFECT_NAME threw inside a try and was swallowed, so nothing
# ever reported it. This applies the patch to a throwaway clone of the cached
# checkout, parses every JS file it touches,
# and flags UPPER_SNAKE names a touched file uses but neither declares nor
# imports -- the shape of constant that bug was.
#
# No network: it clones from install_bms's cache ($SRC_CACHE/blur-my-shell)
# and skips, saying so, when there is none. Writes only to a temp dir.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=lib/steps.sh
. "$ROOT/lib/steps.sh"

# Git runs a pre-commit hook with GIT_INDEX_FILE (and sometimes GIT_DIR) set
# for the repository being committed to; left in place they point every git
# call below at that index instead of the temp clone's.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES

cache="${AURA_GLASS_BMS_CACHE:-$SRC_CACHE/blur-my-shell}"
if [ ! -d "$cache/.git" ] || ! git -C "$cache" cat-file -e "$BMS_REF^{commit}" 2>/dev/null; then
    echo "check-bms-patches: skipped (no cached Blur My Shell checkout at $BMS_REF in $cache)"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone --quiet --shared --no-checkout "$cache" "$TMP/bms"
git -C "$TMP/bms" -c advice.detachedHead=false checkout --quiet "$BMS_REF"

problems=0
note() { printf '  %s\n' "$1"; problems=$((problems + 1)); }

git -C "$TMP/bms" apply --whitespace=nowarn "$ROOT/patches/$BMS_SUBWIN_PATCH" \
    || note "patches/$BMS_SUBWIN_PATCH does not apply to $BMS_REF"
[ "$problems" = 0 ] || { echo "check-bms-patches: $problems problem(s)"; exit 1; }

mapfile -t touched < <(git -C "$TMP/bms" diff --name-only -- '*.js')

have node || echo "check-bms-patches: node not found, parse step skipped"
for file in "${touched[@]}"; do
    path="$TMP/bms/$file"
    if have node; then
        cp "$path" "$TMP/parse.mjs"
        node --check "$TMP/parse.mjs" 2>/dev/null || note "$file does not parse after patching"
    fi
    python3 - "$path" "$file" <<'PY' || problems=$((problems + 1))
import re, sys
path, name = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()
# Comments and strings would otherwise show up as uses.
code = re.sub(r"//[^\n]*|/\*.*?\*/", "", src, flags=re.S)
code = re.sub(r"`(?:\\.|[^`\\])*`|'(?:\\.|[^'\\\n])*'|\"(?:\\.|[^\"\\\n])*\"", "''", code)
declared = set(re.findall(r"\b(?:const|let|var|function|class)\s+([A-Z][A-Z0-9_]+)\b", code))
for block in re.findall(r"import\s*\{([^}]*)\}", code):
    for part in block.split(","):
        declared.add(part.split(" as ")[-1].strip())
declared |= set(re.findall(r"import\s+(?:\*\s+as\s+)?([A-Za-z_][A-Za-z0-9_]*)\s+from", code))
used = set(re.findall(r"(?<![.\w$])([A-Z][A-Z0-9]*_[A-Z0-9_]+)\b", code))
missing = sorted(used - declared)
for m in missing:
    print("  %s uses %s, which it never declares or imports" % (name, m))
sys.exit(1 if missing else 0)
PY
done

if [ "$problems" != 0 ]; then
    echo "check-bms-patches: $problems problem(s)"
    exit 1
fi
echo "check-bms-patches: OK (${#touched[@]} patched JS files)"
