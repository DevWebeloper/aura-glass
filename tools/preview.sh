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
PROFILE="${TAHOE_PREVIEW_DIR:-$HOME/.cache/tahoe-glass/preview}"
SHOTS="${TAHOE_PREVIEW_SHOTS:-$REPO_ROOT/screenshots/preview}"
DISPLAY_NAME="tahoe-preview"
RESOLUTION="${TAHOE_PREVIEW_RES:-1920x1080}"
THEME="Tahoe-Dark"
# Loaded only into the preview profile — see tools/preview-driver/extension.js
# for why it must never reach a real session.
DRIVER_UUID="tahoe-preview-driver@tahoe-glass.local"

MODE="shell"
KEEP=0
GPU=0
GTK_APP="nautilus"

while [ $# -gt 0 ]; do
    case "$1" in
        --gtk-only) MODE="gtk"; [ "${2:-}" ] && [ "${2#--}" = "$2" ] && { GTK_APP="$2"; shift; }; shift ;;
        --keep)     KEEP=1; shift ;;
        --gpu)      GPU=1; shift ;;
        --res)      RESOLUTION="$2"; shift 2 ;;
        -h|--help)  sed -n '2,30p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

say() { printf '\033[1;36m::\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

# --- the candidate profile -------------------------------------------------
#
# Built from the *installed* theme plus this tree's CSS, so what gets rendered
# is the working copy rather than whatever was last installed. bin/tahoe-glass-
# apply needs no special-casing for this: it already takes every path from
# $HOME, $TAHOE_GLASS_DIR and $TAHOE_GLASS_THEME.
build_profile() {
    local home="$PROFILE/home" conf="$PROFILE/home/.config/tahoe-glass"
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

    cp "$REPO_ROOT"/css/shell-[0-9][0-9]-*.css "$REPO_ROOT"/css/gtk4-[0-9][0-9]-*.css "$conf/"
    cp "$REPO_ROOT/css/gtk3-tweaks.css" "$REPO_ROOT/css/shell-popup-blur.css" "$conf/"

    HOME="$home" TAHOE_GLASS_DIR="$conf" TAHOE_GLASS_THEME="$THEME" \
        bash "$REPO_ROOT/bin/tahoe-glass-apply" | sed 's/^/   /'
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
export TG_DRIVER_UUID="$DRIVER_UUID"

# Kept inside the real runtime dir so it is still tmpfs owned by this user,
# which is what a runtime dir has to be; only the path differs.
PREVIEW_RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/tahoe-glass-preview"
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
