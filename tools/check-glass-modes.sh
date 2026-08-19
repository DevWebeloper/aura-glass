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
# rather than assume it is, and give it the disk values the seeding cases below
# are actually about — one non-default value per key the drawer keeps.
rm -rf "$scratch/.config/aura-glass/modes"
printf '0.88\n'    > "$scratch/.config/aura-glass/app-transparency"
printf '#224488\n' > "$scratch/.config/aura-glass/shell-tint-color"
printf 'all\n'      > "$scratch/.config/aura-glass/app-blur-scope"
printf '0\n'        > "$scratch/.config/aura-glass/popup-blur"
printf '150\n'      > "$scratch/.config/aura-glass/blur-strength"

in_scratch --glass-mode frosted >/dev/null 2>&1
seeded="$(cat "$scratch/.config/aura-glass/modes/frosted/app-transparency" 2>/dev/null || true)"
[ "$seeded" = "0.88" ] || failures+=(
    "seeding frosted should take the level already on disk, got '$seeded'")
seeded="$(cat "$scratch/.config/aura-glass/modes/frosted/shell-tint-color" 2>/dev/null || true)"
[ "$seeded" = "#224488" ] || failures+=(
    "seeding frosted should take the shell tint already on disk, got '$seeded'")
seeded="$(cat "$scratch/.config/aura-glass/modes/frosted/app-blur-scope" 2>/dev/null || true)"
[ "$seeded" = "all" ] || failures+=(
    "seeding frosted should take the blur scope already on disk, got '$seeded'")
seeded="$(cat "$scratch/.config/aura-glass/modes/frosted/popup-blur" 2>/dev/null || true)"
[ "$seeded" = "0" ] || failures+=(
    "seeding frosted should take the popup-blur choice already on disk, got '$seeded'")
seeded="$(cat "$scratch/.config/aura-glass/modes/frosted/blur-strength" 2>/dev/null || true)"
[ "$seeded" = "150" ] || failures+=(
    "seeding frosted should take the blur strength already on disk, got '$seeded'")

in_scratch --glass-mode transparent >/dev/null 2>&1
seeded="$(cat "$scratch/.config/aura-glass/modes/transparent/app-transparency" 2>/dev/null || true)"
[ "$seeded" = "0.82" ] || failures+=(
    "seeding transparent should give it its own darker level, got '$seeded'")
seeded="$(cat "$scratch/.config/aura-glass/modes/transparent/app-tint-color" 2>/dev/null || true)"
[ "$seeded" = "#0b0b0f" ] || failures+=(
    "seeding transparent should give it its own tint, got '$seeded'")

# Diverge the shared top-level memos from what frosted's own drawer holds —
# what a plain flagless run, or a real (non-dry) run of another mode, would
# leave behind. Without this, switching back to frosted would find the shared
# memo agreeing with the drawer by coincidence, and a re-read that should not
# have happened would go unnoticed the same way it did the first time: the
# drawer was written correctly here too, it just was not what reached the
# resolution.
printf 'gtk\n'      > "$scratch/.config/aura-glass/app-blur-scope"
printf '1\n'        > "$scratch/.config/aura-glass/popup-blur"
printf '100\n'      > "$scratch/.config/aura-glass/blur-strength"
printf '#000000\n'  > "$scratch/.config/aura-glass/shell-tint-color"

# Back to frosted: its own answers come back, not the shared memos just
# diverged out from under it. transparency is read straight off the
# glass-mode line. popup-blur and app-blur-scope are not: both have a
# downstream reader gated on their own *_EXPLICIT flag rather than on
# emptiness (apply_popup_blur and apply_app_blur in lib/steps-dconf.sh, plus
# install.sh's own block for scope), and that reader runs after the
# glass-mode line is printed and only ever touches its own local copy of the
# value — so the line itself prints the same popup=0 whether or not the
# re-read after it was skipped. What actually moves is the dconf write those
# functions make, echoed here because this is a dry run. blur-strength and
# shell-tint-color have no such second reader — apply_blur_strength and
# apply_shell_tint_color only fall back to the shared memo when the value
# itself is still empty, which load_glass_mode_memos never leaves it — so
# their own dry-run lines are asserted on for the same reason: it is where
# this run says what it actually resolved to.
raw="$(in_scratch --glass-mode frosted 2>&1)"
got="$(printf '%s\n' "$raw" | sed -n 's/^ *glass-mode: //p' | tail -n 1)"
case "$got" in
    *"transparency=0.88"*) ;;
    *) failures+=("switching back to frosted should restore transparency 0.88, got '$got'") ;;
esac
case "$raw" in
    *"dry-run: dconf write /org/gnome/shell/extensions/blur-my-shell/popup/blur false"*) ;;
    *) failures+=("switching back to frosted should keep popup-blur off (no 'popup/blur false' dry-run write seen)") ;;
esac
case "$raw" in
    *"dry-run: dconf write /org/gnome/shell/extensions/blur-my-shell/applications/enable-all true"*) ;;
    *) failures+=("switching back to frosted should keep app-blur-scope all (no 'enable-all true' dry-run write seen)") ;;
esac
case "$raw" in
    *"dry-run: scale every blur radius to 150%"*) ;;
    *) failures+=("switching back to frosted should restore blur-strength 150 (line not seen)") ;;
esac
case "$raw" in
    *"dry-run: tint the shell's dark surfaces toward #224488"*) ;;
    *) failures+=("switching back to frosted should restore shell-tint-color #224488 (line not seen)") ;;
esac

# Solid leaves the packs and the accent alone and puts the two theme keys back.
# Matched against the specific dry-run line each assertion is about, rather
# than anywhere in the whole run's output, so a regression in one line cannot
# hide behind an unrelated line elsewhere that happens to share a word.
out="$(in_scratch --glass-mode solid)"
case "$out" in
    *"dry-run: gsettings reset org.gnome.desktop.interface gtk-theme"*) ;;
    *) failures+=("solid should reset gtk-theme, the run never mentions it") ;;
esac
case "$out" in
    *"dry-run: dconf load /org/gnome/shell/extensions/ < dconf/core.ini"*)
        failures+=("solid should not load the dconf preset — it would rewrite the extensions' own settings") ;;
esac
case "$out" in
    *"dry-run: gsettings set org.gnome.desktop.interface icon-theme"*) ;;
    *) failures+=("solid should still set the icon theme — the packs stay") ;;
esac

# Solid also stands the extensions down, and the way back is silent on any
# other mode — restore_extensions returns immediately with no record on disk.
out="$(in_scratch --glass-mode solid)"
case "$out" in
    *"Standing the extensions down"*) ;;
    *) failures+=("solid should stand the extensions down, the run never mentions it") ;;
esac
case "$out" in
    *"dconf reset"*)
        failures+=("solid must not reset any extension's settings") ;;
esac

out="$(in_scratch --glass-mode frosted)"
case "$out" in
    *"Standing the extensions down"*)
        failures+=("frosted should never stand the extensions down") ;;
esac

if [ "${#failures[@]}" -gt 0 ]; then
    printf 'glass mode check FAILED\n\n'
    printf '  %s\n' "${failures[@]}"
    exit 1
fi
printf 'glass mode check passed — 7 resolutions, 5 refusals, 6 drawer keys round-tripped, solid'"'"'s theme keys confirmed, and its extensions stood down\n'
