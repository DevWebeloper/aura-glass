#!/usr/bin/env bash
# Assert the Blur My Shell patches apply to the pinned ref and leave valid JS.
#
# install_bms applies patches/blur-my-shell-subwindows.patch, then
# patches/blur-my-shell-full-size-buffers.patch, then
# patches/blur-my-shell-overview-fade.patch, then
# patches/blur-my-shell-static-maximized.patch, then
# patches/blur-my-shell-osd-corners.patch, to BMS_REF and
# dies if it does not apply, which is a user's desktop finding out. And a patch
# that applies can still reference a name it never declares: KI-27's
# MESSAGE_CORNER_EFFECT_NAME threw inside a try and was swallowed, so nothing
# ever reported it. This applies the patch to a throwaway clone of the cached
# checkout, parses every JS file it touches,
# and flags UPPER_SNAKE names a touched file uses but neither declares nor
# imports -- the shape of constant that bug was.
#
# Last, every `*corner-radius` key the patched schema ships must be one aura
# keeps in step with a token (tools/token_manifest.py), one it deliberately
# leaves at Blur My Shell's default (DEFAULT_OK below), or one it pins to a
# constant that the painting css or theme hardcodes (PINNED below). KI-47: BMS #1164 split
# calendar-corner-radius and submenu-corner-radius out of
# quick-settings-corner-radius, nothing here wrote them, and the blur stuck out
# past the painted corners until someone looked at a bright wallpaper. A new
# key now fails at pin-bump time instead.
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
git -C "$TMP/bms" apply --whitespace=nowarn "$ROOT/patches/$BMS_BUFFERS_PATCH" \
    || note "patches/$BMS_BUFFERS_PATCH does not apply on top of those"
git -C "$TMP/bms" apply --whitespace=nowarn "$ROOT/patches/$BMS_FADE_PATCH" \
    || note "patches/$BMS_FADE_PATCH does not apply on top of those"
git -C "$TMP/bms" apply --whitespace=nowarn "$ROOT/patches/$BMS_STATIC_PATCH" \
    || note "patches/$BMS_STATIC_PATCH does not apply on top of those"
git -C "$TMP/bms" apply --whitespace=nowarn "$ROOT/patches/$BMS_OSD_PATCH" \
    || note "patches/$BMS_OSD_PATCH does not apply on top of those"
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

python3 - "$TMP/bms/schemas" "$ROOT/tools" "$TMP/radius-count" <<'PY' || problems=$((problems + 1))
import glob, os, re, sys
import xml.etree.ElementTree as ET
sys.path.insert(0, sys.argv[2])
import token_manifest

# Radius keys aura leaves at Blur My Shell's default on purpose, each with the
# reason that default is also what the surface is painted at.
DEFAULT_OK = {
    ("blur-my-shell/panel", "corner-radius"):
        "aura paints no #panel radius (css/shell-00-flat.css) and the theme's "
        "-panel-corner-radius is 0, BMS default 0",
    ("blur-my-shell/popup", "osk-corner-radius"):
        "no css here rounds .bms-keyboard-surface and the theme's #keyboard "
        "has no radius, BMS default 0",
}

# Radius keys written as constants because the surface's paint is a constant
# the css or the adopted theme hardcodes: (section, key): (value, reason).
# The step fails if dconf/core.ini drifts from the value, and for the GTK menu
# if the css rule it mirrors does.
PINNED = {
    ("blur-my-shell/popup", "candidate-corner-radius"):
        (14, "the input-method popup is painted by the adopted theme: "
             "gnome-shell.css .candidate-popup-content, 14px !important"),
    ("blur-my-shell/applications", "menu-corner-radius"):
        (18, "GTK app popup menus are painted by css/gtk4-70-surfaces.css "
             "`popover > contents`, border-radius 18px"),
}

schema = set()
for path in sorted(glob.glob(os.path.join(sys.argv[1], "*.gschema.xml"))):
    for node in ET.parse(path).getroot().iter("schema"):
        section = node.get("path", "").strip("/").replace("org/gnome/shell/extensions/", "")
        for key in node.iter("key"):
            if key.get("name", "").endswith("corner-radius"):
                schema.add((section, key.get("name")))

covered = {(e[3], e[4]) for e in token_manifest.ini_entries()
           if e[4].endswith("corner-radius")}
bad = 0

ini = {}
section = None
for line in open(os.path.join(sys.argv[2], "..", "dconf", "core.ini"), encoding="utf-8"):
    line = line.strip()
    if line.startswith("[") and line.endswith("]"):
        section = line[1:-1]
    elif "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        ini[(section, k)] = v
for (section, key), (value, why) in sorted(PINNED.items()):
    if ini.get((section, key)) != str(value):
        print("  %s %s: dconf/core.ini has %s, pinned at %s (%s)"
              % (section, key, ini.get((section, key)), value, why))
        bad += 1
css = open(os.path.join(sys.argv[2], "..", "css", "gtk4-70-surfaces.css"), encoding="utf-8").read()
rule = re.search(r"^popover > contents,\n[^{]*\{[^}]*?border-radius: (\d+)px", css, re.M)
if not rule or int(rule.group(1)) != PINNED[("blur-my-shell/applications", "menu-corner-radius")][0]:
    print("  css/gtk4-70-surfaces.css `popover > contents` border-radius is %s, "
          "pinned menu-corner-radius is %s" % (rule and rule.group(1),
          PINNED[("blur-my-shell/applications", "menu-corner-radius")][0]))
    bad += 1

for section, key in sorted(schema - covered - set(DEFAULT_OK) - set(PINNED)):
    print("  %s %s: no token keeps it in step and it is not in DEFAULT_OK (KI-47) -- "
          "add it to tools/token_manifest.py + apply_radius_dconf + dconf/core.ini, "
          "to DEFAULT_OK, or to PINNED, with a reason" % (section, key))
    bad += 1
for section, key in sorted((covered | set(DEFAULT_OK) | set(PINNED)) - schema):
    print("  %s %s: in the manifest, DEFAULT_OK or PINNED but the pinned schema has no such key" % (section, key))
    bad += 1
with open(sys.argv[3], "w") as out:
    out.write(str(len(schema)))
sys.exit(1 if bad else 0)
PY

if [ "$problems" != 0 ]; then
    echo "check-bms-patches: $problems problem(s)"
    exit 1
fi
echo "check-bms-patches: OK (${#touched[@]} patched JS files, $(cat "$TMP/radius-count") radius keys accounted for)"
