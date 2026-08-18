# Glass Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give aura-glass three named glass modes — frosted, transparent and solid — each with its own remembered settings, shown as three tabs on the settings window's Glass page, where solid stands the theme's styling down instead of restyling it.

**Architecture:** A new setting `glass-mode` is resolved in install.sh and expands into the blur/transparency flags install.sh already has, so nothing downstream learns new vocabulary. Each mode keeps its own copy of the settings that belong to it under `$CONF_DIR/modes/<mode>/`, while the existing top-level memos stay the live state every current reader consults. Solid additionally sets a `styling-off` marker that `bin/aura-glass-apply`, `apply_gsettings` and a new extension stand-down step read.

**Tech Stack:** bash 5 (install.sh + `lib/steps-*.sh`), python3 (helper rewriters and the check scripts), PyGObject / GTK4 / libadwaita 1 (`gui/aura_glass_settings.py`).

**Spec:** `docs/superpowers/specs/2026-08-18-glass-modes-design.md`

## Global Constraints

- Shell is bash with `set -euo pipefail`-style discipline as in the existing files; every mutating command goes through the existing `run` helper so `--dry-run` stays honest.
- `$CONF_DIR` is `$HOME/.config/aura-glass`, `$BACKUP_DIR` is `$CONF_DIR/backups` (both from `lib/steps.sh`).
- Valid modes, exact spelling: `frosted transparent solid`.
- Marker file, exact path: `$CONF_DIR/styling-off`. Mode memo: `$CONF_DIR/glass-mode`. Per-mode directory: `$CONF_DIR/modes/<mode>/`.
- Transparent-mode seeds: transparency `0.82`, tints `#0b0b0f`, blur strength `100`, popup blur `1`. Frosted-mode seeds: transparency `0` (off), tints `#000000`, blur strength `100`, scope `gtk`, popup blur `1`.
- `--no-blur` on its own keeps its current meaning — opaque but still themed. Only an explicit mode of `solid` (or an existing `styling-off` marker) stands the styling down.
- Every new check script is wired into `tools/hooks/pre-commit` in the same task that creates it, following the existing `step "<name> (tools/<file>)" <runner> "$TMP/tools/<file>"` shape.
- Commit messages follow the repo's style: `type(scope): lowercase summary`, body explaining why, no trailing period on the summary.

---

### Task 1: The mode setting — flag, validation, derivation, memo

**Files:**
- Create: `lib/steps-modes.sh`
- Create: `tools/check-glass-modes.sh`
- Modify: `install.sh` (variable block ~line 59-90, usage text ~line 182-190, argument parser ~line 266-284, resolution ~line 721-726, conflict check ~line 905)
- Modify: `lib/steps.sh` (source the new file alongside the other `steps-*.sh`)
- Modify: `tools/hooks/pre-commit` (~line 118, after the app blur lists step)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `GLASS_MODE` (one of `frosted|transparent|solid`), `GLASS_MODE_EXPLICIT`, `WANT_STYLING` (`1`/`0`), and the shell functions `resolve_glass_mode`, `apply_glass_mode`, `glass_mode_from_state`, `remember_glass_mode` — all sourced from `lib/steps-modes.sh`.

- [ ] **Step 1: Write the failing test**

Create `tools/check-glass-modes.sh`:

```bash
#!/usr/bin/env bash
# Assert that --glass-mode resolves into the blur flags the design table says.
#
# Everything runs through install.sh --settings-only --dry-run, which parses and
# resolves exactly as a real run would and writes nothing. The mode is a
# resolution rule, so resolution is what this checks: which WANT_* the mode
# leaves behind, which explicit flag beats it, and which combination is refused.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=()

# The resolved state is not printed by install.sh, so ask it for the one thing
# that is: a debug line the resolution writes under --dry-run.
resolved() {   # resolved MODE FLAG...
    bash "$ROOT/install.sh" --settings-only --dry-run --yes "$@" 2>&1 \
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

if bash "$ROOT/install.sh" --settings-only --dry-run --yes \
        --glass-mode solid --window-blur >/dev/null 2>&1; then
    failures+=("--glass-mode solid --window-blur was accepted, it must be refused")
fi

if bash "$ROOT/install.sh" --settings-only --dry-run --yes \
        --glass-mode frostd >/dev/null 2>&1; then
    failures+=("a misspelled --glass-mode was accepted")
fi

if [ "${#failures[@]}" -gt 0 ]; then
    printf 'glass mode check FAILED\n\n'
    printf '  %s\n' "${failures[@]}"
    exit 1
fi
printf 'glass mode check passed — 5 resolutions and 2 refusals\n'
```

Make it executable: `chmod +x tools/check-glass-modes.sh`.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tools/check-glass-modes.sh`
Expected: FAIL — every `want` reports `got ''` because nothing prints a `glass-mode:` line yet, and the two refusal cases fail because `--glass-mode` is an unknown flag that install.sh already rejects (so those two may pass by accident; the five `want` lines are the ones that must fail).

- [ ] **Step 3: Add the variables and the usage text to install.sh**

In the variable block, directly after `WANT_BLUR=1` (~line 59):

```bash
GLASS_MODE=""            # empty = the memo, then derived from the flags
GLASS_MODE_EXPLICIT=""
BLUR_EXPLICIT=""         # --blur / --no-blur were typed, so a mode must not move them
WANT_STYLING=1           # 0 = the theme stands down (solid mode)
VALID_GLASS_MODES="frosted transparent solid"
```

In the usage heredoc, directly above the `--no-blur` line (~line 186):

```
    --glass-mode M    frosted (blur behind windows and popups), transparent
                      (translucent windows, no window blur) or solid (the theme
                      stands down: no styling, stock shell, the extensions it
                      enabled switched off and their settings left alone).
                      Remembered; each mode keeps its own opacity and tint
```

- [ ] **Step 4: Parse the flag**

In the argument parser, directly above the `--blur)` case (~line 266):

```bash
        --glass-mode)    GLASS_MODE="${2:-}"; GLASS_MODE_EXPLICIT=1; EXPLICIT_FLAGS=1; shift 2 ;;
        --glass-mode=*)  GLASS_MODE="${1#*=}"; GLASS_MODE_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
```

And mark the two blur flags explicit, so a mode cannot move a flag the user typed. Change the existing `--blur)` case to:

```bash
        --blur)          WANT_BLUR=1; BLUR_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
```

and add `BLUR_EXPLICIT=1` to the `--no-blur)` case beside `WANT_BLUR=0`.

- [ ] **Step 5: Write lib/steps-modes.sh**

```bash
# The three glass modes.
#
# A mode is not a fourth kind of setting — it is a name for a combination of the
# blur, transparency and styling flags install.sh already has, plus a drawer to
# keep each combination's own tuning in. Everything here therefore resolves into
# those flags and then gets out of the way: nothing downstream of this file
# knows a mode exists.
#
# Precedence, highest first: a flag the user typed, then --glass-mode, then the
# remembered mode, then a mode derived from the state the flags leave behind.
# The rule is the ordinary one — an explicit answer beats an inferred one — and
# it is why apply_glass_mode tests every *_EXPLICIT before it moves anything.

# The mode the resolved state amounts to, which is what gets remembered. Solid
# is the styling being down rather than the blur being off: --no-blur on its own
# is an opaque theme, not a theme that has stood down, and remembering it as
# solid would stand the styling down on the next flagless run.
glass_mode_from_state() {
    if [ "${WANT_STYLING:-1}" = 0 ]; then
        printf 'solid\n'
    elif [ "${WANT_BLUR:-1}" = 1 ] && [ "${WANT_WINDOW_BLUR:-1}" = 0 ] \
         && [ "${APP_TRANSPARENCY:-0}" != 0 ]; then
        printf 'transparent\n'
    else
        printf 'frosted\n'
    fi
}

resolve_glass_mode() {
    if [ -n "${GLASS_MODE_EXPLICIT:-}" ]; then
        case " $VALID_GLASS_MODES " in
            *" $GLASS_MODE "*) ;;
            *) die "unknown --glass-mode '$GLASS_MODE' — pick one of: $VALID_GLASS_MODES" ;;
        esac
        return 0
    fi

    # The marker is the honest answer for solid: it is the state the desktop is
    # actually in, and it outranks a memo that a hand-edited install could have
    # left disagreeing with it.
    if [ -f "$CONF_DIR/styling-off" ]; then GLASS_MODE="solid"; return 0; fi

    if [ -r "$CONF_DIR/glass-mode" ]; then
        GLASS_MODE="$(cat "$CONF_DIR/glass-mode" 2>/dev/null || true)"
        case " $VALID_GLASS_MODES " in
            *" $GLASS_MODE "*) return 0 ;;
        esac
    fi
    GLASS_MODE=""      # nothing to go on; apply_glass_mode leaves the flags be
}

# The table in the design doc, in code. Only ever writes a value whose flag was
# not given: --glass-mode transparent --no-popup-blur is a mode with one of its
# answers overruled, not a contradiction.
apply_glass_mode() {
    case "${GLASS_MODE:-}" in
        frosted)
            [ -n "${BLUR_EXPLICIT:-}" ]        || WANT_BLUR=1
            [ -n "${WINDOW_BLUR_EXPLICIT:-}" ] || WANT_WINDOW_BLUR=1
            [ -n "${POPUP_BLUR_EXPLICIT:-}" ]  || WANT_POPUP_BLUR=1
            WANT_STYLING=1
            ;;
        transparent)
            [ -n "${BLUR_EXPLICIT:-}" ]        || WANT_BLUR=1
            if [ -z "${WINDOW_BLUR_EXPLICIT:-}" ]; then
                WANT_WINDOW_BLUR=0
                APP_BLUR_SCOPE="none"
            fi
            [ -n "${POPUP_BLUR_EXPLICIT:-}" ]  || WANT_POPUP_BLUR=1
            WANT_STYLING=1
            ;;
        solid)
            WANT_BLUR=0
            WANT_WINDOW_BLUR=0
            WINDOW_BLUR_EXPLICIT=1
            WANT_POPUP_BLUR=0
            POPUP_BLUR_EXPLICIT=1
            WANT_ROUNDED_BLUR=0
            APP_TRANSPARENCY=0
            APP_OPACITY=255
            WANT_STYLING=0
            ;;
        *)  # No mode to apply: a run driven by bare flags, on a machine that
            # has never been told about modes. The flags stand as given.
            ;;
    esac
}

# Written after the run has resolved, so the memo holds what was applied rather
# than what was asked for. The marker is the styling half of the same answer and
# is written here too, so the two can never disagree.
remember_glass_mode() {
    GLASS_MODE="$(glass_mode_from_state)"
    [ "${DRY_RUN:-0}" = 1 ] && return 0
    mkdir -p "$CONF_DIR"
    printf '%s\n' "$GLASS_MODE" > "$CONF_DIR/glass-mode"
    if [ "${WANT_STYLING:-1}" = 0 ]; then
        : > "$CONF_DIR/styling-off"
    else
        rm -f "$CONF_DIR/styling-off"
    fi
}
```

- [ ] **Step 6: Source the new file**

In `lib/steps.sh`, beside the other `. "$REPO_ROOT/lib/steps-*.sh"` lines, add `steps-modes.sh`. It must be sourced before `steps-css.sh` and `steps-dconf.sh`, which call into it in later tasks.

- [ ] **Step 7: Call the resolution, and print it under --dry-run**

In `install.sh`, directly above the existing `if [ "${WANT_BLUR:-1}" = 0 ]; then` transparency block (~line 725):

```bash
resolve_glass_mode
apply_glass_mode
```

And directly below the `APP_OPACITY="${APP_OPACITY:-255}"` line (~line 875), after the transparency normalisation has run:

```bash
# The one line tools/check-glass-modes.sh reads. Printed on every dry run rather
# than behind a flag of its own: the resolution is the whole of what a mode is,
# and a dry run that did not say which mode it resolved to would be describing
# everything except the question that was asked.
if [ "$DRY_RUN" = 1 ]; then
    printf '  glass-mode: %s blur=%s window=%s popup=%s transparency=%s styling=%s\n' \
        "$(glass_mode_from_state)" "$WANT_BLUR" "$WANT_WINDOW_BLUR" \
        "$WANT_POPUP_BLUR" "$APP_TRANSPARENCY" "$WANT_STYLING"
fi
```

- [ ] **Step 8: Extend the conflict check**

Replace the existing `--no-blur` / `--window-blur` check (~line 905) with one that names the mode when the mode is what turned the blur off:

```bash
if [ "$WANT_BLUR" != 1 ] && [ "$WANT_WINDOW_BLUR" = 1 ]; then
    if [ "${GLASS_MODE:-}" = solid ]; then
        die "--glass-mode solid and --window-blur contradict each other — solid mode stands the theme down entirely, so there is no blur to put behind a window. Pick one."
    fi
    die "--no-blur and --window-blur contradict each other — --no-blur leaves Blur My Shell out entirely, so there is nothing to blur behind a window. Pick one."
fi
```

- [ ] **Step 9: Call remember_glass_mode from both install paths**

In the `--settings-only` block, directly after `apply_gsettings` (~line 953), and in the full install path directly after its own `apply_gsettings` call, add:

```bash
remember_glass_mode
```

- [ ] **Step 10: Run the check**

Run: `bash tools/check-glass-modes.sh`
Expected: PASS — `glass mode check passed — 5 resolutions and 2 refusals`

- [ ] **Step 11: Wire it into the pre-commit hook**

In `tools/hooks/pre-commit`, after the app blur lists step (~line 114):

```bash
step "glass modes (tools/check-glass-modes.sh)" \
    bash "$TMP/tools/check-glass-modes.sh"
```

- [ ] **Step 12: Run the whole hook**

Run: `bash tools/hooks/pre-commit`
Expected: every step `ok`, including the new one.

- [ ] **Step 13: Commit**

```bash
git add lib/steps-modes.sh lib/steps.sh install.sh tools/check-glass-modes.sh tools/hooks/pre-commit
git commit -m "feat(modes): resolve --glass-mode into the blur flags

A mode is a name for a combination install.sh could already be asked
for, plus the memo that makes it survive a flagless run. Solid is the
styling standing down rather than the blur being off, so bare --no-blur
keeps meaning an opaque theme."
```

---

### Task 2: Per-mode memory

**Files:**
- Modify: `lib/steps-modes.sh` (append the memo store)
- Modify: `install.sh` (~line 725, between `apply_glass_mode` and the transparency block; and the two `remember_glass_mode` call sites)
- Modify: `tools/check-glass-modes.sh` (add the round-trip cases)

**Interfaces:**
- Consumes: `GLASS_MODE`, `WANT_STYLING`, `resolve_glass_mode`, `apply_glass_mode`, `remember_glass_mode` from Task 1.
- Produces: `mode_memo_path KEY`, `mode_memo_read KEY DEFAULT`, `mode_memo_write KEY VALUE`, `seed_glass_mode`, `load_glass_mode_memos`, `save_glass_mode_memos`.

- [ ] **Step 1: Write the failing test**

Append to `tools/check-glass-modes.sh`, above the `if [ "${#failures[@]}" -gt 0 ]` block. It runs against a scratch `$CONF_DIR` so the developer's own install is never read or written:

```bash
# The per-mode drawer, against a scratch CONF_DIR rather than the machine's own.
# install.sh takes it from $HOME, so a temporary HOME is the whole isolation.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/.config/aura-glass" "$scratch/.themes/Tahoe-Dark"

in_scratch() {  # in_scratch FLAG...
    HOME="$scratch" bash "$ROOT/install.sh" --settings-only --dry-run --yes "$@" 2>&1
}

printf '0.88\n' > "$scratch/.config/aura-glass/app-transparency"
in_scratch --glass-mode frosted >/dev/null
seeded="$(cat "$scratch/.config/aura-glass/modes/frosted/app-transparency" 2>/dev/null || true)"
[ "$seeded" = "0.88" ] || failures+=(
    "seeding frosted should take the level already on disk, got '$seeded'")

in_scratch --glass-mode transparent >/dev/null
seeded="$(cat "$scratch/.config/aura-glass/modes/transparent/app-transparency" 2>/dev/null || true)"
[ "$seeded" = "0.82" ] || failures+=(
    "seeding transparent should give it its own darker level, got '$seeded'")
seeded="$(cat "$scratch/.config/aura-glass/modes/transparent/app-tint-color" 2>/dev/null || true)"
[ "$seeded" = "#0b0b0f" ] || failures+=(
    "seeding transparent should give it its own tint, got '$seeded'")

# Back to frosted: its own level comes back rather than transparent's.
got="$(in_scratch --glass-mode frosted | sed -n 's/^ *glass-mode: //p' | tail -n 1)"
case "$got" in
    *"transparency=0.88"*) ;;
    *) failures+=("switching back to frosted should restore 0.88, got '$got'") ;;
esac
```

Note the dry-run caveat this test depends on: seeding and the mode memo write are the two things that must happen even under `--dry-run`, because a dry run that seeded nothing could not be asked what it resolved to. Both write only inside `$CONF_DIR/modes/`, never to the desktop.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tools/check-glass-modes.sh`
Expected: FAIL with `seeding frosted should take the level already on disk, got ''` — there is no `modes/` directory yet.

- [ ] **Step 3: Append the memo store to lib/steps-modes.sh**

```bash
# ---- the per-mode drawer ------------------------------------------------

# Every mode keeps the settings that belong to it. The top-level memos stay the
# live state — install_transparency_css, apply_app_tint_color and the settings
# window all read those, and none of them learn about modes — so these are an
# archive that the mode switch restores from, not a second source of truth.
mode_memo_path() { printf '%s/modes/%s/%s\n' "$CONF_DIR" "${GLASS_MODE:-frosted}" "$1"; }

mode_memo_read() {   # KEY DEFAULT
    local f; f="$(mode_memo_path "$1")"
    if [ -r "$f" ]; then cat "$f" 2>/dev/null || printf '%s\n' "$2"
    else printf '%s\n' "$2"; fi
}

mode_memo_write() {  # KEY VALUE
    mkdir -p "$CONF_DIR/modes/${GLASS_MODE:-frosted}"
    printf '%s\n' "$2" > "$(mode_memo_path "$1")"
}

# What a mode starts life with. Read from the top-level memos where they exist,
# so an install that predates modes keeps the tuning it is wearing and finds it
# in the tab it belongs to; from the constants only where there is nothing to
# read. Transparent is the exception that proves it: with no blur behind the
# window the wallpaper is what the text sits on, so it starts darker, and a
# level of 0 is not a state this mode has.
seed_glass_mode() {
    local dir="$CONF_DIR/modes/${GLASS_MODE:-frosted}"
    [ -d "$dir" ] && return 0
    mkdir -p "$dir"
    [ "${GLASS_MODE:-}" = solid ] && return 0

    local disk_level disk_app disk_shell disk_strength disk_scope disk_popup
    disk_level="$(cat "$CONF_DIR/app-transparency" 2>/dev/null || true)"
    disk_app="$(cat "$CONF_DIR/app-tint-color" 2>/dev/null || true)"
    disk_shell="$(cat "$CONF_DIR/shell-tint-color" 2>/dev/null || true)"
    disk_strength="$(cat "$CONF_DIR/blur-strength" 2>/dev/null || true)"
    disk_scope="$(cat "$CONF_DIR/app-blur-scope" 2>/dev/null || true)"
    disk_popup="$(cat "$CONF_DIR/popup-blur" 2>/dev/null || true)"

    if [ "${GLASS_MODE:-}" = transparent ]; then
        case "$disk_level" in ''|0|0.0|0.00) disk_level="0.82" ;; esac
        mode_memo_write app-transparency "$disk_level"
        mode_memo_write app-tint-color   "${disk_app:-#0b0b0f}"
        mode_memo_write shell-tint-color "${disk_shell:-#0b0b0f}"
    else
        mode_memo_write app-transparency "${disk_level:-0}"
        mode_memo_write app-tint-color   "${disk_app:-#000000}"
        mode_memo_write shell-tint-color "${disk_shell:-#000000}"
        mode_memo_write app-blur-scope   "${disk_scope:-gtk}"
    fi
    mode_memo_write blur-strength "${disk_strength:-100}"
    mode_memo_write popup-blur    "${disk_popup:-1}"
}

# The drawer into this run's variables. Only where the flag was not given, on
# the same precedence rule apply_glass_mode follows.
load_glass_mode_memos() {
    [ -n "${GLASS_MODE:-}" ] || return 0
    [ "${GLASS_MODE}" = solid ] && return 0

    [ -n "${APP_TRANSPARENCY_EXPLICIT:-}" ] || [ -n "${APP_TRANSPARENCY:-}" ] \
        || APP_TRANSPARENCY="$(mode_memo_read app-transparency 0)"
    [ -n "${APP_TINT_COLOR:-}" ]   || APP_TINT_COLOR="$(mode_memo_read app-tint-color '#000000')"
    [ -n "${SHELL_TINT_COLOR:-}" ] || SHELL_TINT_COLOR="$(mode_memo_read shell-tint-color '#000000')"
    [ -n "${BLUR_STRENGTH:-}" ]    || BLUR_STRENGTH="$(mode_memo_read blur-strength 100)"

    if [ -z "${POPUP_BLUR_EXPLICIT:-}" ]; then
        WANT_POPUP_BLUR="$(mode_memo_read popup-blur 1)"
    fi
    # Transparent has no scope to remember: not blurring behind windows is what
    # the mode is, and apply_glass_mode has already pinned it to none.
    if [ "${GLASS_MODE}" = frosted ] && [ -z "${APP_BLUR_SCOPE_EXPLICIT:-}" ]; then
        APP_BLUR_SCOPE="$(mode_memo_read app-blur-scope gtk)"
    fi
}

# This run's answers back into the drawer, after everything has resolved.
save_glass_mode_memos() {
    [ "${WANT_STYLING:-1}" = 0 ] && return 0
    mode_memo_write app-transparency "${APP_TRANSPARENCY:-0}"
    mode_memo_write app-tint-color   "${APP_TINT_COLOR:-#000000}"
    mode_memo_write shell-tint-color "${SHELL_TINT_COLOR:-#000000}"
    mode_memo_write blur-strength    "${BLUR_STRENGTH:-100}"
    mode_memo_write popup-blur       "${WANT_POPUP_BLUR:-1}"
    [ "${GLASS_MODE:-}" = frosted ] && mode_memo_write app-blur-scope "${APP_BLUR_SCOPE:-gtk}"
    return 0
}
```

- [ ] **Step 3b: Reseed a drawer holding a value install.sh would reject**

A hand-edited or half-written drawer must not be sent onward. Append the guard
to `load_glass_mode_memos`, directly above its first read:

```bash
    # A value install.sh would refuse is treated as an empty drawer rather than
    # passed along: the flag it would become dies in the parser, which is a
    # failure a long way from the file that caused it.
    local level; level="$(mode_memo_read app-transparency 0)"
    case "$level" in
        0|0.[0-9][0-9]|1.00) ;;
        *) warn "$(mode_memo_path app-transparency) holds '$level' — reseeding this mode"
           rm -rf "$CONF_DIR/modes/$GLASS_MODE"
           seed_glass_mode ;;
    esac
```

- [ ] **Step 4: Call seeding and loading from install.sh**

Change the block added in Task 1 Step 7 to:

```bash
resolve_glass_mode
apply_glass_mode
seed_glass_mode
load_glass_mode_memos
```

`seed_glass_mode` runs before `load_glass_mode_memos` so the first run of a mode reads the drawer it has just filled.

- [ ] **Step 5: Save the drawer at the end of the run**

In `lib/steps-modes.sh`, extend `remember_glass_mode` so the drawer is written with the mode, by inserting `save_glass_mode_memos` immediately after the `printf ... > "$CONF_DIR/glass-mode"` line. The `[ "${DRY_RUN:-0}" = 1 ] && return 0` guard above it stays where it is, so a dry run writes neither.

Seeding is deliberately on the other side of that guard: `seed_glass_mode` writes under `--dry-run` too, because it creates only the drawer and a dry run that skipped it could not report the level the mode resolves to.

- [ ] **Step 6: Run the check**

Run: `bash tools/check-glass-modes.sh`
Expected: PASS — the five resolutions, the two refusals and the four round-trip assertions.

- [ ] **Step 7: Confirm nothing regressed**

Run: `bash tools/hooks/pre-commit`
Expected: every step `ok`.

- [ ] **Step 8: Commit**

```bash
git add lib/steps-modes.sh install.sh tools/check-glass-modes.sh
git commit -m "feat(modes): give each mode its own opacity, tint and strength

Switching to transparent and back used to cost the frosted tuning,
because there was one set of memos for what are three different
answers. The top-level memos stay the live state; the drawer under
modes/ is what a switch restores from."
```

---

### Task 3: Solid stands the stylesheets down

**Files:**
- Modify: `bin/aura-glass-apply` (after the `GTK3_CSS` assignment ~line 17, before the `apply()` definition)
- Modify: `lib/steps-css.sh` (`install_css`, ~line 271)
- Create: `tools/check-styling-off.sh`
- Modify: `tools/hooks/pre-commit`

**Interfaces:**
- Consumes: `WANT_STYLING` and the `$CONF_DIR/styling-off` marker from Task 1.
- Produces: the marker's effect on `bin/aura-glass-apply`; no new shell functions for later tasks.

- [ ] **Step 1: Write the failing test**

Create `tools/check-styling-off.sh`:

```bash
#!/usr/bin/env bash
# Assert bin/aura-glass-apply splices when the theme is up and stands it down
# when the marker is there — against a fixture HOME, never the real desktop.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=()

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
conf="$fixture/.config/aura-glass"
mkdir -p "$conf/backups" "$fixture/.config/gtk-4.0" "$fixture/.config/gtk-3.0" \
         "$fixture/.themes/Tahoe-Dark/gnome-shell"

shell_css="$fixture/.themes/Tahoe-Dark/gnome-shell/gnome-shell.css"
gtk4_css="$fixture/.config/gtk-4.0/gtk.css"

printf 'stage { box-shadow: 0 2px 4px rgba(0,0,0,0.5); }\n' > "$shell_css"
cp "$shell_css" "$conf/backups/gnome-shell.css.orig"
printf '/* theme */\nwindow { background: black; }\n' > "$gtk4_css"
cp "$gtk4_css" "$conf/backups/gtk4-gtk.css.orig"
printf 'stage { color: white; }\n' > "$conf/shell-00-flat.css"
printf 'window { color: white; }\n' > "$conf/gtk4-00-flat.css"
printf '* { outline: none; }\n' > "$conf/gtk3-tweaks.css"

apply_it() { HOME="$fixture" bash "$ROOT/bin/aura-glass-apply" >/dev/null 2>&1; }

apply_it
grep -q 'aura-glass BEGIN' "$shell_css" \
    || failures+=("with no marker the shell sheet should carry the block")
grep -q 'aura-glass BEGIN' "$gtk4_css" \
    || failures+=("with no marker the gtk4 sheet should carry the block")

: > "$conf/styling-off"
apply_it
grep -q 'aura-glass BEGIN' "$shell_css" \
    && failures+=("with the marker the shell sheet should have no block")
grep -q 'box-shadow: 0 2px 4px' "$shell_css" \
    || failures+=("the shell sheet should be the pristine backup again, shadows and all")
grep -q 'aura-glass BEGIN' "$gtk4_css" \
    && failures+=("with the marker the gtk4 sheet should have no block")

# Twice is the same as once.
before="$(cat "$shell_css")"
apply_it
[ "$before" = "$(cat "$shell_css")" ] \
    || failures+=("standing down twice should change nothing the second time")

# And back again.
rm -f "$conf/styling-off"
apply_it
grep -q 'aura-glass BEGIN' "$shell_css" \
    || failures+=("removing the marker should put the block back")

if [ "${#failures[@]}" -gt 0 ]; then
    printf 'styling-off check FAILED\n\n'
    printf '  %s\n' "${failures[@]}"
    exit 1
fi
printf 'styling-off check passed — splice, stand down, idempotent, and back\n'
```

Make it executable: `chmod +x tools/check-styling-off.sh`.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tools/check-styling-off.sh`
Expected: FAIL with `with the marker the shell sheet should have no block` — the marker means nothing yet.

- [ ] **Step 3: Add the stand-down path to bin/aura-glass-apply**

Directly below the `GTK3_CSS=` assignment and the GTK3 file creation (~line 23):

```bash
# The theme standing down, which is what solid mode is. install.sh writes the
# marker; this is the only thing that reads it, because this is the only thing
# that ever put the block into a target in the first place.
#
# Stripping is not enough on its own for the three theme-generated files: apply
# flattens the theme's own shadow and gradient values in place, so a sheet with
# the block removed is still a flattened sheet. Where there is a backup it is
# restored; where the file existed only because the theme's installer made it
# (an .absent marker beside the backups) it goes; otherwise the block is
# stripped and whatever else is in there is left alone. This is the same rule
# uninstall.sh's restore() follows, for the same reason.
if [ -f "$DIR/styling-off" ]; then
    stand_down() {   # stand_down TARGET BACKUP_NAME
        local target="$1" name="$2" bak="$DIR/backups/$2.orig"
        if [ -f "$bak" ]; then
            cp -a "$bak" "$target"
            echo "restored $target"
            return
        fi
        if [ -e "$DIR/backups/$name.absent" ]; then
            rm -f "$target"
            echo "removed $target (nothing was there before)"
            return
        fi
        [ -f "$target" ] || { echo "skip (missing target): $target"; return; }
        python3 - "$target" <<'PY'
import sys, re
target = sys.argv[1]
css = open(target, encoding="utf-8").read()
new = css
for name in ("aura-glass", "tahoe-glass", "tahoe-tweaks"):
    new = re.sub(
        r"/\* >>> %s BEGIN <<< \*/.*?/\* >>> %s END <<< \*/\n?" % (name, name),
        "", new, flags=re.S,
    )
if new != css:
    open(target, "w", encoding="utf-8").write(new)
    print("stripped", target)
else:
    print("no block in", target)
PY
    }
    stand_down "$SHELL_CSS"     "gnome-shell.css"
    stand_down "$GTK4_CSS"      "gtk4-gtk.css"
    stand_down "$GTK4_DARK_CSS" "gtk4-gtk-dark.css"
    stand_down "$GTK3_CSS"      "gtk3-gtk.css"
    echo "the theme has stood down — restart GTK apps to pick up the GTK side"
    exit 0
fi
```

The script's existing shell-theme reload block sits below this and is skipped by the `exit 0`: in solid mode the user-theme extension is switched off in Task 5, so there is no theme to reload.

- [ ] **Step 4: Run the check to see it pass**

Run: `bash tools/check-styling-off.sh`
Expected: PASS — `styling-off check passed — splice, stand down, idempotent, and back`

- [ ] **Step 5: Write the marker from install_css**

In `lib/steps-css.sh`, at the top of `install_css` directly after the `step "Installing the CSS tweaks"` line:

```bash
    # The marker goes down before aura-glass-apply runs at the end of this
    # function, because that is what reads it. The sheets are copied into
    # $CONF_DIR either way: they cost nothing while nothing splices them, and
    # having them there is what makes coming back out of solid mode one run.
    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        if [ "${WANT_STYLING:-1}" = 0 ]; then : > "$CONF_DIR/styling-off"
        else rm -f "$CONF_DIR/styling-off"; fi
    fi
```

- [ ] **Step 6: Verify install.sh still resolves**

Run: `bash install.sh --settings-only --dry-run --yes --glass-mode solid | tail -n 20`
Expected: the run reaches `Done` and the `glass-mode: solid ... styling=0` line is printed; no error.

- [ ] **Step 7: Wire the check into the pre-commit hook**

In `tools/hooks/pre-commit`, after the glass modes step from Task 1:

```bash
step "styling off (tools/check-styling-off.sh)" \
    bash "$TMP/tools/check-styling-off.sh"
```

- [ ] **Step 8: Run the whole hook**

Run: `bash tools/hooks/pre-commit`
Expected: every step `ok`.

- [ ] **Step 9: Commit**

```bash
git add bin/aura-glass-apply lib/steps-css.sh tools/check-styling-off.sh tools/hooks/pre-commit
git commit -m "feat(solid): take the CSS block out instead of restyling

Solid mode is the theme standing down, so the block comes out of all
four targets and the three theme-generated files go back to their
backups — stripping alone leaves a flattened sheet behind, because
that is what apply rewrote in place."
```

---

### Task 4: Solid puts the shell and the GTK theme back

**Files:**
- Modify: `lib/steps-dconf.sh` (`apply_gsettings`, ~line 665-716)
- Modify: `install.sh` (both `load_dconf` call sites: the `--settings-only` block ~line 951 and the full path)
- Modify: `tools/check-glass-modes.sh` (add the dry-run assertions)

**Interfaces:**
- Consumes: `WANT_STYLING`, `GLASS_MODE` from Task 1.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

Append to `tools/check-glass-modes.sh`, above the failure report:

```bash
# Solid leaves the packs and the accent alone and puts the two theme keys back.
out="$(in_scratch --glass-mode solid)"
case "$out" in
    *"gtk-theme"*"reset"*) ;;
    *) failures+=("solid should reset gtk-theme, the run never mentions it") ;;
esac
case "$out" in
    *"dconf load"*"core.ini"*)
        failures+=("solid should not load the dconf preset — it would rewrite the extensions' own settings") ;;
esac
case "$out" in
    *"icon-theme"*) ;;
    *) failures+=("solid should still set the icon theme — the packs stay") ;;
esac
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tools/check-glass-modes.sh`
Expected: FAIL with `solid should reset gtk-theme, the run never mentions it` and `solid should not load the dconf preset`.

- [ ] **Step 3: Split apply_gsettings**

In `lib/steps-dconf.sh`, replace the three theme lines inside `apply_gsettings` (`color-scheme`, `gtk-theme`, `accent-color`) with:

```bash
    # prefer-dark and the accent are GNOME's own keys and a preference of the
    # user's, not this theme's styling, so they stand in every mode. The GTK
    # theme is ours, and in solid mode it goes back to GNOME's default along
    # with the shell theme — that pair is what makes a stood-down desktop look
    # like one, rather than a themed desktop with the blur removed.
    run gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    run gsettings set org.gnome.desktop.interface accent-color "$ACCENT"
    if [ "${WANT_STYLING:-1}" = 1 ]; then
        run gsettings set org.gnome.desktop.interface gtk-theme 'Tahoe-Dark'
        run dconf write /org/gnome/shell/extensions/user-theme/name "'Tahoe-Dark'"
    else
        run gsettings reset org.gnome.desktop.interface gtk-theme
        run dconf write /org/gnome/shell/extensions/user-theme/name "''"
        ok "gtk-theme and the shell theme reset — the theme has stood down"
    fi
```

Then change the closing `ok` line of the function so it does not claim a theme that is not set:

```bash
    if [ "${WANT_STYLING:-1}" = 1 ]; then
        ok "gtk-theme=Tahoe-Dark  icons=$icons  cursor=$cursor  accent=$ACCENT"
    else
        ok "icons=$icons  cursor=$cursor  accent=$ACCENT — theme keys left at GNOME's defaults"
    fi
```

- [ ] **Step 4: Skip the dconf preset in solid mode**

In `install.sh`, at both `load_dconf` call sites, guard it:

```bash
    # Not in solid mode. dconf/core.ini is every extension's settings, and
    # loading it is exactly the "modifying the extension" that standing down is
    # supposed to avoid — the extensions are switched off with their own
    # settings intact, ready for the way back.
    if [ "$WANT_STYLING" = 1 ]; then
        load_dconf
    else
        step "Loading the dconf preset"
        skip "solid mode — the extensions keep their own settings"
    fi
```

- [ ] **Step 5: Run the check**

Run: `bash tools/check-glass-modes.sh`
Expected: PASS.

- [ ] **Step 6: Confirm the other modes are untouched**

Run: `bash install.sh --settings-only --dry-run --yes --glass-mode frosted | grep -E "gtk-theme|core.ini"`
Expected: both present — the preset is loaded and `gtk-theme` is set to `Tahoe-Dark`.

- [ ] **Step 7: Commit**

```bash
git add lib/steps-dconf.sh install.sh tools/check-glass-modes.sh
git commit -m "feat(solid): put the GTK and shell themes back to GNOME's

The accent, the icons and the pointer are the user's and stay. The
dconf preset is skipped outright in solid mode: loading it is the one
thing that would overwrite the extension settings this mode exists to
leave alone."
```

---

### Task 5: Solid switches the extensions off and back on

**Files:**
- Modify: `lib/steps-extensions.sh` (append after `enqueue_extension`, ~line 473)
- Modify: `install.sh` (both paths, directly after the `apply_gsettings` call and before `remember_glass_mode`)
- Modify: `tools/check-glass-modes.sh` (dry-run assertions)

**Interfaces:**
- Consumes: `WANT_STYLING`, `GLASS_MODE`, `mode_memo_path` (Task 2), `EXT_CORE`, `EXT_EXTRA_ALL`, `BMS_UUID` (`lib/steps.sh`).
- Produces: `glass_owned_extensions`, `stand_down_extensions`, `restore_extensions`.

- [ ] **Step 1: Write the failing test**

Append to `tools/check-glass-modes.sh`, above the failure report:

```bash
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
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tools/check-glass-modes.sh`
Expected: FAIL with `solid should stand the extensions down, the run never mentions it`.

- [ ] **Step 3: Append the two steps to lib/steps-extensions.sh**

```bash
# ---- standing the extensions down ---------------------------------------

# Everything this project ever enables, which is the set it is entitled to
# switch off again. A user's own extensions are outside it and are never
# touched in either direction — that is the whole point of computing the
# intersection rather than disabling a list.
glass_owned_extensions() {
    printf '%s\n' "${EXT_CORE[@]}" openbar@neuromorph "$BMS_UUID" \
        custom-osd@neuromorph "${EXT_EXTRA_ALL[@]}"
}

# Solid mode. The UUIDs that are enabled right now and are ours get written
# down and switched off; nothing else about them is touched, so every one of
# them keeps its own settings and comes back exactly as it was. The record is
# what makes the way back exact rather than a guess at what was on.
stand_down_extensions() {
    step "Standing the extensions down"
    local record enabled u wrote=0
    record="$CONF_DIR/modes/solid/disabled-extensions"

    enabled="$(gnome-extensions list --enabled 2>/dev/null || true)"
    if [ -z "$enabled" ]; then
        skip "the shell lists nothing enabled — nothing to switch off"
        return 0
    fi

    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR/modes/solid"
        : > "$record"
    fi

    while IFS= read -r u; do
        [ -n "$u" ] || continue
        case "
$enabled
" in
            *"
$u
"*) ;;
            *) continue ;;
        esac
        [ "${DRY_RUN:-0}" = 1 ] || printf '%s\n' "$u" >> "$record"
        wrote=$((wrote + 1))
        run gnome-extensions disable "$u" 2>/dev/null \
            || warn "could not switch $u off — it is still written down, so the way back still tries it"
    done < <(glass_owned_extensions)

    if [ "$wrote" -eq 0 ]; then
        skip "none of this project's extensions are enabled"
    else
        ok "$wrote extension(s) switched off, their settings untouched"
    fi
}

# The way back out of solid mode. Exactly what was written down, in the order
# it was written, and then the record goes: it describes a state that no longer
# exists the moment this succeeds.
restore_extensions() {
    local record="$CONF_DIR/modes/solid/disabled-extensions" u back=0
    [ -r "$record" ] || return 0
    step "Switching the extensions back on"

    while IFS= read -r u; do
        [ -n "$u" ] || continue
        if [ ! -d "$EXT_DIR/$u" ] && [ ! -d "/usr/share/gnome-shell/extensions/$u" ]; then
            skip "$u is no longer installed"
            continue
        fi
        if run gnome-extensions enable "$u" 2>/dev/null; then
            back=$((back + 1))
            continue
        fi
        # The same fallback enable_extensions uses: on Wayland the running
        # shell will not load a UUID it did not start with, so it goes into
        # enabled-extensions for the next session instead.
        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: add $u to enabled-extensions for the next session"
        elif enqueue_extension "$u"; then
            ok "$u queued — active after logout"
            back=$((back + 1))
        else
            warn "could not switch $u back on"
        fi
    done < "$record"

    [ "${DRY_RUN:-0}" = 1 ] || rm -f "$record"
    ok "$back extension(s) back on"
}
```

- [ ] **Step 4: Call them from install.sh**

At both `apply_gsettings` call sites, directly below it and above `remember_glass_mode`:

```bash
    if [ "$WANT_STYLING" = 0 ]; then
        stand_down_extensions
    else
        restore_extensions
    fi
```

`restore_extensions` returns immediately when there is no record, so this costs nothing on a machine that has never been in solid mode.

- [ ] **Step 5: Run the check**

Run: `bash tools/check-glass-modes.sh`
Expected: PASS.

- [ ] **Step 6: Verify the record round-trips by hand**

Run, on a live desktop only:

```bash
./install.sh --settings-only -y --glass-mode solid
cat ~/.config/aura-glass/modes/solid/disabled-extensions
gnome-extensions list --enabled
```

Expected: the record lists the aura-glass extensions that were on; `--enabled` no longer shows them; extensions you installed yourself are still listed. Then:

```bash
./install.sh --settings-only -y --glass-mode frosted
gnome-extensions list --enabled
```

Expected: the recorded UUIDs are back, the record file is gone, and `dconf dump /org/gnome/shell/extensions/blur-my-shell/` still holds the settings it held before the round trip.

- [ ] **Step 7: Commit**

```bash
git add lib/steps-extensions.sh install.sh tools/check-glass-modes.sh
git commit -m "feat(solid): switch this project's extensions off, settings intact

The set is computed as the intersection of what is enabled with what
this project installs, so a user's own extensions are never touched,
and the record of what was switched off is what makes the way back
exact rather than a guess."
```

---

### Task 6: The window learns what a mode is

**Files:**
- Modify: `gui/aura_glass_settings.py` (`Settings.__init__` ~line 1217-1230, `Settings.flags_against` ~line 1341-1370, `Window._current` ~line 3548)
- Modify: `tools/check-gui-flags.py` (`state()` ~line 43, `CASES` ~line 110)

**Interfaces:**
- Consumes: the memo `$CONF_DIR/glass-mode` and marker `$CONF_DIR/styling-off` from Tasks 1 and 3.
- Produces: `Settings.glass_mode` (str, one of `"frosted" | "transparent" | "solid"`), and `flags_against` emitting `["--glass-mode", mode]`.

- [ ] **Step 1: Write the failing test**

In `tools/check-gui-flags.py`, add the field to `state()` directly below the `s.blur` line:

```python
    s.glass_mode = kw.get("glass_mode", "frosted")
```

and add these cases to `CASES`, replacing the two existing `frosted -> solid` / `solid -> frosted` entries:

```python
    # The mode carries the flags it implies, so they are not restated. Sending
    # --glass-mode solid --no-window-blur --no-popup-blur would be the same
    # sentence three times, and the third one is the combination install.sh
    # refuses.
    ("frosted -> solid", FROSTED, state(glass_mode="solid", blur=False,
                                        transparency="0", popup_blur=False,
                                        scope="none"),
     ["--glass-mode", "solid"]),

    ("solid -> frosted", state(glass_mode="solid", blur=False, transparency="0",
                               popup_blur=False, scope="none"),
     state(), ["--glass-mode", "frosted"]),

    ("frosted -> transparent carries its own level and tint", FROSTED,
     state(glass_mode="transparent", scope="none", transparency="0.82",
           app_tint="#0b0b0f", shell_tint="#0b0b0f"),
     ["--glass-mode", "transparent", "--app-transparency", "0.82",
      "--app-tint-color", "#0b0b0f", "--shell-tint-color", "#0b0b0f"]),

    ("a level moved inside transparent is not a mode change",
     state(glass_mode="transparent", scope="none", transparency="0.82"),
     state(glass_mode="transparent", scope="none", transparency="0.78"),
     ["--app-transparency", "0.78"]),

    ("the popup switch inside transparent",
     state(glass_mode="transparent", scope="none", transparency="0.82"),
     state(glass_mode="transparent", scope="none", transparency="0.82",
           popup_blur=False),
     ["--no-popup-blur"]),

    ("frosted -> solid with a radius change", FROSTED,
     state(glass_mode="solid", blur=False, transparency="0",
           popup_blur=False, scope="none", radius="sharp"),
     ["--radius-preset", "sharp", "--glass-mode", "solid"]),
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 tools/check-gui-flags.py`
Expected: FAIL — `frosted -> solid: wanted ['--glass-mode', 'solid'], got ['--no-blur']`.

- [ ] **Step 3: Read the mode in Settings.__init__**

In `gui/aura_glass_settings.py`, replace the `self.blur = not os.path.exists(...)` block with:

```python
        # The mode is the memo install.sh wrote, and the marker outranks it for
        # the same reason install.sh's resolve_glass_mode gives it precedence:
        # the marker is the state the desktop is in, the memo is a note about
        # it. A machine from before modes existed has neither, so the mode is
        # read out of what is installed — which is exactly what the window used
        # to do for the one switch this replaces.
        if os.path.exists(os.path.join(CONF_DIR, "styling-off")):
            self.glass_mode = "solid"
        else:
            mode = read_memo("glass-mode", "") or ""
            if mode not in GLASS_MODES:
                mode = ""
            self.glass_mode = mode

        # Solid mode has no memo of its own for the blur: install_css encodes it
        # by whether the solid sheet is installed at all.
        self.blur = not os.path.exists(
            os.path.join(CONF_DIR, "shell-80-solid.css"))
```

and after `self.popup_blur` is read (~line 1229), fill in a mode for a machine that has none:

```python
        if not self.glass_mode:
            # Derived exactly as glass_mode_from_state does in
            # lib/steps-modes.sh: the two have to agree, because the window
            # showing one tab while install.sh resolves another is the one bug
            # a mode can have that nothing else would catch.
            if self.blur and self.scope == "none" and self.transparency != "0":
                self.glass_mode = "transparent"
            else:
                self.glass_mode = "frosted"
```

Add the constant beside `BLUR_SCOPES` (~line 297):

```python
# The three modes, in the order the tabs show them. Solid is last because it is
# the one that takes the theme away.
GLASS_MODES = ["frosted", "transparent", "solid"]
```

- [ ] **Step 4: Read every mode's drawer, not only the active one**

The transparent tab has to show its own opacity while frosted is the mode in
force, and the only place that value exists is the drawer install.sh wrote it
to. Add the reader beside `read_memo` in `gui/aura_glass_settings.py`:

```python
def read_mode_memo(mode, key, default):
    """One value out of a mode's drawer under $CONF_DIR/modes/<mode>/.

    The drawer is written by save_glass_mode_memos in lib/steps-modes.sh at the
    end of every run. Missing is normal — a mode that has never been applied on
    this machine has no drawer — so every read carries the seed that
    seed_glass_mode would have used, and the two lists have to stay in step.
    """
    try:
        with open(os.path.join(CONF_DIR, "modes", mode, key),
                  encoding="utf-8") as fh:
            value = fh.read().strip()
    except OSError:
        return default
    return value or default
```

And in `Settings.__init__`, directly below the block that fills in `glass_mode`:

```python
        # Every mode's own settings, so switching tabs can show them without
        # applying anything. The seeds match seed_glass_mode's.
        self.modes = {}
        for mode in GLASS_MODES:
            if mode == "solid":
                continue
            level = "0.82" if mode == "transparent" else "0"
            tint = "#0b0b0f" if mode == "transparent" else "#000000"
            try:
                strength = int(read_mode_memo(mode, "blur-strength", "100"))
            except ValueError:
                strength = 100
            self.modes[mode] = {
                "transparency": read_mode_memo(mode, "app-transparency", level),
                "app_tint": read_mode_memo(mode, "app-tint-color", tint),
                "shell_tint": read_mode_memo(mode, "shell-tint-color", tint),
                "blur_strength": strength,
                "popup_blur": read_mode_memo(mode, "popup-blur", "1") != "0",
                "scope": read_mode_memo(mode, "app-blur-scope", "gtk"),
            }

        # The mode in force is the live state whatever its drawer says: the
        # drawer is written at the end of a run, and a memo edited by hand must
        # not outrank the sheet that is actually installed.
        if self.glass_mode in self.modes:
            self.modes[self.glass_mode].update({
                "transparency": self.transparency,
                "app_tint": self.app_tint,
                "shell_tint": self.shell_tint,
                "blur_strength": self.blur_strength,
                "popup_blur": self.popup_blur,
                "scope": self.scope,
            })
```

This block reads `self.transparency` and the tints, so it must sit **after** they
are read — put it at the end of `__init__`, below `self.update_available`.
`tools/check-gui-flags.py` builds its states with `Settings.__new__` and never
touches `self.modes`, so nothing there needs it; `flags_against` must not read it
either, for the same reason.

- [ ] **Step 5: Emit the flag from flags_against**

Replace the blur block in `flags_against` (the `--blur`/`--no-blur`, scope, transparency and popup sections, ~lines 1341-1368) with:

```python
        # The mode first, and the flags it already implies are not restated.
        # install.sh resolves a mode into exactly these, so sending both would
        # be the same sentence twice — and in solid's case the second half is
        # the combination install.sh refuses outright.
        mode_changed = self.glass_mode != other.glass_mode
        if mode_changed:
            args += ["--glass-mode", self.glass_mode]

        if self.glass_mode == "solid":
            return args

        # Only frosted has a scope to send: not blurring behind windows is what
        # transparent is, and --glass-mode transparent has already said it.
        if self.glass_mode == "frosted" and (
                self.scope != other.scope or mode_changed):
            if not (mode_changed and self.scope == "gtk"):
                args.append({"gtk": "--gtk-apps-blur",
                             "all": "--all-apps-blur",
                             "none": "--no-window-blur"}[self.scope])

        # --no-window-blur moves the level to 0.95 unless the level is given, so
        # the level goes after the scope flag and always states itself when
        # either the scope or the mode moved.
        if (self.transparency != other.transparency
                or self.scope != other.scope or mode_changed):
            if self.transparency == "0":
                args.append("--no-app-transparency")
            else:
                args += ["--app-transparency", self.transparency]

        if self.popup_blur != other.popup_blur:
            args.append("--popup-blur" if self.popup_blur
                        else "--no-popup-blur")
```

Then, in the tint section below it, change the guard `if self.app_tint != other.app_tint and self.transparency != "0":` to also fire on a mode change, since a mode brings its own tints:

```python
        if ((self.app_tint != other.app_tint or mode_changed)
                and self.transparency != "0"):
```

and the same for the shell tint and the blur strength:

```python
        if self.shell_tint != other.shell_tint or mode_changed:
        ...
        if self.blur_strength != other.blur_strength or mode_changed:
```

- [ ] **Step 6: Carry the mode through _current**

In `Window._current`, below `s.blur = ...`, add:

```python
        s.glass_mode = self._glass_mode()
```

and add the accessor beside `_scope` (which is near `_current`):

```python
    def _glass_mode(self):
        """Which tab is showing, which is which mode is being asked for."""
        return self._mode_stack.get_visible_child_name()
```

`self._mode_stack` is built in Task 7. To keep this task's tests runnable before that, `check-gui-flags.py` constructs `Settings` objects directly and never builds a `Window`, so nothing here needs the widget to exist yet.

- [ ] **Step 7: Run the check**

Run: `python3 tools/check-gui-flags.py`
Expected: PASS — `gui flag check passed — N transitions compose and parse`, where every case including the six new ones both composes and survives `install.sh --settings-only --dry-run`.

- [ ] **Step 8: Commit**

```bash
git add gui/aura_glass_settings.py tools/check-gui-flags.py
git commit -m "feat(gui): send the glass mode as one flag

The mode implies the blur flags, so Apply sends the mode instead of
restating them — which is also the only way to say solid without
writing the combination install.sh refuses."
```

---

### Task 7: Three tabs on the Glass page

**Files:**
- Modify: `gui/aura_glass_settings.py` (`_build_glass_page` ~line 2314-2432, `_sync_sensitivity` ~line 3578, `_reload` ~line 3655, `_on_changed` ~line 3629)

**Interfaces:**
- Consumes: `Settings.glass_mode`, `GLASS_MODES`, `Window._glass_mode` from Task 6.
- Produces: `self._mode_stack` (`Adw.ViewStack` whose child names are the three mode ids), and the per-mode rows `self._t_transparency_scale`, `self._t_popup_row`, `self._t_strength_scale` used by `_current` and `_reload`.

- [ ] **Step 1: Rebuild the page as a switcher over three pages**

Replace `_build_glass_page` with a shell that returns the box, and three builders beneath it:

```python
    def _build_glass_page(self):
        """The three modes, as three tabs.

        The tab is the mode: switching one is asking for the other mode, in the
        ordinary pending way every other control here works, and Apply is what
        commits it. Browsing is distinguishable from choosing because the
        applied mode keeps its mark until Apply moves it.

        Each tab owns its own controls rather than sharing dimmed ones. The page
        this replaces spent four rows and a sensitivity pass explaining which of
        its switches did not apply right now; a control that does not apply to
        the mode you are in is simply in another tab.
        """
        self._mode_stack = Adw.ViewStack()
        self._mode_stack.add_titled_with_icon(
            self._build_frosted_page(), "frosted", "Frosted glass",
            "weather-fog-symbolic")
        self._mode_stack.add_titled_with_icon(
            self._build_transparent_page(), "transparent", "Transparent",
            "view-reveal-symbolic")
        self._mode_stack.add_titled_with_icon(
            self._build_solid_page(), "solid", "Solid",
            "checkbox-symbolic")
        self._mode_stack.set_visible_child_name(self._applied.glass_mode)
        self._mode_stack.connect("notify::visible-child-name",
                                 self._on_mode_switched)

        switcher = Adw.ViewSwitcher(stack=self._mode_stack,
                                    policy=Adw.ViewSwitcherPolicy.WIDE,
                                    halign=Gtk.Align.CENTER,
                                    margin_top=12, margin_bottom=6)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(switcher)
        box.append(self._mode_stack)
        self._mode_stack.set_vexpand(True)
        return box

    def _on_mode_switched(self, _stack, _param):
        if self._loading:
            return
        self._rebuild_app_list()
        self._mark_dirty()
```

- [ ] **Step 2: Move the existing page into the frosted builder**

`_build_frosted_page` is the body of the old `_build_glass_page` with two changes: the `self._blur_row` switch is gone — solid is a tab now, not a switch — and the group's description no longer mentions solid mode:

```python
    def _build_frosted_page(self):
        page = Adw.PreferencesPage()
        page.add(tip_card(
            "<b>Blur is the most expensive thing in this window.</b> The GPU "
            "redraws every blurred surface as what is behind it moves, and the "
            "shell has more to composite each frame, so it costs CPU too. On an "
            "integrated GPU, a 4K screen or a laptop on battery expect slower "
            "animations, dropped frames and less battery.\n\nIf the desktop "
            "feels heavy, turn off <b>Blur behind all application windows</b> "
            "first, then try the Transparent tab, then Solid."))

        glass = Adw.PreferencesGroup(
            title="Glass",
            description="Blur behind windows, popups and the panel.")
```

then the existing `self._window_blur_row`, `self._blur_all_row`, `self._transparency_on`, the opacity scale and row, `self._transparency_bar`, the `popups` group with `self._popup_row`, `self._build_tint_group()` and `self._build_blur_strength_group()` follow unchanged, and the method returns `page`.

- [ ] **Step 3: Write the transparent builder**

```python
    def _build_transparent_page(self):
        """Translucent windows with nothing blurred behind them.

        Two controls and a switch. There is no translucency on/off here: turning
        it off is asking for a different mode, and the tab bar is where that is
        asked. The level and the tint are this mode's own — they are not the
        ones the frosted tab shows, and moving one here does not move that one.
        """
        page = Adw.PreferencesPage()
        page.add(tip_card(
            "Windows let the wallpaper through without the GPU cost of blurring "
            "it. Nothing is blurred behind a window, so the wallpaper is what "
            "your text sits on — which is why this mode starts darker and why "
            "70% is still the floor."))

        group = Adw.PreferencesGroup(
            title="Transparency",
            description="How much of the desktop comes through an app window.")

        self._t_transparency_scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, TRANSPARENCY_MIN, TRANSPARENCY_MAX, 1)
        self._t_transparency_scale.set_hexpand(True)
        self._t_transparency_scale.set_draw_value(False)
        for at, label in TRANSPARENCY_MARKS:
            self._t_transparency_scale.add_mark(at, Gtk.PositionType.BOTTOM,
                                                label)
        self._t_transparency_scale.set_value(level_to_percent(
            self._applied.modes["transparent"]["transparency"]))
        self._t_transparency_scale.connect("value-changed",
                                           self._on_scale_changed)

        self._t_transparency_value = Gtk.Label(valign=Gtk.Align.CENTER)
        self._t_transparency_value.add_css_class("numeric")
        self._t_transparency_value.add_css_class("dim-label")

        row = Adw.ActionRow(
            title="Opacity",
            subtitle="Lower is more see-through. Below 70% the text stops "
                     "holding up over a bright wallpaper, so that is the floor")
        row.add_suffix(self._t_transparency_value)
        group.add(row)

        bar = Gtk.Box(margin_start=12, margin_end=12, margin_top=4,
                      margin_bottom=4)
        bar.append(self._t_transparency_scale)
        group.add(bar)
        page.add(group)

        popups = Adw.PreferencesGroup(
            title="Popups",
            description="The one blur this mode has. Menus and the panel are a "
                        "fraction of the pixels a window is, so this costs a "
                        "fraction of what window blur costs.")
        self._t_popup_row = Adw.SwitchRow(
            title="Blur behind menus and the top bar",
            subtitle="Popups, Quick Settings and the panel",
            active=self._applied.modes["transparent"]["popup_blur"])
        self._t_popup_row.connect("notify::active", self._on_changed,
                                  "popup_blur")
        popups.add(self._t_popup_row)
        page.add(popups)

        page.add(self._build_tint_group())
        page.add(self._build_blur_strength_group(
            description="How far the popup and panel blur reaches. Nothing "
                        "else is blurred in this mode, so this is the only "
                        "thing it moves."))
        self._sync_transparency_value()
        return page
```

The two shared groups are built once per tab, so they take the mode they belong
to. See Step 3b below — write that step before this one compiles.

- [ ] **Step 3b: Make the tint and blur-strength groups per-mode**

Both groups are written today as build-once helpers that stash their widgets on
single attributes (`self._app_tint_row`, `self._blur_strength_scale`, …). Two
tabs need two independent sets, so they take the mode and stash per mode. A
widget has one parent, so sharing one group between two pages is not an option.

Change the two signatures and their storage:

```python
    def _build_tint_group(self, mode, description=None):
        """The colour under the glass, for one mode.

        ...the existing docstring, unchanged...
        """
        tints = self._tints.setdefault(mode, {
            "app": self._applied.modes[mode]["app_tint"],
            "shell": self._applied.modes[mode]["shell_tint"],
        })
        rows = self._tint_rows.setdefault(mode, {})

        group = Adw.PreferencesGroup(
            title="Tint",
            description=description or ("What the glass is coloured with. ..."))

        rows["link"] = Adw.SwitchRow(
            title="One colour for both",
            subtitle="Point the shell at whatever the app windows are tinted "
                     "with",
            active=tints["app"] == tints["shell"])
        rows["link"].connect("notify::active", self._on_tint_link, mode)
        group.add(rows["link"])

        rows["app"] = self._tint_row(
            "App windows",
            "GTK and libadwaita windows, wherever they are translucent",
            "app", mode)
        group.add(rows["app"])
        rows["shell"] = self._tint_row(
            "Shell surfaces",
            "The panel, menus, Quick Settings, notifications and dialogs",
            "shell", mode)
        group.add(rows["shell"])
        ...   # the preview row, unchanged
        return group
```

`_tint_row`, `_on_tint_picked` and `_on_tint_link` each take `mode` as their
last user-data argument and read and write `self._tints[mode][which]` instead of
`self._app_tint` / `self._shell_tint`. `_build_blur_strength_group(self, mode,
description=None)` does the same with `self._strength_scales[mode]`, seeded from
`self._applied.modes[mode]["blur_strength"]`.

Initialise the two dictionaries in `Window.__init__`, above the loop that builds
the pages:

```python
        self._tints = {}
        self._tint_rows = {}
        self._strength_scales = {}
```

Every existing reader of the old single attributes moves to the active mode's
entry. There are four: `_sync_sensitivity`, `_reload`, `_current` and
`_on_tint_preview`. A convenience accessor keeps them readable:

```python
    def _mode_tints(self):
        """The tint pair belonging to the tab that is showing."""
        return self._tints[self._glass_mode()]
```

Solid has no tint group and no strength bar, so `_glass_mode() == "solid"` must
never reach these — `_current` returns solid's fixed values before it asks (see
Step 5), and `_sync_sensitivity` returns early on solid.

- [ ] **Step 4: Write the solid builder**

```python
    def _build_solid_page(self):
        """No controls: this tab is a description of what standing down means.

        It is the tab someone reaches because something is wrong, so it says
        what it takes away and what it leaves in the order those questions get
        asked, and it does not editorialise about performance — the frosted tab
        already does that.
        """
        page = Adw.PreferencesPage()
        page.add(tip_card(
            "<b>The theme stands down.</b> Your desktop goes back to GNOME's "
            "own look, as though this was never installed — for when something "
            "is wrong and you want the desktop back while you work out what.\n\n"
            "Nothing is deleted and nothing is forgotten. Coming back is "
            "picking another tab and pressing Apply."))

        goes = Adw.PreferencesGroup(title="What it takes away")
        for title, subtitle in (
            ("The stylesheets",
             "The aura-glass block comes out of your GTK and shell CSS, and "
             "the files it changed go back to the copies it backed up"),
            ("The shell and GTK themes",
             "Both keys go back to GNOME's defaults, so the shell is the one "
             "GNOME ships"),
            ("The extensions this installed",
             "Switched off, not removed and not reconfigured — every one of "
             "them keeps its own settings and comes back exactly as it was"),
        ):
            goes.add(Adw.ActionRow(title=title, subtitle=subtitle))
        page.add(goes)

        stays = Adw.PreferencesGroup(title="What it leaves")
        for title, subtitle in (
            ("Your icons and pointer",
             "The packs stay installed and selected"),
            ("Your accent colour",
             "A GNOME setting rather than one of this theme's, so it stands"),
            ("Every setting in the other two tabs",
             "Opacity, tint, blur strength and the per-app lists are all "
             "remembered where they are"),
            ("Extensions you installed yourself",
             "Only the ones this project installs are switched off"),
        ):
            stays.add(Adw.ActionRow(title=title, subtitle=subtitle))
        page.add(stays)
        return page
```

- [ ] **Step 5: Teach _current, _reload and _sync_sensitivity about the tabs**

In `_current`, read the controls of whichever tab is showing:

```python
        s.glass_mode = self._glass_mode()
        s.blur = s.glass_mode != "solid"
        if s.glass_mode == "solid":
            # No tint and no strength bar exist in this tab, so they carry the
            # applied values through untouched rather than being read from
            # widgets that are not there.
            s.app_tint = self._applied.app_tint
            s.shell_tint = self._applied.shell_tint
            s.blur_strength = self._applied.blur_strength
        else:
            s.app_tint = self._tints[s.glass_mode]["app"]
            s.shell_tint = self._tints[s.glass_mode]["shell"]
            s.blur_strength = int(round(
                self._strength_scales[s.glass_mode].get_value()))
        if s.glass_mode == "transparent":
            s.scope = "none"
            s.transparency = percent_to_level(
                round(self._t_transparency_scale.get_value()))
            s.popup_blur = self._t_popup_row.get_active()
        elif s.glass_mode == "solid":
            s.scope = "none"
            s.transparency = "0"
            s.popup_blur = False
        else:
            s.scope = self._scope()
            s.transparency = (
                percent_to_level(round(self._transparency_scale.get_value()))
                if self._transparency_on.get_active() else "0")
            s.popup_blur = self._popup_row.get_active()
```

In `_reload`, drop the `self._blur_row.set_active(...)` line and put the tab back to what is on disk, filling whichever scale belongs to it:

```python
        self._mode_stack.set_visible_child_name(self._applied.glass_mode)
        if self._applied.glass_mode == "transparent":
            if self._applied.transparency != "0":
                self._t_transparency_scale.set_value(
                    level_to_percent(self._applied.transparency))
            self._t_popup_row.set_active(self._applied.popup_blur)
        else:
            ...   # the existing frosted lines, unchanged
```

In `_sync_sensitivity`, delete every line that dimmed a row because `blur` was off — those rows are in the frosted tab, which only exists when the mode is frosted. What remains is the pair that still depends on a control in the same tab:

```python
    def _sync_sensitivity(self):
        """Only the rows that depend on another row in the same tab."""
        self._blur_all_row.set_sensitive(self._window_blur_row.get_active())
        live = self._transparency_on.get_active()
        self._transparency_row.set_sensitive(live)
        self._transparency_bar.set_sensitive(live)
        self._app_tint_row.set_sensitive(live)
        self._tint_link_row.set_sensitive(live)
```

In `_on_changed`, drop `"blur"` from both key tests — nothing sends that key any more.

- [ ] **Step 6: Check the window still builds and the flags still compose**

Run: `python3 -c "import sys; sys.path.insert(0, 'gui'); import aura_glass_settings"`
Expected: no output, no traceback.

Run: `python3 tools/check-gui-flags.py && python3 tools/check-gui-radius.py`
Expected: both pass.

- [ ] **Step 7: Look at it**

Run: `python3 gui/aura_glass_settings.py`
Expected: the Glass section opens on the tab matching the installed mode; the three tabs switch; the switcher marks the pending mode and the Apply button lights up when a tab is switched; Revert puts the tab back.

- [ ] **Step 8: Commit**

```bash
git add gui/aura_glass_settings.py
git commit -m "feat(gui): three glass modes as three tabs

A control that does not apply to the mode you are in is now in another
tab rather than dimmed in this one, which is four rows and a
sensitivity pass the page no longer has to spend explaining itself."
```

---

### Task 8: Say so in the README

**Files:**
- Modify: `README.md` (the section describing blur and solid mode)

**Interfaces:**
- Consumes: everything above.
- Produces: nothing.

- [ ] **Step 1: Find what the README says today**

Run: `grep -n "solid\|no-blur\|Solid" README.md`
Expected: the existing passages that describe solid mode as opaque surfaces.

- [ ] **Step 2: Rewrite the passage as three modes**

Describe the three modes in the table shape the spec uses, note that `--glass-mode` is the flag and that each mode keeps its own opacity and tint, and say plainly that solid stands the theme down — stylesheets out, stock shell, this project's extensions switched off with their settings intact, packs and accent kept, and one Apply back.

Keep the existing note that bare `--no-blur` is opaque-but-themed; it is still true and is now the difference between it and solid mode.

- [ ] **Step 3: Check the docs claim nothing untrue**

Run: `bash install.sh --help | grep -A6 glass-mode`
Expected: the help text matches what the README now says.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: describe the three glass modes

Solid is no longer 'opaque surfaces' — it is the theme standing down,
which is a different promise and needs saying in the place people read
before they install."
```

---

## Notes for the executor

- **Run order matters.** Tasks 1 and 2 are the foundation; 3, 4 and 5 are the three halves of solid mode and can be reviewed independently but not reordered before 1; 6 and 7 are the window and depend on 1-5 being in place for the manual checks to mean anything.
- **The live checks in Task 5 Step 6 need a real GNOME session.** If you are working somewhere without one, say so in the task's report rather than marking it done — the dry-run assertions cover the wiring, not the round trip.
- **Do not touch `gui/aura_glass_setup_wizard.py`.** Its Step 2 is still a two-way question; teaching it the three modes is a separate change, and `tools/check-wizard-flags.py` will fail if it is half-done.
