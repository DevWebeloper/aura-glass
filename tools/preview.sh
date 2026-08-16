#!/usr/bin/env bash
# Render this working tree's theme in a throwaway GNOME session and screenshot
# it, without touching the desktop you are sitting in front of.
#
# Why this exists: every CSS and dconf value here used to be checked by editing
# a file, applying it, logging out, and looking. That loop is slow enough that
# wrong values survived for weeks — see the corner-radius bisections in
# handoff.md. This runs the real shell against the real theme and hands back
# PNGs in about a minute.
#
#   tools/preview.sh                 shell screenshots from the current tree
#   tools/preview.sh --gtk-only      one GTK app, no shell, on your own session
#   tools/preview.sh --keep          leave the session up (see --keep below)
#   tools/preview.sh --gpu           sample GPU busy% while the session runs
#   tools/preview.sh --solid         render --no-blur mode instead of the glass one
#   tools/preview.sh --transparency 0.85   translucent app windows at that level
#   tools/preview.sh --tint 70             how much theme colour survives, vs black
#
# Every run is compared against the last accepted run of the same mode, and
# reports what moved. tools/check-shots.py --accept adopts the current run as
# the baseline; --mode glass and --mode solid keep separate ones.
#
# ---------------------------------------------------------------------------
# What this is NOT
#
# This is a headless render, not a window you can click around in. mutter 18 on
# this machine has no nested backend compiled in — `MetaBackendX11Nested` is not
# in libmutter-18.so, and gnome-shell's `--nested` option is gone — so a shell
# started inside your session takes the *native* backend, tries to take control
# of the seat, and dies with EBUSY against the session you are using. `gnome-
# shell --headless --virtual-monitor` is the mode that works, and it renders to
# a virtual output that only the screenshot API can see.
#
# Isolation is three separate things, and all three are needed:
#
#   dbus-run-session   a private bus, so the preview shell owns org.gnome.Shell
#                      without fighting the real one, and so the driver
#                      extension is reachable by nothing outside this session.
#   HOME               the User Themes extension reads ~/.themes/<name> relative
#                      to $HOME, which no XDG variable governs.
#   XDG_{CONFIG,DATA,CACHE}_HOME   where the preview session's own state lands,
#                      including the GSettings keyfile it is seeded from.
#                      Settings deliberately do not go through dconf here — see
#                      the long note in tools/preview-session.sh.
#
#   XDG_RUNTIME_DIR    isolated too, and this one is not optional. GNOME Shell
#                      disables every extension when
#                      $XDG_RUNTIME_DIR/gnome-shell-disable-extensions exists,
#                      and the live session leaves that file lying in the real
#                      one — so sharing it renders a stock desktop with no blur
#                      and no top bar geometry, which looks exactly like the
#                      theme having failed. Nothing is lost by isolating it: a
#                      headless shell has no host compositor to reach, and the
#                      test apps are launched with the same isolated value, so
#                      they still find the preview socket.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../tokens/tokens.sh
. "$REPO_ROOT/tokens/tokens.sh"
PROFILE="${AURA_PREVIEW_DIR:-${TAHOE_PREVIEW_DIR:-$HOME/.cache/aura-glass/preview}}"
SHOTS="${AURA_PREVIEW_SHOTS:-${TAHOE_PREVIEW_SHOTS:-$REPO_ROOT/screenshots/preview}}"
DISPLAY_NAME="aura-preview"
RESOLUTION="${AURA_PREVIEW_RES:-${TAHOE_PREVIEW_RES:-1920x1080}}"
THEME="Tahoe-Dark"
# Loaded only into the preview profile — see tools/preview-driver/extension.js
# for why it must never reach a real session.
DRIVER_UUID="aura-preview-driver@aura-glass.local"

MODE="shell"
KEEP=0
GPU=0
SOLID=0
TRANSPARENCY=""
TINT=""
GTK_APP="nautilus"

while [ $# -gt 0 ]; do
    case "$1" in
        --gtk-only) MODE="gtk"; [ "${2:-}" ] && [ "${2#--}" = "$2" ] && { GTK_APP="$2"; shift; }; shift ;;
        --keep)     KEEP=1; shift ;;
        --gpu)      GPU=1; shift ;;
        --solid)    SOLID=1; shift ;;
        --transparency) TRANSPARENCY="$2"; shift 2 ;;
        --tint)     TINT="$2"; shift 2 ;;
        --res)      RESOLUTION="$2"; shift 2 ;;
        -h|--help)  sed -n '2,34p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

say() { printf '\033[1;36m::\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

# --- the candidate profile -------------------------------------------------
#
# Built from the *installed* theme plus this tree's CSS, so what gets rendered
# is the working copy rather than whatever was last installed. bin/aura-glass-
# apply needs no special-casing for this: it already takes every path from
# $HOME, $AURA_GLASS_DIR and $AURA_GLASS_THEME.
build_profile() {
    local home="$PROFILE/home" conf="$PROFILE/home/.config/aura-glass"
    rm -rf "$PROFILE"
    mkdir -p "$home/.themes" "$home/.config" "$home/.local/share" "$home/.cache" "$conf"

    [ -d "$HOME/.themes/$THEME" ] || die \
        "$HOME/.themes/$THEME is not installed — run ./install.sh first. This
   previews changes to an installed theme; it does not build one from scratch."
    cp -a "$HOME/.themes/$THEME" "$home/.themes/$THEME"

    # Each installed extension is linked in individually rather than linking
    # the directory itself, because the preview needs one extension of its own
    # in there and a symlinked directory would put it in the real one.
    local extdir="$home/.local/share/gnome-shell/extensions" ext
    mkdir -p "$extdir"
    for ext in "$HOME/.local/share/gnome-shell/extensions"/*/; do
        [ -d "$ext" ] || continue
        ln -sfn "${ext%/}" "$extdir/$(basename "$ext")"
    done
    cp -a "$REPO_ROOT/tools/preview-driver" "$extdir/$DRIVER_UUID"

    [ -d "$HOME/.local/share/icons" ] && \
        ln -sfn "$HOME/.local/share/icons" "$home/.local/share/icons"

    # The GTK4 targets are generated files that live outside the theme
    # directory, so copying ~/.themes alone does not bring them and
    # aura-glass-apply has nothing to append to — every gtk4-*.css sheet was
    # silently skipped, and the GTK half of a preview was really stock
    # libadwaita. Seed them from the installed copies with any previously
    # applied block stripped, so apply starts from the theme's own output.
    mkdir -p "$home/.config/gtk-4.0"
    local t
    for t in gtk.css gtk-dark.css; do
        [ -f "$HOME/.config/gtk-4.0/$t" ] || continue
        python3 - "$HOME/.config/gtk-4.0/$t" "$home/.config/gtk-4.0/$t" <<'STRIP'
import re, sys
css = open(sys.argv[1], encoding="utf-8").read()
for name in ("aura-glass", "tahoe-glass", "tahoe-tweaks"):
    css = re.sub(r"/\* >>> %s BEGIN <<< \*/.*?/\* >>> %s END <<< \*/\n?" % (name, name),
                 "", css, flags=re.S)
open(sys.argv[2], "w", encoding="utf-8").write(css)
STRIP
    done

    cp "$REPO_ROOT"/css/shell-[0-9][0-9]-*.css "$REPO_ROOT"/css/gtk4-[0-9][0-9]-*.css "$conf/"
    cp "$REPO_ROOT/css/gtk3-tweaks.css" "$conf/"
    # Mirrors what install_css does with these two: solid mode gets the opaque
    # overrides and no popup blur sheet, glass mode the other way round.
    if [ "$SOLID" = 1 ]; then
        cp "$REPO_ROOT/css/shell-80-solid.css" "$conf/"
    else
        cp "$REPO_ROOT/css/shell-popup-blur.css" "$conf/"
    fi

    # The same sheet and the same rescale the installer applies, so what gets
    # rendered is what --app-transparency N would actually produce.
    if [ -n "$TRANSPARENCY" ]; then
        cp "$REPO_ROOT/css/gtk4-transparency.css" "$conf/"
        python3 "$REPO_ROOT/tools/rescale-transparency.py" \
                "$conf/gtk4-transparency.css" "$TRANSPARENCY" \
                "$TOKEN_APP_TRANSPARENCY_SHIPPED"
        # Tuning only: rewrites the tint in the profile copy so combinations can
        # be compared without editing the token and the sheet for each try.
        # Whatever is settled on goes into TOKEN_APP_TINT for real.
        if [ -n "$TINT" ]; then
            python3 - "$conf/gtk4-transparency.css" "$TINT" <<'TINTPY'
import re, sys
path, pct = sys.argv[1], int(sys.argv[2])
css = open(path, encoding="utf-8").read()
css = re.sub(r"(var\(--[a-z-]+\)) \d+%, #000000", r"\1 %d%%, #000000" % pct, css)
css = re.sub(r"(mix\(@[a-z_]+, #000000, )0?\.\d+\)",
             lambda m: "%s%.2f)" % (m.group(1), (100 - pct) / 100.0), css)
open(path, "w", encoding="utf-8").write(css)
TINTPY
        fi
    fi

    HOME="$home" AURA_GLASS_DIR="$conf" AURA_GLASS_THEME="$THEME" \
        bash "$REPO_ROOT/bin/aura-glass-apply" | sed 's/^/   /'
}

# --- GTK-only tier ---------------------------------------------------------
#
# GTK CSS needs no shell to be exercised, so this skips all of the above and
# runs one app against the candidate profile on the session you are already in.
# It only ever reads $PROFILE, never ~/.config/gtk-4.0, so it cannot disturb
# the desktop it is running on. GTK_DEBUG=interactive opens the inspector, which
# is the fastest way to try a selector by hand.
if [ "$MODE" = gtk ]; then
    say "building candidate profile"
    build_profile
    say "launching $GTK_APP with the GTK inspector"
    echo "   close the app window to finish"
    HOME="$PROFILE/home" XDG_CONFIG_HOME="$PROFILE/home/.config" \
    XDG_DATA_HOME="$PROFILE/home/.local/share" GTK_DEBUG=interactive \
        "$GTK_APP" || true
    exit 0
fi

# --- shell tier ------------------------------------------------------------
command -v dbus-run-session >/dev/null || die "dbus-run-session is missing (dbus)"
command -v gnome-shell      >/dev/null || die "gnome-shell is missing"

say "building candidate profile"
build_profile
mkdir -p "$SHOTS"

export TG_REPO_ROOT="$REPO_ROOT" TG_PROFILE="$PROFILE" TG_SHOTS="$SHOTS"
export TG_DISPLAY="$DISPLAY_NAME" TG_RES="$RESOLUTION" TG_KEEP="$KEEP" TG_GPU="$GPU"
export TG_DRIVER_UUID="$DRIVER_UUID" TG_SOLID="$SOLID"

# Kept inside the real runtime dir so it is still tmpfs owned by this user,
# which is what a runtime dir has to be; only the path differs.
PREVIEW_RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/aura-glass-preview"
rm -rf "$PREVIEW_RUNTIME"
mkdir -p -m 0700 "$PREVIEW_RUNTIME"

say "starting a private bus and a headless shell"
dbus-run-session -- env \
    HOME="$PROFILE/home" \
    XDG_CONFIG_HOME="$PROFILE/home/.config" \
    XDG_DATA_HOME="$PROFILE/home/.local/share" \
    XDG_CACHE_HOME="$PROFILE/home/.cache" \
    XDG_RUNTIME_DIR="$PREVIEW_RUNTIME" \
    GTK_THEME="" \
    bash "$REPO_ROOT/tools/preview-session.sh"

rm -rf "$PREVIEW_RUNTIME"

say "screenshots in $SHOTS"
ls -1 "$SHOTS" | sed 's/^/   /'

# Glass and solid keep separate baselines on purpose: the two modes are meant to
# differ, so a shared one would report every mode switch as a regression and be
# ignored within a week. Exits non-zero when something moved, so this is usable
# from a script and not only by eye.
MODE_NAME=glass
[ "$SOLID" = 1 ] && MODE_NAME=solid
say "comparing against the '$MODE_NAME' baseline"
python3 "$REPO_ROOT/tools/check-shots.py" --mode "$MODE_NAME" --shots "$SHOTS"
