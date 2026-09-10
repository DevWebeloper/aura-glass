# shellcheck shell=bash
# aura-glass — the dconf preset, and the gsettings that go with it.
#
# dconf/core.ini holds the preset so it stays readable in one file. What cannot
# live there is anything whose right value depends on the machine or on a flag,
# because dconf load rewrites the whole section on every run — so a flagless
# re-install would quietly undo a deliberate choice. Those keys are written
# afterwards by the apply_* functions here, several of which remember the answer
# in $CONF_DIR for exactly that reason.
#
# Sourced by install.sh.

liquid_snapshot_read() {
    local value
    value="$(dconf read "$1" 2>/dev/null || true)"
    # dconf read is empty when a key has no user value.  Record that distinct
    # state so restoration resets the key instead of leaving Liquid Glass's
    # false override behind as a fake user choice.
    printf '%s\n' "${value:-__AURA_DCONF_RESET__}"
}

# Liquid Glass owns the visual treatment of shell popups, notifications, the
# dock and OSD.  Keep Aura's panel/application Blur My Shell effects running;
# they are separate actors and disabling either would make this renderer's
# shell-only scope unexpectedly change application windows.
apply_liquid_glass_profile() {
    [ "${LIQUID_GLASS_EFFECTIVE:-0}" = 1 ] || return 0
    local profile="$CONF_DIR/liquid-glass" marker="$CONF_DIR/liquid-glass/profile-snapshot"
    local bms=/org/gnome/shell/extensions/blur-my-shell
    local dock=/org/gnome/shell/extensions/dash-to-dock/blur
    local openbar=/org/gnome/shell/extensions/openbar/apply-menu-notif
    local enabled

    if [ ! -f "$marker" ]; then
        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: snapshot Liquid Glass conflicts and suspend their Aura profile"
        else
            mkdir -p "$profile"
            liquid_snapshot_read "$bms/popup/blur" > "$profile/bms-popup-blur"
            liquid_snapshot_read "$bms/popup/notification" > "$profile/bms-popup-notification"
            liquid_snapshot_read "$dock" > "$profile/dash-to-dock-blur"
            liquid_snapshot_read "$openbar" > "$profile/openbar-apply-menu-notif"
            enabled="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)"
            case "$enabled" in *"'custom-osd@neuromorph'"*) printf '1\n' > "$profile/custom-osd-enabled" ;; *) printf '0\n' > "$profile/custom-osd-enabled" ;; esac
            : > "$marker"
        fi
    fi

    # These are the only upstream keys Aura writes.  Advanced Liquid Glass
    # preferences remain entirely upstream-owned.
    run dconf write /org/gnome/shell/extensions/liquid-glass/enable-dock-glass true
    run dconf write /org/gnome/shell/extensions/liquid-glass/enable-menu-glass true
    run dconf write /org/gnome/shell/extensions/liquid-glass/enable-notification-glass true
    run dconf write /org/gnome/shell/extensions/liquid-glass/enable-quick-settings-glass true
    run dconf write /org/gnome/shell/extensions/liquid-glass/enable-osd-glass true
    run dconf write /org/gnome/shell/extensions/liquid-glass/enable-application-glass false
    run dconf write "$bms/popup/blur" false
    run dconf write "$bms/popup/notification" false
    run dconf write "$dock" false
    run dconf write "$openbar" false
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: disable Custom OSD if the saved Liquid Glass profile says it was enabled"
    elif [ "$(cat "$profile/custom-osd-enabled" 2>/dev/null || true)" = 1 ]; then
        gnome-extensions disable custom-osd@neuromorph 2>/dev/null || true
        dequeue_extension custom-osd@neuromorph || true
    fi
    queue_liquid_glass
    ok "Liquid Glass conflict profile staged — shell renderer activates after logout"
}

restore_liquid_glass_profile() {
    local profile="$CONF_DIR/liquid-glass" marker="$CONF_DIR/liquid-glass/profile-snapshot"
    local bms=/org/gnome/shell/extensions/blur-my-shell value
    [ -f "$marker" ] || return 0

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: restore the saved Liquid Glass conflict profile"
        return 0
    fi
    gnome-extensions disable "$LIQUID_GLASS_UUID" 2>/dev/null || true
    dequeue_extension "$LIQUID_GLASS_UUID" || true
    for value in \
        "$bms/popup/blur:bms-popup-blur" \
        "$bms/popup/notification:bms-popup-notification" \
        "/org/gnome/shell/extensions/dash-to-dock/blur:dash-to-dock-blur" \
        "/org/gnome/shell/extensions/openbar/apply-menu-notif:openbar-apply-menu-notif"; do
        local key="${value%%:*}" file="${value#*:}" saved
        saved="$(cat "$profile/$file" 2>/dev/null || true)"
        case "$saved" in
            __AURA_DCONF_RESET__) run dconf reset "$key" ;;
            '') warn "Liquid Glass snapshot for $key is empty — left for inspection" ;;
            *) run dconf write "$key" "$saved" ;;
        esac
    done
    if [ "$(cat "$profile/custom-osd-enabled" 2>/dev/null || true)" = 1 ]; then
        if ! gnome-extensions enable custom-osd@neuromorph 2>/dev/null; then
            enqueue_extension custom-osd@neuromorph || true
        fi
    fi
    rm -f "$marker" "$profile/bms-popup-blur" "$profile/bms-popup-notification" \
          "$profile/dash-to-dock-blur" "$profile/openbar-apply-menu-notif" \
          "$profile/custom-osd-enabled"
    rmdir "$profile" 2>/dev/null || true
    ok "Liquid Glass conflict profile restored"
}

load_dconf() {
    step "Loading the dconf preset"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: dconf load /org/gnome/shell/extensions/ < dconf/core.ini"
    else
        dconf load /org/gnome/shell/extensions/ < "$REPO_ROOT/dconf/core.ini" \
            || die "dconf load failed"
    fi
    ok "core look loaded"

    # Applied over the top rather than as a separate preset, so solid mode is
    # one overlay to read and to review rather than a second full copy of every
    # key that would then have to be kept in step with core.ini.
    if [ "${WANT_BLUR:-1}" != 1 ]; then
        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: dconf load /org/gnome/shell/extensions/ < dconf/solid.ini"
        else
            dconf load /org/gnome/shell/extensions/ < "$REPO_ROOT/dconf/solid.ini" \
                || die "dconf load of the solid preset failed"
        fi
        ok "solid mode loaded — no blur, opaque surfaces"
    fi

    if [ "${WANT_EXTRAS:-0}" = 1 ]; then
        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: dconf load /org/gnome/shell/extensions/ < dconf/extras.ini"
        else
            dconf load /org/gnome/shell/extensions/ < "$REPO_ROOT/dconf/extras.ini" || true
        fi
        ok "optional extension settings loaded"
    fi

    # Open Bar regenerates its stylesheet when this key changes, so toggling it
    # is what makes the preset take effect without a restart.
    run dconf write /org/gnome/shell/extensions/openbar/trigger-reload false
    run dconf write /org/gnome/shell/extensions/openbar/trigger-reload true

    apply_grain
    apply_blur_strength
    apply_popup_brightness
    apply_popup_blur
    apply_notification_blur
    apply_app_blur
    apply_app_opacity
    apply_radius_dconf
    sync_osd_profile
}

# The seven of the eight corner radii that Blur My Shell rounds its blur
# actors at — TOKEN_RADIUS_BUTTON has no blur actor behind it and is skipped
# here, only ever painted by apply_radius_css. dconf/core.ini
# ships them at the `default` row of radius_preset_values in tokens/tokens.sh,
# and dconf load has just written that row — so like every other apply_* here,
# this runs afterwards to put a flag's or a remembered choice's value back over
# the preset's.
#
# The project rule these exist to keep: a painted radius must equal the blur
# radius behind it. apply_radius_css moved the painted half in $CONF_DIR; this is
# the blur half, and the two read the same TOKEN_RADIUS_* variables from the same
# call to radius_preset_values so they cannot disagree.
#
# Two of these have no painted counterpart at all. `corner-radius` under popup is
# the generic fallback for surfaces the specific keys do not claim, and
# `osd-corner-radius` belongs to a pill Custom OSD draws rather than to any
# stylesheet — see TOKEN_RADIUS_OSD for why that one does not simply scale with
# the rest.
apply_radius_dconf() {
    local base=/org/gnome/shell/extensions/blur-my-shell

    # Nothing here is Blur My Shell's to round when Blur My Shell is not
    # installed. The painted radii still moved: apply_radius_css runs
    # regardless, because in solid mode the corner is all there is.
    if [ "${WANT_BLUR:-1}" != 1 ]; then
        skip "blur corner radii left alone (--no-blur — no blur to round)"
        return 0
    fi

    run dconf write "$base/applications/corner-radius" "$TOKEN_RADIUS_WINDOW"
    run dconf write "$base/popup/menu-corner-radius" "$TOKEN_RADIUS_MENU"
    run dconf write "$base/popup/quick-settings-corner-radius" "$TOKEN_RADIUS_QUICK_SETTINGS"
    run dconf write "$base/popup/notification-corner-radius" "$TOKEN_RADIUS_NOTIFICATION"
    run dconf write "$base/popup/dialog-corner-radius" "$TOKEN_RADIUS_DIALOG"
    run dconf write "$base/popup/corner-radius" "$TOKEN_RADIUS_POPUP"
    run dconf write "$base/popup/osd-corner-radius" "$TOKEN_RADIUS_OSD"
    apply_pipeline_radius
    ok "blur corner radii follow the '${RADIUS_PRESET:-default}' preset"
}

# The window corner again, in the other place Blur My Shell keeps it.
#
# [applications] names a pipeline, and that pipeline carries a `corner` effect
# with a radius of its own — so the blur behind an app window is rounded twice
# over, by corner-radius above and by the effect here. Only the first moved with
# a preset, which left a `soft` desktop rounding one at 16 and the other at 30:
# the two-stacked-surfaces fault tokens/tokens.sh exists to prevent, inside a
# single component.
#
# Every pipeline lives in one GVariant blob under `pipelines`, so this is a
# read-modify-write of one number inside it rather than a key to set. The
# pattern comes from tools/token_manifest.py — the same list
# tools/check-tokens.sh asserts dconf/core.ini against — so the shipped value
# and the value moved here cannot drift apart. It matches by pipeline name: the
# id beside it is generated per machine and is not a thing to hard-code.
#
# The other three corner effects are left alone deliberately. `panel` and `dock`
# round surfaces that are not among the eight a preset covers, and
# `default rounded` is named by no component at all.
#
# Runs after apply_blur_strength, which rewrites the same key. That one only
# ever touches `unscaled_radius`, so the two do not fight over a value — but it
# also resets the whole blob from the shipped literal in bin/aura-glass-preview,
# so the order is fixed rather than incidental.
apply_pipeline_radius() {
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: round the windows blur pipeline at $TOKEN_RADIUS_WINDOW"
        return 0
    fi
    python3 - "$REPO_ROOT" "$TOKEN_RADIUS_WINDOW" <<'PIPELINE_PY' || { warn "could not round the windows blur pipeline"; return 0; }
import os
import re
import subprocess
import sys

root, want = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(root, "tools"))
from token_manifest import raw_entries

KEY = "/org/gnome/shell/extensions/blur-my-shell/pipelines"
cur = subprocess.run(["dconf", "read", KEY],
                     capture_output=True, text=True).stdout.strip()
if not cur:
    sys.exit(0)

new = cur
for _token, _kind, _rel, pattern in raw_entries({"TOKEN_RADIUS_WINDOW"}):
    matches = list(re.finditer(pattern, new, re.M))
    if not matches:
        # Blur My Shell renamed the pipeline, or this machine never had it.
        # Said out loud rather than passed over: the painted corner has already
        # moved by the time this runs, so a silent miss here is exactly the
        # mismatch this function exists to close.
        print("no `windows` pipeline in %s — its blur corner stays where it is"
              % KEY, file=sys.stderr)
        continue
    # From the end, so an earlier replacement cannot move a later span.
    for m in reversed(matches):
        for i in range(1, (m.lastindex or 0) + 1):
            start, end = m.span(i)
            new = new[:start] + want + new[end:]

if new != cur:
    subprocess.run(["dconf", "write", KEY, new], check=True)
PIPELINE_PY
}

# [applications] opacity controls the compositor-level window actor opacity for
# windows on top of the blur effect. For GTK4 apps, the stylesheet handles inner
# translucency; for Electron/IDE/browser apps, this actor opacity allows the blur
# to show through the window content.
apply_app_opacity() {
    local base=/org/gnome/shell/extensions/blur-my-shell
    local opacity="${APP_OPACITY:-255}" memo="$CONF_DIR/app-opacity"

    if [ "${WANT_BLUR:-1}" != 1 ] || [ "${WANT_WINDOW_BLUR:-1}" != 1 ]; then
        run dconf write "$base/applications/opacity" 255
        return 0
    fi

    if [ -z "${APP_OPACITY_EXPLICIT:-}" ] && [ -r "$memo" ]; then
        opacity="$(cat "$memo" 2>/dev/null || true)"
        opacity="${opacity:-255}"
    fi

    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$opacity" > "$memo"
    fi

    run dconf write "$base/applications/opacity" "$opacity"
    if [ "$opacity" != 255 ]; then
        local pct
        pct="$(python3 -c "print(round($opacity / 255.0 * 100))" 2>/dev/null || echo "$opacity")"
        ok "window actor opacity set to $opacity (${pct}% opacity, translucent blur for apps)"
    else
        ok "window actor opacity set to 255 (opaque actor)"
    fi
}

# The popup keys themselves ship in dconf/core.ini so the whole preset stays
# readable in one file. Two things cannot live there:
#
# The on/off choice, because dconf load rewrites the section on every run — a
# flagless re-install would quietly turn popup blur back on over a deliberate
# --no-popup-blur. Same reason --grain and --icons are remembered.
#
# static-blur, because the right value depends on the machine. Rounded corners
# on a dynamic blur need the gnome-rounded-blur library; a static blur rounds
# itself. So when the library is missing this falls back to static, and the
# corners stay round instead of going square. It self-heals: install the
# library, re-run, and it flips back to dynamic.
# Which windows the applications component treats, as wm_class patterns.
#
# Blur My Shell compiles these and matches a window's wm_class against them
# (components/applications.js, matchesAnyPattern), so `*chrome*` covers every
# spelling Chrome uses. Which list is consulted depends on enable-all: with it
# off only the allow list is blurred, with it on everything except the block
# list is. That is the same choice --app-blur-scope makes, which is why gtk mode
# reads one list and all mode reads the other.
#
# The same test decides the actor opacity in apply_app_opacity — Blur My Shell
# applies both to whatever passes it — so these lists govern which windows go
# translucent as much as which ones get a blur. There is no way to separate the
# two, and no per-app control over the stylesheet's own alpha at all: GTK CSS
# has no selector for "this application".
#
# Shipped as defaults rather than written into dconf/core.ini, because a user's
# edited list has to survive the next install and dconf load rewrites whole
# sections. $CONF_DIR/app-blur-allow and app-blur-block hold the edited copies,
# one pattern per line, and are what the settings window writes.
APP_BLUR_ALLOW_DEFAULT=(
    org.gnome.Nautilus org.gnome.Settings gnome-control-center
    org.gnome.TextEditor org.gnome.SystemMonitor org.gnome.Calculator
    org.gnome.Extensions org.gnome.Tweaks org.gnome.Ptyxis org.gnome.Console
    gnome-terminal org.gnome.DiskUtility org.gnome.Logs org.gnome.Calendar
    org.gnome.Weather org.gnome.Clocks org.gnome.Characters
    org.gnome.FontViewer org.gnome.Loupe org.gnome.Snapshot
    io.bassi.Amberol com.raggesilver.BlackBox
)

# Only consulted in `all` mode. The wildcards are the expensive-to-blur or
# self-compositing apps: browsers and Electron redraw constantly, so a blur
# behind them is rebuilt constantly, and Plank and ding draw their own desktop
# surfaces that a blur actor sits wrongly against.
APP_BLUR_BLOCK_DEFAULT=(
    '*chrome*' '*google-chrome*' '*chromium*' '*discord*' '*vesktop*'
    '*brave*' '*firefox*' '*code*' '*antigravity*' '*steam*' '*spotify*'
    '*electron*' Plank com.desktop.ding Conky
)

# The settings window's own wm_class, which is blurred whenever anything is.
#
# Written out here rather than read from $GUI_APP_ID in lib/steps-gui.sh: that
# file is sourced after this one and the two are separate concerns, so the string
# is duplicated and tools/check-app-blur-lists.sh asserts the two copies agree.
# gui/aura_glass_settings.py holds a third, for the same reason and with the same
# check behind it.
APP_BLUR_SELF="io.github.DevWebeloper.AuraGlassSettings"

# Does one pattern cover the settings window?
#
# wildcardToRegex in the extension's components/applications.js anchors a pattern
# at both ends, turns * into .* and ? into ., and compiles case-insensitively —
# which is what a bash glob under nocasematch does. The one difference is [abc]:
# the extension escapes the brackets and matches them literally. No wm_class has
# brackets in it, and this one certainly does not.
app_blur_covers_self() {
    local pattern="$1" matched=0 restore
    restore="$(shopt -p nocasematch)"
    shopt -s nocasematch
    case "$APP_BLUR_SELF" in
        $pattern) matched=1 ;;
    esac
    eval "$restore"
    [ "$matched" = 1 ]
}

# Lines on stdin -> the same lines with the settings window on them.
#
# The window is the one place the glass is explained, so it is the one window
# that must never be the exception to it: unblurred, it shows an opaque grey
# panel while describing the blur, and the per-app lists it opens are drawn in
# a window that proves the setting does not work. Nothing else here is pinned,
# and this is not a general mechanism — it is one class, named once.
#
# Pinned rather than added to APP_BLUR_ALLOW_DEFAULT, because a default is only
# consulted when there is no memo, and every machine that has run an earlier
# release has one. Skipped when a pattern already covers it, so a user who wrote
# their own wildcard for it does not get a duplicate underneath.
app_blur_pin_allow() {
    local lines pattern
    lines="$(cat)"
    while IFS= read -r pattern; do
        [ -n "${pattern// /}" ] || continue
        if app_blur_covers_self "$pattern"; then
            printf '%s\n' "$lines"
            return 0
        fi
    done <<< "$lines"
    printf '%s\n%s\n' "$APP_BLUR_SELF" "$lines"
}

# Lines on stdin -> the same lines, minus anything that would block the window.
#
# The other half of the pin. In `all` mode the allow list is not read at all, so
# keeping the window blurred there means dropping whatever excludes it — and the
# shipped block list does not name it, but `*aura*` from a user who wanted their
# own theme's windows left alone would.
app_blur_pin_block() {
    local pattern
    while IFS= read -r pattern; do
        [ -n "${pattern// /}" ] || continue
        app_blur_covers_self "$pattern" && continue
        printf '%s\n' "$pattern"
    done
}

# The list to use, one pattern per line: an explicit flag wins, else the user's
# memo, else the shipped default. Same precedence as every other remembered
# choice here, so a flag is a one-run override that then becomes the memory.
app_blur_lines() {
    local given="$1" override="$2" memo="$3"; shift 3
    # `given` rather than a non-empty override, because clearing a list is a
    # thing a user does: --app-blur-allow "" and the settings window removing the
    # last row both mean an empty list, and testing the value alone read that as
    # "no flag" and quietly reinstated the previous one.
    if [ -n "$given" ]; then
        printf '%s\n' "$override" | tr ',' '\n'
    elif [ -r "$memo" ]; then
        cat "$memo"
    else
        printf '%s\n' "$@"
    fi
}

# Lines on stdin -> a GVariant array literal for dconf write.
#
# By the time the settings window has been near it a pattern is arbitrary text,
# and it is about to be spliced into a literal that dconf parses. Two characters
# matter: an apostrophe ends the string early, which dconf rejects outright, and
# a backslash escapes whatever follows it, which dconf accepts as a different
# string than the one meant — 'weird\name' arrives carrying a newline. The first
# is a failed install with a message about GVariant syntax; the second is an
# entry that silently never matches.
#
# Escaped explicitly rather than by leaning on python's repr. repr does in fact
# produce valid GVariant for every pattern anyone would type — it quotes and
# escapes compatibly — but it is a function whose contract is "readable python",
# and relying on the two staying in agreement is a bet with no upside.
# tools/check-app-blur-lists.sh parses the result back with GLib's own parser.
app_blur_literal() {
    python3 -c '
import sys


def gvariant(s):
    return "\x27" + s.replace("\\", "\\\\").replace("\x27", "\\\x27") + "\x27"


lines = [l.strip() for l in sys.stdin]
print("[%s]" % ", ".join(gvariant(l) for l in lines if l))'
}

# The window blur is its own opt-in, not a consequence of anything else.
#
# It is the most expensive thing this preset can switch on — a blur behind every
# window, rebuilt as the window moves, which measured the overview at p90 99%
# GPU against 32% without it on an RX 7600 — and it only becomes visible at all
# once --app-transparency has made the surfaces translucent. Paired with
# --app-transparency it is a real effect for a real cost; on its own it is a
# cost for almost nothing, since the window sits at 94% opacity.
#
# The cheaper way to the same readable, see-through window is the tint: darken
# the ground under the alpha instead of blurring what is behind it. That costs
# no GPU at all. See TOKEN_APP_TINT in tokens/tokens.sh.
#
# Deliberately not remembered, like the popup-blur memo it sits beside: a flag
# that persists past the run that set it is how --no-blur left menus unblurred
# after a return to glass.
apply_app_blur() {
    local base=/org/gnome/shell/extensions/blur-my-shell
    local want="${WANT_WINDOW_BLUR:-1}" memo="$CONF_DIR/window-blur"
    local scope="${APP_BLUR_SCOPE:-gtk}" scope_memo="$CONF_DIR/app-blur-scope"
    local allow_memo="$CONF_DIR/app-blur-allow" block_memo="$CONF_DIR/app-blur-block"

    if [ "${WANT_BLUR:-1}" != 1 ]; then
        run dconf write "$base/applications/blur" false
        skip "window blur off with the rest of it (--no-blur)"
        return 0
    fi

    if [ -z "${WINDOW_BLUR_EXPLICIT:-}" ] && [ -r "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
        want="${want:-1}"
    fi

    if [ -z "${APP_BLUR_SCOPE_EXPLICIT:-}" ] && [ -r "$scope_memo" ]; then
        scope="$(cat "$scope_memo" 2>/dev/null || true)"
        scope="${scope:-gtk}"
    fi

    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
        printf '%s\n' "$scope" > "$scope_memo"
    fi

    if [ "$want" != 1 ]; then
        run dconf write "$base/applications/blur" false
        skip "window blur off — pass --window-blur if you want it"
        return 0
    fi

    # Both lists are written in both modes. Only one is consulted — enable-all
    # decides which — but leaving the other at whatever a previous run or a
    # previous version put there means switching modes later picks up a stale
    # list, which reads as the mode switch having done something else as well.
    local allow_lines block_lines allow block
    allow_lines="$(app_blur_lines "${APP_BLUR_ALLOW_EXPLICIT:-}" "${APP_BLUR_ALLOW:-}" "$allow_memo" "${APP_BLUR_ALLOW_DEFAULT[@]}")"
    block_lines="$(app_blur_lines "${APP_BLUR_BLOCK_EXPLICIT:-}" "${APP_BLUR_BLOCK:-}" "$block_memo" "${APP_BLUR_BLOCK_DEFAULT[@]}")"

    # After the flag/memo/default choice and before anything is written, so the
    # memo the settings window reads back is the list that reached dconf. An
    # empty allow list is still emptied by --app-blur-allow "" — it comes out of
    # this holding the settings window and nothing else, which is a list with
    # nothing of the user's on it rather than a list that ignored them.
    allow_lines="$(printf '%s\n' "$allow_lines" | app_blur_pin_allow)"
    block_lines="$(printf '%s\n' "$block_lines" | app_blur_pin_block)"

    allow="$(printf '%s\n' "$allow_lines" | app_blur_literal)"
    block="$(printf '%s\n' "$block_lines" | app_blur_literal)"

    # Written back every real run, not only when a flag supplied them, so the
    # memo is always what is installed. The settings window reads these files to
    # show the lists, and a missing memo would have it show an empty list for a
    # dconf key that is not empty at all. A preview is not a real run and writes
    # neither — see remembering() in lib/common.sh.
    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$allow_lines" > "$allow_memo"
        printf '%s\n' "$block_lines" > "$block_memo"
    fi

    run dconf write "$base/applications/whitelist" "$allow"
    run dconf write "$base/applications/blacklist" "$block"

    if [ "$scope" = "all" ]; then
        run dconf write "$base/applications/enable-all" true
        run dconf write "$base/applications/blur" true
        ok "window blur on for ALL applications except the block list (enable-all: true)"
    else
        run dconf write "$base/applications/enable-all" false
        run dconf write "$base/applications/blur" true
        ok "window blur on behind the allowed applications only (Nautilus, Settings, Terminal, etc.)"
    fi
    if [ -z "${APP_TRANSPARENCY:-}" ] || [ "${APP_TRANSPARENCY:-0}" = 0 ]; then
        warn "without --app-transparency the windows stay 94% opaque, so very"
        warn "little of that blur will be visible for what it costs"
    fi
}

apply_popup_blur() {
    local base=/org/gnome/shell/extensions/blur-my-shell
    local want="${WANT_POPUP_BLUR:-1}" memo="$CONF_DIR/popup-blur"

    # --no-blur turns this off as a consequence of turning everything off, not
    # because the user asked for flat popups. Remembering it would outlive the
    # mode: installing --no-blur and later going back to glass came up with
    # blurred windows and unblurred menus, because the memo said 0 and nothing
    # on the second run contradicted it. So solid mode neither reads nor writes
    # the memo — it leaves whatever the last real choice was intact, ready for
    # the next glass install.
    if [ "${WANT_BLUR:-1}" != 1 ]; then
        run dconf write "$base/popup/blur" false
        skip "popup blur off with the rest of it (--no-blur)"
        return 0
    fi

    if [ -z "${POPUP_BLUR_EXPLICIT:-}" ] && [ -r "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
        want="${want:-1}"
    fi

    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi

    if [ "$want" != 1 ]; then
        run dconf write "$base/popup/blur" false
        skip "popup blur off — menus keep the flat translucent look"
        return 0
    fi

    # Written by Blur My Shell at every enable, so on a first install — before
    # the shell has ever loaded this build — it is absent and we start static.
    # The next run picks the library up.
    local found
    found="$(dconf read "$base/rounded-blur-found" 2>/dev/null || true)"

    run dconf write "$base/popup/blur" true
    if [ "$found" = true ]; then
        run dconf write "$base/popup/static-blur" false
        ok "popup blur on, dynamic — it tracks whatever is behind the popup"
    else
        run dconf write "$base/popup/static-blur" true
        ok "popup blur on, static — rounded, but sampling the wallpaper"
        info "install gnome-rounded-blur (--rounded-blur) for blur that tracks windows"
    fi
}

# Notification banners and the history cards in the date menu, gated by the
# patched popup component's own `notification` key — independent of
# popup/blur, the same way this project's --popup-blur and
# --notification-blur flags are independent of each other. static-blur and
# rounded-blur-found stay apply_popup_blur's business: they are settings on
# the popup component as a whole, not on this surface alone, and the popup
# blur switch already decides them whenever it runs.
apply_notification_blur() {
    local base=/org/gnome/shell/extensions/blur-my-shell
    local want="${WANT_NOTIFICATION_BLUR:-1}" memo="$CONF_DIR/notification-blur"

    # Same reasoning as apply_popup_blur: --no-blur turns this off as a
    # consequence of turning everything off, not a real choice to remember,
    # so solid mode neither reads nor writes the memo.
    if [ "${WANT_BLUR:-1}" != 1 ]; then
        run dconf write "$base/popup/notification" false
        skip "notification blur off with the rest of it (--no-blur)"
        return 0
    fi

    if [ -z "${NOTIFICATION_BLUR_EXPLICIT:-}" ] && [ -r "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
        want="${want:-1}"
    fi

    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi

    if [ "$want" != 1 ]; then
        run dconf write "$base/popup/notification" false
        skip "notification blur off — banners and history cards keep the flat look"
        return 0
    fi

    run dconf write "$base/popup/notification" true
    ok "notification blur on — banners and history cards blur independently"
    clear_openbar_notification_override
}

# Open Bar generates a stylesheet of its own into
# $XDG_RUNTIME_DIR/io.github.neuromorph.openbar/stylesheet.css, and its "apply
# to menus and notifications" switch puts a
# `.notification-banner { background-color: ... !important }` into it. St loads
# every extension stylesheet after the user theme and settles a tie by load
# order rather than by weight, so that one rule outranks this project's banner
# fill however it is written — !important does not reach it, and neither does
# raising the selector to `.notification-banner.message`. The banner then sits
# at Open Bar's own menu opacity, 0.92 out of the box, and the blur behind it
# survives only in the margin ring outside the fill: a banner that reads as a
# flat slab while the history cards, which match .message and never
# .notification-banner, blur correctly and make it look like a bug in here.
#
# The switch gates exactly one block of Open Bar's sheet — the banner, the
# notification buttons and the summary counter — so clearing it costs that
# override and nothing else of Open Bar's look. It only runs on the path that
# has just turned notification blur on; turning blur off again leaves the
# switch alone rather than restoring an override the user may not want back.
clear_openbar_notification_override() {
    local u=openbar@neuromorph
    local key=/org/gnome/shell/extensions/openbar/apply-menu-notif

    [ -d "$EXT_DIR/$u" ] || return 0
    [ "$(dconf read "$key" 2>/dev/null || true)" = true ] || return 0

    run dconf write "$key" false

    # Open Bar rewrites that sheet when it starts rather than on every key it
    # owns, so the file on disk keeps the banner rule until the extension is
    # cycled — and cycling is only meaningful while it is actually running.
    if gnome-extensions info "$u" 2>/dev/null | grep -q 'State: ACTIVE'; then
        run gnome-extensions disable "$u" 2>/dev/null || true
        run gnome-extensions enable "$u" 2>/dev/null || true
    fi

    ok "Open Bar's notification styling switched off — its banner fill outranked the blur"
}

# Custom OSD keeps a set of named profiles beside the live settings, and its
# preferences window overwrites the live settings with the active profile the
# moment one is picked from the list. The preset above only writes the live
# settings, so without this the popup would quietly go back to stock the first
# time anyone opened that page. Copying the loaded values into the Default
# profile makes the preset what "Default" actually means.
sync_osd_profile() {
    [ "${WANT_OSD:-1}" = 1 ] || return 0
    local schemas="$EXT_DIR/custom-osd@neuromorph/schemas"
    [ -d "$schemas" ] || return 0

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: save the OSD preset into Custom OSD's Default profile"
        return 0
    fi

    python3 - "$schemas" <<'PY' || { warn "could not sync the OSD profile"; return 0; }
import sys
import gi
from gi.repository import Gio, GLib

source = Gio.SettingsSchemaSource.new_from_directory(
    sys.argv[1], Gio.SettingsSchemaSource.get_default(), False)
schema = source.lookup("org.gnome.shell.extensions.custom-osd", False)
if schema is None:
    sys.exit(1)
settings = Gio.Settings.new_full(schema, None, None)

# The same exclusions the extension's own "save profile" uses: these are
# either global or set per popup type rather than per profile.
skip = {"default-font", "profiles", "active-profile",
        "icon", "label", "level", "numeric", "showosd", "clock-osd"}
profile = {k: settings.get_value(k) for k in schema.list_keys() if k not in skip}

existing = settings.get_value("profiles")
merged = {}
for i in range(existing.n_children()):
    entry = existing.get_child_value(i)
    merged[entry.get_child_value(0).get_string()] = entry.get_child_value(1).get_variant()
merged["Default"] = GLib.Variant("a{sv}", profile)

settings.set_value("profiles", GLib.Variant("a{sv}", merged))
settings.set_string("active-profile", "Default")
Gio.Settings.sync()
PY
    ok "OSD preset saved as Custom OSD's Default profile"
}

# Blur My Shell's noise effect lays film grain over every blurred surface. It
# is generated per physical pixel and its strength is not scaled by anything,
# so how it reads depends on the panel and the GPU: the value that gives a
# frosted texture on one machine can look like television static on another.
#
# The preset ships the tuned strength. This makes it adjustable without hand
# editing a nested dconf blob, and — because dconf load rewrites the whole
# pipelines key — remembers the choice so the next install does not silently
# put the grain back.
apply_grain() {
    local want="${GRAIN:-}" memo="$CONF_DIR/grain"
    if [ -z "$want" ] && [ -f "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ -n "$want" ] || return 0

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: set blur grain to $want"
        return 0
    fi

    python3 - "$want" <<'PY' || { warn "could not set grain"; return 0; }
import re, subprocess, sys
want = float(sys.argv[1])
KEY = "/org/gnome/shell/extensions/blur-my-shell/pipelines"
cur = subprocess.run(["dconf", "read", KEY], capture_output=True, text=True).stdout.strip()
if not cur:
    sys.exit(0)
new = re.sub(r"('noise': <)[0-9.]+(>)", lambda m: m.group(1) + repr(want) + m.group(2), cur)
if new != cur:
    subprocess.run(["dconf", "write", KEY, new], check=True)
PY
    run mkdir -p "$CONF_DIR"
    printf '%s\n' "$want" > "$memo"
    ok "blur grain set to $want (remembered for future installs)"
}

# How far the blur reaches, as a percentage of the tuned values.
#
# One number for every blurred surface rather than one per surface. The six
# sigmas in tokens/tokens.sh are not a ladder anybody should have to climb one
# rung at a time — they are already in proportion to each other, chosen against
# what each surface sits in front of, and what people actually want is the
# whole set softer or crisper. Scaling keeps those proportions: the panel stays
# heavier than the dock at every setting.
#
# Both places a blur radius lives are scaled, because Blur My Shell has two.
# The per-component `sigma` keys are what the older releases read. The
# `pipelines` blob is what the current ones read, and it carries the same
# number again as `unscaled_radius` inside each effect. A run that moved one
# and not the other would soften the desktop on one machine and do nothing on
# the next.
#
# Sigmas are written from the tokens rather than read back and multiplied, so
# the value cannot compound over repeated installs. The blob has to be read —
# there is no token for its seven copies — but dconf load has just rewritten it
# from dconf/core.ini a few lines above, which is the same assumption apply_grain
# already makes.
#
# Remembered, like the grain beside it: dconf load puts the shipped sigmas back
# on every run, so an unremembered choice would last until the next install.
# How bright the blur behind menus, Quick Settings and notification banners
# comes out, as a percentage of the backdrop it is blurring. 100% is the
# backdrop's own brightness; under that the blur darkens what is behind it, over
# it the blur lifts it.
#
# One number for every popup surface, and it has to be, because Blur My Shell
# gives the whole popup component one pipeline — settings.popup.PIPELINE in
# components/popup/static_actor.js is read once and handed to every surface the
# component makes. A banner cannot be brightened without the date menu and the
# quick-toggle menus coming with it, and a control that implied otherwise would
# be lying about what it moves.
#
# Both places the number lives are written, for the same reason
# apply_blur_strength writes two: the per-component `brightness` key is what the
# older releases read, and the `pipelines` blob is what the current ones read.
# The pipeline is found by the name the popup component actually points at
# rather than by a hard-coded id, so renaming or repointing it in dconf/core.ini
# does not silently turn this into a no-op.
#
# Runs after apply_blur_strength, which rewrites the same blob. That one only
# touches `unscaled_radius` and this one only touches `brightness`, so the order
# between them is not load-bearing — but keeping them adjacent is, because
# anything that resets the blob wholesale has to come before both.
#
# Remembered, like the strength above it: dconf load puts the shipped brightness
# back on every run.
POPUP_BRIGHTNESS_MIN=50
POPUP_BRIGHTNESS_MAX=150

apply_popup_brightness() {
    local want="${POPUP_BRIGHTNESS:-}" memo="$CONF_DIR/popup-brightness"
    if [ -z "$want" ] && [ -f "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ -n "$want" ] || return 0

    case "$want" in
        ''|*[!0-9]*) warn "--popup-brightness wants a whole percentage, got '$want'"
                     return 0 ;;
    esac
    if [ "$want" -lt "$POPUP_BRIGHTNESS_MIN" ] || [ "$want" -gt "$POPUP_BRIGHTNESS_MAX" ]; then
        warn "--popup-brightness $want is outside ${POPUP_BRIGHTNESS_MIN}-${POPUP_BRIGHTNESS_MAX} — leaving the popup blur alone"
        return 0
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: light the popup blur at ${want}%"
        return 0
    fi

    local base=/org/gnome/shell/extensions/blur-my-shell
    run dconf write "$base/popup/brightness" \
        "$(awk -v p="$want" 'BEGIN { printf "%.2f", p / 100 }')"

    python3 "$REPO_ROOT/tools/apply-popup-brightness.py" "$want" \
        || { warn "could not light the popup blur"; return 0; }

    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi
    ok "popup blur lit at ${want}% (remembered for later runs)"
}

BLUR_STRENGTH_MIN=25
BLUR_STRENGTH_MAX=200

apply_blur_strength() {
    local want="${BLUR_STRENGTH:-}" memo="$CONF_DIR/blur-strength"
    if [ -z "$want" ] && [ -f "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ -n "$want" ] || return 0

    case "$want" in
        ''|*[!0-9]*) warn "--blur-strength wants a whole percentage, got '$want'"
                     return 0 ;;
    esac
    if [ "$want" -lt "$BLUR_STRENGTH_MIN" ] || [ "$want" -gt "$BLUR_STRENGTH_MAX" ]; then
        warn "--blur-strength $want is outside ${BLUR_STRENGTH_MIN}-${BLUR_STRENGTH_MAX} — leaving the blur alone"
        return 0
    fi

    # Nothing to do at the tuned values, and saying so is better than writing
    # six keys back to what dconf load just wrote.
    if [ "$want" = 100 ]; then
        if remembering; then
            mkdir -p "$CONF_DIR"
            printf '%s\n' "$want" > "$memo"
        fi
        ok "blur strength at 100% — the tuned values"
        return 0
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: scale every blur radius to ${want}%"
        return 0
    fi

    local base=/org/gnome/shell/extensions/blur-my-shell
    local pair name token scaled
    for pair in "panel:$TOKEN_SIGMA_PANEL" "appfolder:$TOKEN_SIGMA_APPFOLDER" \
                "popup:$TOKEN_SIGMA_POPUP" "window-list:$TOKEN_SIGMA_WINDOW_LIST" \
                "applications:$TOKEN_SIGMA_APPLICATIONS" \
                "dash-to-dock:$TOKEN_SIGMA_DASH_TO_DOCK"; do
        name="${pair%%:*}"; token="${pair##*:}"
        # Rounded, floored at 1. A sigma of 0 is not a fainter blur, it is the
        # effect switched off, and the switches on the Glass page are where
        # that answer lives.
        scaled=$(( (token * want + 50) / 100 ))
        [ "$scaled" -lt 1 ] && scaled=1
        run dconf write "$base/$name/sigma" "$scaled"
    done

    python3 - "$want" <<'PY' || { warn "could not scale the blur pipelines"; return 0; }
import re
import subprocess
import sys

want = int(sys.argv[1]) / 100.0
KEY = "/org/gnome/shell/extensions/blur-my-shell/pipelines"
cur = subprocess.run(["dconf", "read", KEY],
                     capture_output=True, text=True).stdout.strip()
if not cur:
    sys.exit(0)


def scale(match):
    # Floored at 1 for the same reason the sigmas above are: 0 is off, and off
    # is a different question from faint.
    return "%s%s%s" % (match.group(1),
                       repr(max(1.0, round(float(match.group(2)) * want, 1))),
                       match.group(3))


new = re.sub(r"('unscaled_radius': <)([0-9.]+)(>)", scale, cur)
if new != cur:
    subprocess.run(["dconf", "write", KEY, new], check=True)
PY

    mkdir -p "$CONF_DIR"
    printf '%s\n' "$want" > "$memo"
    ok "blur strength at ${want}% of the tuned radii (remembered for later runs)"
}

# Which of the titlebar buttons a window gets. Two answers rather than the free
# string the key takes: close alone, or all three. The rest of what
# button-layout can express — reordering, moving them to the left, the spacer —
# is not a thing this theme has an opinion about, and a text field that let
# someone type a layout Mutter silently ignores would be worse than no control.
#
# Does nothing at all unless asked, like apply_grain and unlike the theme keys
# in apply_gsettings. This one is shared with GNOME Tweaks and with anyone who
# set it by hand years ago, so a flagless install has no business asserting a
# value over theirs.
apply_window_buttons() {
    local want="${WINDOW_BUTTONS:-}" memo="$CONF_DIR/window-buttons" layout
    if [ -z "$want" ] && [ -f "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ -n "$want" ] || return 0

    # appmenu is a dead token — the shell dropped the app menu in 3.32 — but it
    # is what the shipped default still says, so keeping it means the "all"
    # answer restores byte-for-byte what GNOME had before anyone touched this.
    case "$want" in
        close) layout="appmenu:close" ;;
        all)   layout="appmenu:minimize,maximize,close" ;;
        *)     warn "unknown window button layout '$want' — leaving it alone"
               return 0 ;;
    esac

    run gsettings set org.gnome.desktop.wm.preferences button-layout "$layout"
    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi
}

# Same shape as apply_window_buttons and for the same reason: cursor-size is
# a GNOME preference shared with Tweaks, not this project's styling, so a
# flagless install leaves it exactly where it found it.
apply_cursor_size() {
    local want="${CURSOR_SIZE:-}" memo="$CONF_DIR/cursor-size"
    if [ -z "$want" ] && [ -f "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ -n "$want" ] || return 0

    case "$want" in
        ''|*[!0-9]*) warn "unknown cursor size '$want' — leaving it alone"
                     return 0 ;;
    esac

    run gsettings set org.gnome.desktop.interface cursor-size "$want"
    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi
}

apply_accent() {
    # Accent is intentionally separable from the full interface-theme write:
    # it is GNOME's preference and a narrow GUI edit must not reset appearance.
    run gsettings set org.gnome.desktop.interface accent-color "$ACCENT"
    disable_accent_overriders
    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$ACCENT" > "$CONF_DIR/accent"
    fi
}

apply_gsettings() {
    step "Setting themes and accent"

    # prefer-dark is set below, so pick the dark half of the pair here and save
    # the agent a visible swap a moment later.
    #
    # Nothing is resolved at all when the icons are being kept. --no-icons is a
    # promise not to touch the key, and the promise has to hold in this step
    # too: it used to write icon-theme whatever the flag said, so "Default"
    # installed no pack and then pointed the key at one anyway — and every
    # later run, flagless or from the window, put this theme's pack back over
    # whatever GNOME Tweaks or anything else had set since.
    local base icons=""
    if [ "${WANT_ICONS:-1}" = 1 ]; then
        base="$(icon_base)"
        icons="$(icon_variant "$base" Dark || true)"
        [ -n "$icons" ] \
            || { warn "icon theme $base is not installed — falling back to Adwaita"; icons="Adwaita"; }
    fi

    # prefer-dark and the accent are GNOME's own keys and a preference of the
    # user's, not this theme's styling, so they stand in every mode. The GTK
    # theme is ours, and in solid mode it goes back to GNOME's default along
    # with the shell theme — that pair is what makes a stood-down desktop look
    # like one, rather than a themed desktop with the blur removed.
    run gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    apply_accent
    if [ "${WANT_STYLING:-1}" = 1 ]; then
        run gsettings set org.gnome.desktop.interface gtk-theme "$THEME_NAME"
        run dconf write /org/gnome/shell/extensions/user-theme/name "'$THEME_NAME'"
    else
        run gsettings reset org.gnome.desktop.interface gtk-theme
        run dconf write /org/gnome/shell/extensions/user-theme/name "''"
        ok "gtk-theme and the shell theme reset — the theme has stood down"
    fi
    if [ -n "$icons" ]; then
        run gsettings set org.gnome.desktop.interface icon-theme   "$icons"
    fi

    # Remembered so the next flagless run comes back to this accent rather than
    # to the default. install.sh reads it back before validating. Written here
    # rather than at parse time so that a run which died before this point
    # leaves the previous answer standing.
    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        # "keep" is the memo for --no-icons, and the reason it has to exist:
        # without it the next flagless run reads the last pack out of icon-pack
        # and installs it again, which is the same override by a slower route.
        # remember_icon_pack writes the other answers, from install_icons.
        if [ "${WANT_ICONS:-1}" != 1 ]; then
            printf '%s\n' keep > "$CONF_DIR/icon-pack"
        fi
    fi

    # Empty means the pointer is not ours to write, the same way as the icons
    # above: --no-cursors leaves whatever is set, from wherever it was set.
    local cursor=""
    if [ "${WANT_CURSORS:-1}" != 1 ]; then
        cursor=""
    elif [ "${CURSORS:-adwaita}" = mactahoe ] \
       && { [ -d "$HOME/.local/share/icons/MacTahoe-dark" ] \
            || [ -d "/usr/share/icons/MacTahoe-dark" ]; }; then
        cursor='MacTahoe-dark'
    elif [ "${CURSORS:-adwaita}" = aosp ] \
       && { [ -d "$HOME/.local/share/icons/aosp-cursors" ] \
            || [ -d "/usr/share/icons/aosp-cursors" ]; }; then
        # The directory name, not the Name= in index.theme: the key names a
        # directory, and this pack calls itself "AOSP Cursors" inside the file.
        cursor='aosp-cursors'
    elif [ "${CURSORS:-adwaita}" = original ]; then
        # Adwaita if nothing was recorded, which is also GNOME's own default —
        # so the fallback is the same answer uninstall.sh's gsettings reset
        # would give.
        local o; o="$(gsettings_original cursor-theme)"
        cursor="${o:-Adwaita}"
    else
        cursor='Adwaita'
    fi
    if [ -n "$cursor" ]; then
        run gsettings set org.gnome.desktop.interface cursor-theme "$cursor"
    fi

    # Remembered like the accent above and for the same reason: a later flagless
    # run has no other way to know which pack was chosen, and would come back to
    # the Adwaita default over a deliberate --cursors mactahoe. "keep" is a
    # choice like the others and is remembered like the others, or the next run
    # would go back to setting the key.
    if [ "${DRY_RUN:-0}" != 1 ]; then
        if [ "${WANT_CURSORS:-1}" = 1 ]; then
            printf '%s\n' "${CURSORS:-adwaita}" > "$CONF_DIR/cursor-pack"
        else
            printf '%s\n' keep > "$CONF_DIR/cursor-pack"
        fi
    fi

    # Here rather than in load_dconf: it is a gsettings key like the four above,
    # and this is the step that runs in the --settings-only path with them.
    apply_window_buttons
    apply_cursor_size
    apply_font

    # "left alone" rather than a name, because there is no name to give: the
    # key was not read and not written, and printing what it happens to hold
    # would read like this run had set it.
    local icon_say="${icons:-left alone}" cursor_say="${cursor:-left alone}"
    local font_say; font_say="$(font_family)"; font_say="${font_say:-system}"
    if [ "${WANT_STYLING:-1}" = 1 ]; then
        ok "gtk-theme=$THEME_NAME  icons=$icon_say  cursor=$cursor_say  accent=$ACCENT  font=$font_say"
    else
        ok "icons=$icon_say  cursor=$cursor_say  accent=$ACCENT  font=$font_say — theme keys left at GNOME's defaults"
    fi
}

# The three keys that carry the interface font, and the memo behind them.
#
# Three rather than one because GNOME splits the job: font-name is every label,
# menu and button; document-font-name is what text views and the document
# viewers read; and titlebar-font is Mutter's, under a different schema. Setting
# one and not the others is how a desktop ends up in two typefaces at once, so
# they move together.
#
# monospace-font-name is not here on purpose. None of the three fonts offered
# has a monospaced face, and writing one of them into that key would put a
# proportional font behind every terminal and code view on the machine.
#
# Font size is not this project's to have an opinion about: someone who set
# theirs to 10 or 12 did so about their screen, not about this theme. The size
# already in the key is kept and only the family is replaced, which is also
# what makes --font system able to be a true undo — it puts back exactly what
# gsettings_backup_once recorded, size and all.
apply_font() {
    local family; family="$(font_family)"

    # Recorded before the first write, so that --font system has something to
    # go back to that is the user's rather than GNOME's. Three separate names
    # because gsettings_backup_once keys its file by the name it is given.
    gsettings_backup_once org.gnome.desktop.interface font-name font-name
    gsettings_backup_once org.gnome.desktop.interface document-font-name document-font-name
    gsettings_backup_once org.gnome.desktop.wm.preferences titlebar-font titlebar-font

    if [ -z "$family" ]; then
        # Not `gsettings reset`: what is being restored is the font from before
        # this project first ran, and on a machine where that was already a
        # choice of the user's, reset would throw it away in favour of GNOME's
        # default. Reset is the fallback for a machine with nothing recorded,
        # which is the only case where GNOME's default is the honest answer.
        local key orig
        for key in font-name document-font-name; do
            orig="$(gsettings_original "$key")"
            if [ -n "$orig" ]; then
                run gsettings set org.gnome.desktop.interface "$key" "$orig"
            else
                run gsettings reset org.gnome.desktop.interface "$key"
            fi
        done
        orig="$(gsettings_original titlebar-font)"
        if [ -n "$orig" ]; then
            run gsettings set org.gnome.desktop.wm.preferences titlebar-font "$orig"
        else
            run gsettings reset org.gnome.desktop.wm.preferences titlebar-font
        fi
    else
        run gsettings set org.gnome.desktop.interface font-name \
            "$family $(font_size_now org.gnome.desktop.interface font-name)"
        run gsettings set org.gnome.desktop.interface document-font-name \
            "$family $(font_size_now org.gnome.desktop.interface document-font-name)"
        # Bold, because that is what GNOME's own default titlebar-font is
        # (Cantarell Bold 11) and a window title is the one place the desktop
        # asks for weight.
        run gsettings set org.gnome.desktop.wm.preferences titlebar-font \
            "$family Bold $(font_size_now org.gnome.desktop.wm.preferences titlebar-font)"
    fi

    # Remembered like the accent and the packs: a later flagless run has no
    # other way to know which font was chosen, and would come back to leaving
    # the keys alone over a deliberate --font.
    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "${FONT:-system}" > "$CONF_DIR/font"
    fi
}

# The size currently in one of the three font keys, or 11 where there is not
# one to read. Read live rather than out of the backup: someone who moved their
# interface font to 10 or 12 after installing did so about their screen, and a
# later run that put the recorded size back would undo it every time.
#
# "Cantarell 11" is a family and a size in one string, and only the trailing
# bare number is the size — "Cantarell Bold" has none, and neither has an empty
# key. gsettings prints strings quoted, so the quotes come off first.
font_size_now() {
    local desc last
    desc="$(gsettings get "$1" "$2" 2>/dev/null || true)"
    desc="${desc#\'}"; desc="${desc%\'}"
    last="${desc##* }"
    case "$last" in
        ''|*[!0-9]*)      printf '11\n' ;;
        "$desc")          printf '11\n' ;;   # no space in it: a family alone
        *)                printf '%s\n' "$last" ;;
    esac
}
