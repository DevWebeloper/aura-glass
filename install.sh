#!/usr/bin/env bash
#
# tahoe-glass — a macOS Tahoe glass desktop for GNOME.
#
#   https://github.com/DevWebeloper/tahoe-glass
#
# Nothing here needs root except the optional dependency install, and every
# asset lands under $HOME — which is what makes the same script work on both a
# mutable Arch system and a read-only ostree one like Bazzite.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$REPO_ROOT/lib/common.sh"
# shellcheck source=lib/distro.sh
. "$REPO_ROOT/lib/distro.sh"
# shellcheck source=lib/steps.sh
. "$REPO_ROOT/lib/steps.sh"

ACCENT="pink"
WANT_EXTRAS=0
WANT_ICONS=1
WANT_CURSORS=1
WANT_WM_BUTTONS=1
WANT_DEPS=1
WANT_OSD=1
WANT_PANEL_BLUR_FIX=1
CURSORS="adwaita"   # adwaita | mactahoe
GRAIN=""          # empty keeps the preset's value, or the remembered choice
ASSUME_YES=0
DRY_RUN=0
FORCE=0

VALID_ACCENTS="blue teal green yellow orange red pink purple slate"

usage() {
    cat <<EOF
${C_BLD}tahoe-glass${C_OFF} — a macOS Tahoe glass desktop for GNOME 48-50

  ${C_BLD}usage${C_OFF}
    ./install.sh [options]

  ${C_BLD}options${C_OFF}
    --accent COLOR    accent to build around (default: pink)
                      one of: $VALID_ACCENTS
    --full            the whole reference desktop: every extension and every
                      preset. What you want on a fresh machine
    --extras          also install the optional extensions
                      (Just Perfection, GNOME UI Tune, Space Bar, Dash to Dock)
    --grain N         strength of the film grain over blurred surfaces, 0-1.
                      How heavy it reads depends on the screen and the GPU;
                      drop it if the background looks like static
    --no-grain        no grain at all (same as --grain 0)
    --no-panel-blur-fix
                      skip the agent that rebuilds Blur My Shell's panel blur
                      when the monitor layout changes. Without it the top bar
                      can show a strip that doesn't line up with the wallpaper
    --cursors WHICH   adwaita (default, ships with GNOME) or mactahoe
    --no-osd          keep the stock volume and brightness popup. By default
                      it is reduced to its level bar — no icon, no device
                      name — on a blurred pill
    --no-icons        keep your current icon theme
    --no-cursors      keep your current cursor theme
    --no-wm-buttons   keep your current titlebar button layout
    --no-deps         never touch the package manager
    --force           reinstall things that are already present
    -y, --yes         answer yes to every prompt
    -n, --dry-run     print what would happen, change nothing
    -h, --help        this

  ${C_BLD}after installing${C_OFF}
    log out and back in, then use  tahoe-glass-apply  to re-apply the CSS
    after any theme update, and  ./uninstall.sh  to undo everything.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --accent)        ACCENT="${2:-}"; shift 2 ;;
        --accent=*)      ACCENT="${1#*=}"; shift ;;
        --extras)        WANT_EXTRAS=1; shift ;;
        # Turns on every optional piece, so a fresh machine ends up with the
        # whole reference desktop from one flag. Set here rather than checked
        # later so that anything after it still wins: --full --no-osd is the
        # lot minus the OSD. It deliberately leaves --cursors alone — MacTahoe
        # cursors are a different look, not a more complete one.
        --full)          WANT_EXTRAS=1; WANT_ICONS=1; WANT_CURSORS=1
                         WANT_WM_BUTTONS=1; WANT_OSD=1; WANT_PANEL_BLUR_FIX=1
                         shift ;;
        --grain)         GRAIN="${2:-}"; shift 2 ;;
        --grain=*)       GRAIN="${1#*=}"; shift ;;
        --no-grain)      GRAIN=0; shift ;;
        --panel-blur-fix)    WANT_PANEL_BLUR_FIX=1; shift ;;
        --no-panel-blur-fix) WANT_PANEL_BLUR_FIX=0; shift ;;
        --cursors)       CURSORS="${2:-}"; shift 2 ;;
        --cursors=*)     CURSORS="${1#*=}"; shift ;;
        --osd)           WANT_OSD=1; shift ;;
        --no-osd)        WANT_OSD=0; shift ;;
        --no-icons)      WANT_ICONS=0; shift ;;
        --no-cursors)    WANT_CURSORS=0; shift ;;
        --no-wm-buttons) WANT_WM_BUTTONS=0; shift ;;
        --no-deps)       WANT_DEPS=0; shift ;;
        --force)         FORCE=1; shift ;;
        -y|--yes)        ASSUME_YES=1; shift ;;
        -n|--dry-run)    DRY_RUN=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               usage; die "unknown option: $1" ;;
    esac
done

case "$CURSORS" in
    adwaita|mactahoe) ;;
    *) die "unknown --cursors '$CURSORS' — pick adwaita or mactahoe" ;;
esac

case " $VALID_ACCENTS " in
    *" $ACCENT "*) ;;
    *) die "unknown accent '$ACCENT' — pick one of: $VALID_ACCENTS" ;;
esac

printf '\n%s  tahoe-glass%s  %saccent %s%s\n' \
    "$C_BLD" "$C_OFF" "$C_DIM" "$ACCENT" "$C_OFF"
[ "$DRY_RUN" = 1 ] && printf '%s  dry run — nothing will be changed%s\n' "$C_DIM" "$C_OFF"

preflight

if [ "$WANT_DEPS" = 1 ]; then
    step "Checking dependencies"
    install_deps || die "dependencies are missing — re-run once they are installed, or pass --no-deps to try anyway"
else
    step "Checking dependencies"
    missing="$(missing_cmds | tr '\n' ' ')"
    if [ -n "${missing// /}" ]; then
        warn "missing (--no-deps given, continuing): $missing"
    else
        ok "all present"
    fi
fi

install_theme
install_extensions
if [ "$WANT_ICONS" = 1 ]; then install_icons; else step "Icons"; skip "left alone (--no-icons)"; fi
if [ "$WANT_CURSORS" = 1 ]; then install_cursors; else step "Cursors"; skip "left alone (--no-cursors)"; fi
load_dconf
install_css
apply_gsettings
install_icon_sync
flatpak_override
install_panel_blur_unit
enable_extensions
finish
