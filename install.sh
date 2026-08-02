#!/usr/bin/env bash
#
# tahoe-glass — a macOS Tahoe glass desktop for GNOME.
#
#   https://github.com/DevWebeloper/tahoe-glass
#
# Nothing here needs root except the optional dependency install and the
# optional rounded-blur library: every other asset lands under $HOME.
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
WANT_BMS_GIT=1
WANT_POPUP_BLUR=1
POPUP_BLUR_EXPLICIT=""
WANT_ROUNDED_BLUR=1
CURSORS="adwaita"   # adwaita | mactahoe
ICONS=""            # empty = remembered choice, then colloid
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
    --grain N         film grain over blurred surfaces, 0-1. The preset ships
                      none: how heavy it reads depends entirely on the screen
                      and the GPU, and on most it looks like static rather
                      than like frosted glass. Raise it if you want texture
    --no-grain        no grain at all (same as --grain 0, and the default)
    --no-panel-blur-fix
                      skip the agent that rebuilds Blur My Shell's panel blur
                      when the monitor layout changes. Without it the top bar
                      can show a strip that doesn't line up with the wallpaper
    --icons WHICH     colloid (default, follows --accent) or reversal-COLOUR,
                      e.g. reversal-purple. Folder colour is separate from the
                      accent on purpose. Remembered for later runs
    --cursors WHICH   adwaita (default, ships with GNOME) or mactahoe
    --no-osd          keep the stock volume and brightness popup. By default
                      it is reduced to its level bar — no icon, no device
                      name — on a blurred pill
    --no-popup-blur   keep the flat translucent popups and skip the blur
                      behind menus, quick settings, notifications and the OSD
    --no-bms-git      use Blur My Shell's published build instead of the pinned
                      git one. That build has no popup component, so it
                      implies --no-popup-blur
    --no-rounded-blur skip gnome-rounded-blur. It is the only thing installed
                      outside \$HOME and it always asks first, --yes included.
                      Without it the popup blur is still rounded, it just
                      samples the wallpaper instead of the window behind it
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
        # --bms-git, --popup-blur and --rounded-blur are already on by default
        # and so are not repeated here. Note that --full does not make the
        # rounded-blur step any less interactive: it is the one step that
        # installs outside $HOME and it always asks, --yes included.
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
        --icons)         ICONS="${2:-}"; shift 2 ;;
        --icons=*)       ICONS="${1#*=}"; shift ;;
        --osd)           WANT_OSD=1; shift ;;
        --no-osd)        WANT_OSD=0; shift ;;
        # The published Blur My Shell has no popup schema at all, so asking for
        # one without the other cannot work. Each flag drags the other along.
        --bms-git)       WANT_BMS_GIT=1; shift ;;
        --no-bms-git)    WANT_BMS_GIT=0; WANT_POPUP_BLUR=0
                         POPUP_BLUR_EXPLICIT=1; shift ;;
        --popup-blur)    WANT_POPUP_BLUR=1; WANT_BMS_GIT=1
                         POPUP_BLUR_EXPLICIT=1; shift ;;
        --no-popup-blur) WANT_POPUP_BLUR=0; POPUP_BLUR_EXPLICIT=1; shift ;;
        --rounded-blur)      WANT_ROUNDED_BLUR=1; shift ;;
        --no-rounded-blur)   WANT_ROUNDED_BLUR=0; shift ;;
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

# Remembered per machine, for the same reason --grain is: dconf and gsettings
# get rewritten on every run, so a flagless re-install would quietly put the
# default pack back over a deliberate choice.
if [ -z "$ICONS" ] && [ -r "$CONF_DIR/icon-pack" ]; then
    ICONS="$(cat "$CONF_DIR/icon-pack" 2>/dev/null || true)"
fi
ICONS="${ICONS:-colloid}"

VALID_REVERSAL="default black blue brown cyan green grey lightblue orange pink purple red"
case "$ICONS" in
    colloid|reversal) ;;
    reversal-*)
        case " $VALID_REVERSAL " in
            *" ${ICONS#reversal-} "*) ;;
            *) die "unknown Reversal colour '${ICONS#reversal-}' — pick one of: $VALID_REVERSAL" ;;
        esac ;;
    *) die "unknown --icons '$ICONS' — colloid, reversal, or reversal-COLOUR" ;;
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
# Before load_dconf, so apply_popup_blur sees the result. On a first install it
# will still pick static: Blur My Shell only writes rounded-blur-found once the
# shell has loaded this build, which is the next login.
install_rounded_blur
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
