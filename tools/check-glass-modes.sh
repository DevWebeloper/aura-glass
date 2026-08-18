#!/usr/bin/env bash
# Assert that --glass-mode resolves into the blur flags the design table says.
#
# Everything runs through install.sh --settings-only --dry-run, which parses and
# resolves exactly as a real run would and writes nothing. The mode is a
# resolution rule, so resolution is what this checks: which WANT_* the mode
# leaves behind, which explicit flag beats it, and which combination is refused.
#
# Runs under a scratch $HOME rather than the developer's own. --settings-only
# fills in whatever a flag did not say from $CONF_DIR memos, so running against
# a real ~/.config/aura-glass would make the expected answers depend on that
# machine's history — a glass-mode memo of "solid" left over from a previous run
# would break the bare --no-blur case below, which expects the default
# frosted-shaped answer rather than whatever this machine last remembered.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=()

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
# --settings-only refuses to run at all unless both of these already look like
# an existing install (install.sh's own check), so the scratch HOME needs a
# config dir and a theme directory even though neither holds anything real.
mkdir -p "$scratch/.config/aura-glass" "$scratch/.themes/Tahoe-Dark"

in_scratch() {   # in_scratch FLAG...
    HOME="$scratch" bash "$ROOT/install.sh" --settings-only --dry-run --yes "$@"
}

# The resolved state is not printed by install.sh, so ask it for the one thing
# that is: a debug line the resolution writes under --dry-run.
resolved() {   # resolved FLAG...
    in_scratch "$@" 2>&1 \
        | sed -n 's/^ *glass-mode: //p' | tail -n 1
}

want() {       # want "description" "expected" FLAG...
    local desc="$1" expect="$2"; shift 2
    local got; got="$(resolved "$@")"
    [ "$got" = "$expect" ] || failures+=("$desc: wanted '$expect', got '$got'")
}

want "frosted resolves to blur on, window blur on, styling on" \
     "frosted blur=1 window=1 popup=1 transparency=0.90 styling=1" \
     --glass-mode frosted --app-transparency 0.90

want "transparent drops the window blur and keeps the popups" \
     "transparent blur=1 window=0 popup=1 transparency=0.82 styling=1" \
     --glass-mode transparent --app-transparency 0.82

want "solid turns everything off and stands the styling down" \
     "solid blur=0 window=0 popup=0 transparency=0 styling=0" \
     --glass-mode solid

want "an explicit popup flag beats the mode" \
     "transparent blur=1 window=0 popup=0 transparency=0.82 styling=1" \
     --glass-mode transparent --no-popup-blur --app-transparency 0.82

want "bare --no-blur is opaque but still themed" \
     "frosted blur=0 window=0 popup=0 transparency=0 styling=1" \
     --no-blur

want "solid accepts an explicit --app-transparency already spelled off (0.0)" \
     "solid blur=0 window=0 popup=0 transparency=0 styling=0" \
     --glass-mode solid --app-transparency 0.0

want "solid accepts an explicit --app-transparency already spelled off (off)" \
     "solid blur=0 window=0 popup=0 transparency=0 styling=0" \
     --glass-mode solid --app-transparency off

if in_scratch --glass-mode solid --window-blur >/dev/null 2>&1; then
    failures+=("--glass-mode solid --window-blur was accepted, it must be refused")
fi

if in_scratch --glass-mode solid --blur >/dev/null 2>&1; then
    failures+=("--glass-mode solid --blur was accepted, it must be refused")
fi

if in_scratch --glass-mode solid --popup-blur >/dev/null 2>&1; then
    failures+=("--glass-mode solid --popup-blur was accepted, it must be refused")
fi

if in_scratch --glass-mode solid --app-transparency 0.85 >/dev/null 2>&1; then
    failures+=("--glass-mode solid --app-transparency 0.85 was accepted, it must be refused")
fi

if in_scratch --glass-mode frostd >/dev/null 2>&1; then
    failures+=("a misspelled --glass-mode was accepted")
fi

# The per-mode drawer, on the same scratch CONF_DIR as everything above. The
# resolutions already run above have their own opinions about --glass-mode
# frosted/transparent/solid, and seed_glass_mode writes even under --dry-run —
# so modes/ already holds whatever those left behind. Start this drawer clean
# rather than assume it is, and give it the disk value the seeding cases below
# are actually about.
rm -rf "$scratch/.config/aura-glass/modes"
printf '0.88\n' > "$scratch/.config/aura-glass/app-transparency"

in_scratch --glass-mode frosted >/dev/null 2>&1
seeded="$(cat "$scratch/.config/aura-glass/modes/frosted/app-transparency" 2>/dev/null || true)"
[ "$seeded" = "0.88" ] || failures+=(
    "seeding frosted should take the level already on disk, got '$seeded'")

in_scratch --glass-mode transparent >/dev/null 2>&1
seeded="$(cat "$scratch/.config/aura-glass/modes/transparent/app-transparency" 2>/dev/null || true)"
[ "$seeded" = "0.82" ] || failures+=(
    "seeding transparent should give it its own darker level, got '$seeded'")
seeded="$(cat "$scratch/.config/aura-glass/modes/transparent/app-tint-color" 2>/dev/null || true)"
[ "$seeded" = "#0b0b0f" ] || failures+=(
    "seeding transparent should give it its own tint, got '$seeded'")

# Back to frosted: its own level comes back rather than transparent's.
got="$(resolved --glass-mode frosted)"
case "$got" in
    *"transparency=0.88"*) ;;
    *) failures+=("switching back to frosted should restore 0.88, got '$got'") ;;
esac

if [ "${#failures[@]}" -gt 0 ]; then
    printf 'glass mode check FAILED\n\n'
    printf '  %s\n' "${failures[@]}"
    exit 1
fi
printf 'glass mode check passed — 7 resolutions, 5 refusals and 4 round-trips\n'
