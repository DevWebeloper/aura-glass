#!/usr/bin/env bash
# Assert bin/aura-glass-ext list describes every extension this project ships.
#
# The settings window builds its Extensions page from that command rather than
# from a copy of the arrays, so the command is the catalogue as far as the
# window is concerned. What this catches is the two ways that goes wrong: a
# UUID added to lib/steps.sh that `list` never mentions, and one it mentions
# with no description, which would put a bare UUID on screen where a sentence
# should be.
#
# Reads only. No network, no dconf writes, no display.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=lib/distro.sh
. "$ROOT/lib/distro.sh"
# shellcheck source=lib/steps.sh
. "$ROOT/lib/steps.sh"
# shellcheck source=lib/steps-extensions.sh
. "$ROOT/lib/steps-extensions.sh"

problems=0
note() { printf '  %s\n' "$1"; problems=$((problems + 1)); }

json="$(bash "$ROOT/bin/aura-glass-ext" list)" \
    || { echo "aura-glass-ext list failed"; exit 1; }

# Every UUID the install path can reach, which is what the window has to be able
# to show. BMS_UUID, openbar and custom-osd are named the way enable_extensions
# names them: they are installed unconditionally rather than sitting in a tier.
expected=("${EXT_CORE[@]}" openbar@neuromorph "$BMS_UUID" custom-osd@neuromorph
          "${EXT_EXTRA_ALL[@]}")

listed="$(printf '%s' "$json" | python3 -c '
import json, sys
for e in json.load(sys.stdin):
    print(e["uuid"])
')"

for uuid in "${expected[@]}"; do
    printf '%s\n' "$listed" | grep -qxF "$uuid" \
        || note "$uuid is installable but aura-glass-ext list does not mention it"
done

# Nothing listed that the install path cannot reach, which would be a row whose
# buttons do nothing.
while read -r uuid; do
    [ -n "$uuid" ] || continue
    found=0
    for known in "${expected[@]}"; do
        [ "$known" = "$uuid" ] && { found=1; break; }
    done
    [ "$found" = 1 ] || note "$uuid is listed but is not in any install list"
done <<< "$listed"

# A description per UUID, and not just the UUID echoed back by the fallback
# branch of ext_description — a row titled with a bare UUID is not a
# description. Also that every field the window reads is actually there.
#
# Captured into a variable rather than piped into a loop: a `while read` on the
# right of a pipe runs in a subshell, where incrementing $problems increments a
# copy of it and the check silently always passes.
desc_problems="$(printf '%s' "$json" | python3 -c '
import json, sys
for e in json.load(sys.stdin):
    description = (e.get("description") or "").strip()
    if not description or description == e["uuid"]:
        print("%s has no description of its own" % e["uuid"])
    for key in ("installed", "enabled", "system", "tier"):
        if key not in e:
            print("%s is missing the %s field" % (e["uuid"], key))
')"
while read -r line; do
    [ -n "$line" ] && note "$line"
done <<< "$desc_problems"

count="$(printf '%s\n' "$listed" | grep -c . || true)"

if [ "$problems" -gt 0 ]; then
    printf 'extension catalogue check FAILED — %d problem(s)\n' "$problems"
    exit 1
fi
printf 'extension catalogue check passed — %s extensions, each described\n' "$count"
