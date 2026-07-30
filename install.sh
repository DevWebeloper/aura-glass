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
    --extras          also install the optional extensions
                      (Just Perfection, GNOME UI Tune, Space Bar, Dash to Dock)
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
flatpak_override
install_panel_blur_unit
enable_extensions
finish
