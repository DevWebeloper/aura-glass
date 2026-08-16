#!/usr/bin/env bash
#
# aura-glass — a fluid frosted-glass desktop for GNOME.
#
#   https://github.com/DevWebeloper/aura-glass
#
# Nothing here needs root except the optional dependency install, the
# optional rounded-blur library, and the optional GDM login screen theme:
# every other asset lands under $HOME.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$REPO_ROOT/lib/common.sh"
# shellcheck source=lib/distro.sh
. "$REPO_ROOT/lib/distro.sh"
# The steps were one file until they were split by concern, the same way css/
# was. steps.sh comes first because it defines CONF_DIR, which the flag parsing
# below reads; the rest are definitions only and their order does not matter.
# shellcheck source=lib/steps.sh
. "$REPO_ROOT/lib/steps.sh"
# shellcheck source=lib/steps-extensions.sh
. "$REPO_ROOT/lib/steps-extensions.sh"
# shellcheck source=lib/steps-assets.sh
. "$REPO_ROOT/lib/steps-assets.sh"
# shellcheck source=lib/steps-css.sh
. "$REPO_ROOT/lib/steps-css.sh"
# shellcheck source=lib/steps-dconf.sh
. "$REPO_ROOT/lib/steps-dconf.sh"
# shellcheck source=lib/steps-integration.sh
. "$REPO_ROOT/lib/steps-integration.sh"
# shellcheck source=lib/steps-gdm.sh
. "$REPO_ROOT/lib/steps-gdm.sh"
# Values written down in more than one place live here, so that the copy in a
# stylesheet and the copy in a dconf key cannot drift apart unnoticed.
# tools/check-tokens.sh asserts they still agree.
# shellcheck source=tokens/tokens.sh
. "$REPO_ROOT/tokens/tokens.sh"

ACCENT=""          # empty = remembered choice, then $ACCENT_DEFAULT
ACCENT_DEFAULT="purple"
WANT_EXTRAS=1
WANT_ICONS=1
WANT_CURSORS=1
WANT_DEPS=1
WANT_OSD=1
WANT_PANEL_BLUR_FIX=1
WANT_GDM=0
WANT_GDM_MONITORS=0
GDM_BG="default"
WANT_BMS_GIT=1
WANT_BLUR=1
WANT_WINDOW_BLUR=1
WINDOW_BLUR_EXPLICIT=""
WANT_POPUP_BLUR=1
POPUP_BLUR_EXPLICIT=""
WANT_ROUNDED_BLUR=1
APP_TRANSPARENCY=""   # empty = remembered choice, then off (e.g. 0.90 / 90%)
APP_OPACITY=""        # empty = remembered choice, then 255 (e.g. 230)
APP_OPACITY_EXPLICIT=""
CURSORS="adwaita"   # adwaita | mactahoe
ICONS=""            # empty = remembered choice, then colloid
GRAIN=""          # empty keeps the preset's value, or the remembered choice
ASSUME_YES=0
DRY_RUN=0
FORCE=0
EXPLICIT_FLAGS=0
FORCE_INTERACTIVE=0

VALID_ACCENTS="blue teal green yellow orange red pink purple slate"

usage() {
    cat <<EOF
${C_BLD}aura-glass${C_OFF} — a fluid frosted-glass desktop for GNOME 48-50

  ${C_BLD}usage${C_OFF}
    ./install.sh [options]

  ${C_BLD}interactive mode${C_OFF}
    Running ./install.sh with no options in an interactive terminal launches
    the step-by-step setup wizard to configure accent, blur, icons and extensions.

  ${C_BLD}options${C_OFF}
    --interactive     launch the interactive setup wizard explicitly
    --accent COLOR    accent to build around (default: $ACCENT_DEFAULT, and
                      remembered for later runs). One of: $VALID_ACCENTS
    --recommended     install the recommended optional extensions (Default)
                      (Just Perfection, GNOME UI Tune, Space Bar, AppIndicator Support,
                       Clipboard Indicator, Magic Lamp Effect)
    --full            every optional piece at once: all 14 extra extensions,
                      plus icons, cursors, OSD and panel-blur-fix
    --extras          alias for --recommended
    --all-extras      install all 14 optional extensions
    --no-extras       minimal install with core look only (no optional extensions)
    --minimal         same as --no-extras
    --grain N         film grain over blurred surfaces, 0-1. Default is 0
    --no-grain        no grain at all (same as --grain 0, and the default)
    --panel-blur-fix  agent that rebuilds Blur My Shell's panel blur on layout change (default: on)
    --no-panel-blur-fix skip the panel blur rebuild agent
    --icons WHICH     colloid (default, follows --accent) or reversal-COLOUR,
                      e.g. reversal-purple. Remembered for later runs
    --cursors WHICH   adwaita (default, ships with GNOME) or mactahoe
    --osd             minimal pill OSD for volume & brightness (default: on)
    --no-osd          keep stock volume and brightness popup
    --no-popup-blur   keep flat translucent popups and skip blur behind menus
    --no-bms-git      use Blur My Shell published build (implies --no-popup-blur)
    --app-transparency LEVEL
                      window transparency with blur: 90% (230, default), 82% (210),
                      94% (240), or custom 70%-100% (e.g. --app-transparency 90%). Off by default
    --window-opacity LEVEL
                      alias for --app-transparency (e.g. 90%, 82%, 94%, 230, 210, 240)
    --no-app-transparency keep app windows opaque (default)
    --window-blur     blur behind app windows (heavy on GPU, off by default)
    --no-window-blur  keep window blur off (default)
    --no-blur         solid mode: no blur anywhere, opaque surfaces instead of
                      translucent ones (best for low-end GPUs or battery saver)
    --no-rounded-blur skip gnome-rounded-blur library (popup blur falls back to static)
    --gdm             theme the GDM login screen with blurred Tahoe style (requires sudo)
    --gdm-background PATH
                      set custom background image for GDM (default: blurred wallpaper)
    --no-gdm          do not theme the GDM login screen (default)
    --gdm-monitors    sync primary monitor layout to GDM login screen (good for multi-monitor, requires sudo)
    --no-gdm-monitors keep default GDM monitor layout (default)
    --no-icons        keep your current icon theme
    --no-cursors      keep your current cursor theme
    --no-deps         never touch the package manager
    --force           reinstall things that are already present
    -y, --yes         answer yes to every prompt (non-interactive)
    -n, --dry-run     print what would happen, change nothing
    -h, --help        this

  ${C_BLD}after installing${C_OFF}
    log out and back in, then use  aura-glass-apply  to re-apply the CSS
    after any theme update, and  ./uninstall.sh  to undo everything.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --interactive)   FORCE_INTERACTIVE=1; shift ;;
        --accent)        ACCENT="${2:-}"; EXPLICIT_FLAGS=1; shift 2 ;;
        --accent=*)      ACCENT="${1#*=}"; EXPLICIT_FLAGS=1; shift ;;
        --recommended|--extras)
                         WANT_EXTRAS=1; EXT_EXTRA=("${EXT_EXTRA_RECOMMENDED[@]}"); EXPLICIT_FLAGS=1; shift ;;
        --all-extras)    WANT_EXTRAS=1; EXT_EXTRA=("${EXT_EXTRA_ALL[@]}"); EXPLICIT_FLAGS=1; shift ;;
        --no-extras|--minimal)
                         WANT_EXTRAS=0; EXT_EXTRA=(); EXPLICIT_FLAGS=1; shift ;;
        --full)          WANT_EXTRAS=1; EXT_EXTRA=("${EXT_EXTRA_ALL[@]}"); WANT_ICONS=1; WANT_CURSORS=1
                         WANT_OSD=1; WANT_PANEL_BLUR_FIX=1; EXPLICIT_FLAGS=1; shift ;;
        --grain)         GRAIN="${2:-}"; EXPLICIT_FLAGS=1; shift 2 ;;
        --grain=*)       GRAIN="${1#*=}"; EXPLICIT_FLAGS=1; shift ;;
        --no-grain)      GRAIN=0; EXPLICIT_FLAGS=1; shift ;;
        --panel-blur-fix)    WANT_PANEL_BLUR_FIX=1; EXPLICIT_FLAGS=1; shift ;;
        --no-panel-blur-fix) WANT_PANEL_BLUR_FIX=0; EXPLICIT_FLAGS=1; shift ;;
        --cursors)       CURSORS="${2:-}"; EXPLICIT_FLAGS=1; shift 2 ;;
        --cursors=*)     CURSORS="${1#*=}"; EXPLICIT_FLAGS=1; shift ;;
        --icons)         ICONS="${2:-}"; EXPLICIT_FLAGS=1; shift 2 ;;
        --icons=*)       ICONS="${1#*=}"; EXPLICIT_FLAGS=1; shift ;;
        --osd)           WANT_OSD=1; EXPLICIT_FLAGS=1; shift ;;
        --no-osd)        WANT_OSD=0; EXPLICIT_FLAGS=1; shift ;;
        --bms-git)       WANT_BMS_GIT=1; EXPLICIT_FLAGS=1; shift ;;
        --no-bms-git)    WANT_BMS_GIT=0; WANT_POPUP_BLUR=0
                         POPUP_BLUR_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --popup-blur)    WANT_POPUP_BLUR=1; WANT_BMS_GIT=1
                         POPUP_BLUR_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --no-popup-blur) WANT_POPUP_BLUR=0; POPUP_BLUR_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --blur)          WANT_BLUR=1; EXPLICIT_FLAGS=1; shift ;;
        --window-blur)   WANT_WINDOW_BLUR=1; WINDOW_BLUR_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --no-window-blur) WANT_WINDOW_BLUR=0; WINDOW_BLUR_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --no-blur)       WANT_BLUR=0; WANT_POPUP_BLUR=0; POPUP_BLUR_EXPLICIT=1
                         WANT_WINDOW_BLUR=0; WINDOW_BLUR_EXPLICIT=1
                         WANT_ROUNDED_BLUR=0; EXPLICIT_FLAGS=1; shift ;;
        --rounded-blur)      WANT_ROUNDED_BLUR=1; EXPLICIT_FLAGS=1; shift ;;
        --no-rounded-blur)   WANT_ROUNDED_BLUR=0; EXPLICIT_FLAGS=1; shift ;;
        --app-transparency|--window-opacity|--window-transparency)
                         APP_TRANSPARENCY="${2:-$TOKEN_APP_TRANSPARENCY_SHIPPED}"; EXPLICIT_FLAGS=1; APP_OPACITY_EXPLICIT=1; shift 2 ;;
        --app-transparency=*|--window-opacity=*|--window-transparency=*)
                         APP_TRANSPARENCY="${1#*=}"; EXPLICIT_FLAGS=1; APP_OPACITY_EXPLICIT=1; shift ;;
        --no-app-transparency|--no-window-opacity|--no-window-transparency)
                         APP_TRANSPARENCY=0; APP_OPACITY=255; EXPLICIT_FLAGS=1; APP_OPACITY_EXPLICIT=1; shift ;;
        --gdm)           WANT_GDM=1; EXPLICIT_FLAGS=1; shift ;;
        --no-gdm)        WANT_GDM=0; EXPLICIT_FLAGS=1; shift ;;
        --gdm-monitors|--sync-monitors) WANT_GDM_MONITORS=1; EXPLICIT_FLAGS=1; shift ;;
        --no-gdm-monitors) WANT_GDM_MONITORS=0; EXPLICIT_FLAGS=1; shift ;;
        --gdm-background) GDM_BG="${2:-default}"; WANT_GDM=1; EXPLICIT_FLAGS=1; shift 2 ;;
        --gdm-background=*) GDM_BG="${1#*=}"; WANT_GDM=1; EXPLICIT_FLAGS=1; shift ;;
        --no-icons)      WANT_ICONS=0; EXPLICIT_FLAGS=1; shift ;;
        --no-cursors)    WANT_CURSORS=0; EXPLICIT_FLAGS=1; shift ;;
        --no-wm-buttons|--wm-buttons) # Deprecated / window buttons kept at system default
                         EXPLICIT_FLAGS=1; shift ;;
        --no-deps)       WANT_DEPS=0; EXPLICIT_FLAGS=1; shift ;;
        --force)         FORCE=1; EXPLICIT_FLAGS=1; shift ;;
        -y|--yes)        ASSUME_YES=1; EXPLICIT_FLAGS=1; shift ;;
        -n|--dry-run)    DRY_RUN=1; EXPLICIT_FLAGS=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               usage; die "unknown option: $1" ;;
    esac
done

# Resolve remembered accent or default
if [ -z "$ACCENT" ] && [ -r "$CONF_DIR/accent" ]; then
    ACCENT="$(cat "$CONF_DIR/accent" 2>/dev/null || true)"
fi
ACCENT="${ACCENT:-$ACCENT_DEFAULT}"

# Interactive setup wizard when running without flags in an interactive terminal
if { [ "$EXPLICIT_FLAGS" = 0 ] || [ "$FORCE_INTERACTIVE" = 1 ]; } && [ "$ASSUME_YES" = 0 ] && [ -t 0 ]; then
    cat <<EOF

${C_BLD}┌─────────────────────────────────────────────────────────────┐${C_OFF}
${C_BLD}│  aura-glass — Fluid Frosted Glass Desktop for GNOME 48-50   │${C_OFF}
${C_BLD}└─────────────────────────────────────────────────────────────┘${C_OFF}

EOF

    # 1. Accent Color
    printf '%sStep 1: Choose Accent Color%s\n' "$C_BLD" "$C_OFF"
    printf '  Current default / remembered: %s%s%s\n' "$C_GRN" "$ACCENT" "$C_OFF"
    printf '  Available: [1] purple  [2] blue   [3] teal    [4] green   [5] yellow\n'
    printf '             [6] orange  [7] red    [8] pink    [9] slate\n'
    printf '  Select accent [1-9 or name, default: %s]: ' "$ACCENT"
    read -r ans_accent || ans_accent=""
    case "${ans_accent,,}" in
        1|purple) ACCENT="purple" ;;
        2|blue)   ACCENT="blue" ;;
        3|teal)   ACCENT="teal" ;;
        4|green)  ACCENT="green" ;;
        5|yellow) ACCENT="yellow" ;;
        6|orange) ACCENT="orange" ;;
        7|red)    ACCENT="red" ;;
        8|pink)   ACCENT="pink" ;;
        9|slate)  ACCENT="slate" ;;
        "")       ;; # Keep default
        *)
            if [[ " $VALID_ACCENTS " =~ [[:space:]]${ans_accent,,}[[:space:]] ]]; then
                ACCENT="${ans_accent,,}"
            else
                warn "Unknown accent '$ans_accent' — using $ACCENT"
            fi
            ;;
    esac
    printf '  %s✓%s Accent set to %s%s%s\n\n' "$C_GRN" "$C_OFF" "$C_BLD" "$ACCENT" "$C_OFF"

    # 2. Blur & Visual Depth
    printf '%sStep 2: Blur & Visual Depth%s\n' "$C_BLD" "$C_OFF"
    printf '  %s[1]%s Frosted Glass %s[Default — blur on top bar, popups, menus, and OSD]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
    printf '  %s[2]%s Solid Mode %s[Opaque surfaces, no blur — lightweight for older GPUs or battery]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
    printf '  Choice [1-2, default 1]: '
    read -r ans_blur || ans_blur="1"
    case "$ans_blur" in
        2|solid|no-blur)
            WANT_BLUR=0
            WANT_POPUP_BLUR=0
            POPUP_BLUR_EXPLICIT=1
            WANT_WINDOW_BLUR=0
            WINDOW_BLUR_EXPLICIT=1
            WANT_ROUNDED_BLUR=0
            APP_TRANSPARENCY=0
            printf '  %s✓%s Solid mode selected\n\n' "$C_GRN" "$C_OFF"
            ;;
        *)
            WANT_BLUR=1
            printf '  %s✓%s Frosted glass selected\n' "$C_GRN" "$C_OFF"

            # Question 1: Popup & Menu blur (default: Yes)
            printf '  Enable blur behind popups, menus & top bar? %s[Y/n, default: Y]%s: ' "$C_DIM" "$C_OFF"
            read -r ans_popup || ans_popup="y"
            case "${ans_popup,,}" in
                n|no)
                    WANT_POPUP_BLUR=0
                    POPUP_BLUR_EXPLICIT=1
                    printf '  %s✓%s Popup blur disabled (flat menus)\n' "$C_GRN" "$C_OFF"
                    ;;
                *)
                    WANT_POPUP_BLUR=1
                    POPUP_BLUR_EXPLICIT=1
                    printf '  %s✓%s Popup blur enabled\n' "$C_GRN" "$C_OFF"
                    ;;
            esac

            # Question 2: Window blur & transparency (default: Yes)
            printf '  Enable blur & transparency for app windows (IDE, editor, files)? %s[Y/n, default: Y]%s: ' "$C_DIM" "$C_OFF"
            read -r ans_win || ans_win="y"
            case "${ans_win,,}" in
                n|no)
                    WANT_WINDOW_BLUR=0
                    WINDOW_BLUR_EXPLICIT=1
                    APP_TRANSPARENCY=0
                    APP_OPACITY=255
                    printf '  %s✓%s App window blur disabled (opaque windows)\n\n' "$C_GRN" "$C_OFF"
                    ;;
                *)
                    WANT_WINDOW_BLUR=1
                    WINDOW_BLUR_EXPLICIT=1
                    printf '\n  Choose Window Transparency Level:\n'
                    printf '    %s[1]%s 90%% Opacity %s[Default — balanced frosted glass (230)]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
                    printf '    %s[2]%s 82%% Opacity %s[Deep glass, more transparent (210)]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
                    printf '    %s[3]%s 94%% Opacity %s[Subtle glass, light translucency (240)]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
                    printf '  Choice [1-3 or %%, default: 1 (90%%)]: '
                    read -r ans_trans || ans_trans="1"
                    case "$ans_trans" in
                        2|82|82%|0.82|210)
                            APP_TRANSPARENCY=0.82
                            APP_OPACITY=210
                            printf '  %s✓%s Window transparency set to 82%% (Deep Glass, 210)\n\n' "$C_GRN" "$C_OFF"
                            ;;
                        3|94|94%|0.94|240)
                            APP_TRANSPARENCY=0.94
                            APP_OPACITY=240
                            printf '  %s✓%s Window transparency set to 94%% (Subtle Glass, 240)\n\n' "$C_GRN" "$C_OFF"
                            ;;
                        *)
                            APP_TRANSPARENCY=0.90
                            APP_OPACITY=230
                            printf '  %s✓%s Window transparency set to 90%% (Balanced Glass, 230)\n\n' "$C_GRN" "$C_OFF"
                            ;;
                    esac
                    ;;
            esac
            ;;
    esac

    # 3. Icons & Cursors
    printf '%sStep 3: Icons & Cursors%s\n' "$C_BLD" "$C_OFF"
    printf '  Icon Theme:\n'
    printf '    %s[1]%s Colloid %s[Default — matches accent (%s)]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$ACCENT" "$C_OFF"
    printf '    %s[2]%s Reversal %s[macOS-style circular icons]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
    printf '    %s[3]%s Keep current system icon theme\n' "$C_BLD" "$C_OFF"
    printf '  Choice [1-3, default 1]: '
    read -r ans_icon || ans_icon="1"
    case "$ans_icon" in
        2|reversal)
            ICONS="reversal-$ACCENT"
            WANT_ICONS=1
            printf '  %s✓%s Reversal icon theme selected (%s)\n' "$C_GRN" "$C_OFF" "$ACCENT"
            ;;
        3|keep|none)
            WANT_ICONS=0
            printf '  %s✓%s Keeping current icons\n' "$C_GRN" "$C_OFF"
            ;;
        *)
            ICONS="colloid"
            WANT_ICONS=1
            printf '  %s✓%s Colloid icon theme selected\n' "$C_GRN" "$C_OFF"
            ;;
    esac

    printf '  Cursor Theme:\n'
    printf '    %s[1]%s Stock Adwaita %s[Default — sharp and crisp]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
    printf '    %s[2]%s MacTahoe %s[macOS Tahoe style cursors]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
    printf '    %s[3]%s Keep current cursor theme\n' "$C_BLD" "$C_OFF"
    printf '  Choice [1-3, default 1]: '
    read -r ans_cursor || ans_cursor="1"
    case "$ans_cursor" in
        2|mactahoe)
            CURSORS="mactahoe"
            WANT_CURSORS=1
            printf '  %s✓%s MacTahoe cursors selected\n\n' "$C_GRN" "$C_OFF"
            ;;
        3|keep|none)
            WANT_CURSORS=0
            printf '  %s✓%s Keeping current cursors\n\n' "$C_GRN" "$C_OFF"
            ;;
        *)
            CURSORS="adwaita"
            WANT_CURSORS=1
            printf '  %s✓%s Adwaita cursors selected\n\n' "$C_GRN" "$C_OFF"
            ;;
    esac

    # 4. Extensions
    printf '%sStep 4: Shell Extensions%s\n' "$C_BLD" "$C_OFF"
    printf '  %sMandatory Core:%s User Themes, Blur My Shell, Open Bar\n' "$C_BLD" "$C_OFF"
    printf '  Install Custom OSD? (minimal pill bar for volume & brightness) %s[Y/n]%s: ' "$C_DIM" "$C_OFF"
    read -r ans_osd || ans_osd="y"
    case "${ans_osd,,}" in
        n|no) WANT_OSD=0; printf '  %s✓%s Keeping stock GNOME OSD\n' "$C_GRN" "$C_OFF" ;;
        *)    WANT_OSD=1; printf '  %s✓%s Custom OSD pill bar enabled\n' "$C_GRN" "$C_OFF" ;;
    esac

    printf '\n  Optional Extensions Package:\n'
    printf '    %s[1]%s Recommended Pack %s[Default — 6 curated essentials]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
    printf '        • AppIndicator Support (System tray icons for Steam, Discord, etc.)\n'
    printf '        • Space Bar (Workspace pill switcher in top bar)\n'
    printf '        • Clipboard Indicator (Clipboard history with search & Ctrl+Space)\n'
    printf '        • Magic Lamp Effect (macOS Genie window minimize effect)\n'
    printf '        • Just Perfection (GNOME UI tweaker & clean overview)\n'
    printf '        • GNOME UI Tune (300%% overview window thumbnails)\n'
    printf '    %s[2]%s Full Suite %s[All 14 extra extensions]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
    printf '    %s[3]%s Custom Selection %s[Pick extensions individually]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
    printf '    %s[4]%s Minimal %s[Core look only — no optional extensions]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
    printf '  Choice [1-4, default 1]: '
    read -r ans_pkg || ans_pkg="1"
    case "$ans_pkg" in
        2|full|all)
            WANT_EXTRAS=1
            EXT_EXTRA=("${EXT_EXTRA_ALL[@]}")
            printf '  %s✓%s Full Suite selected (14 extensions)\n\n' "$C_GRN" "$C_OFF"
            ;;
        3|custom)
            WANT_EXTRAS=1
            EXT_EXTRA=()
            printf '\n  %sSelect individual extensions:%s\n' "$C_BLD" "$C_OFF"
            for u in "${EXT_EXTRA_ALL[@]}"; do
                # Pre-select recommended as default yes, others as default no
                is_rec=0 def_hint="[y/N]" def_val="n"
                for r in "${EXT_EXTRA_RECOMMENDED[@]}"; do
                    if [ "$r" = "$u" ]; then is_rec=1; def_hint="[Y/n]"; def_val="y"; break; fi
                done
                printf '    Install %s %s? ' "$(ext_description "$u")" "$def_hint"
                read -r ans_ext || ans_ext="$def_val"
                [ -z "$ans_ext" ] && ans_ext="$def_val"
                case "${ans_ext,,}" in
                    y|yes) EXT_EXTRA+=("$u"); printf '      %s+ added%s\n' "$C_GRN" "$C_OFF" ;;
                    *)     printf '      %s- skipped%s\n' "$C_DIM" "$C_OFF" ;;
                esac
            done
            printf '  %s✓%s %d optional extensions selected\n\n' "$C_GRN" "$C_OFF" "${#EXT_EXTRA[@]}"
            ;;
        4|minimal|none)
            WANT_EXTRAS=0
            EXT_EXTRA=()
            printf '  %s✓%s Minimal core only selected\n\n' "$C_GRN" "$C_OFF"
            ;;
        *)
            WANT_EXTRAS=1
            EXT_EXTRA=("${EXT_EXTRA_RECOMMENDED[@]}")
            printf '  %s✓%s Recommended Pack selected (6 extensions)\n\n' "$C_GRN" "$C_OFF"
            ;;
    esac

    # 5. GDM Login Screen Theme
    if have gdm || have gdm3 || [ -e /usr/sbin/gdm3 ]; then
        printf '%sStep 5: GDM Login Screen Theme%s\n' "$C_BLD" "$C_OFF"
        printf '  Theme GDM login screen with Tahoe glass (dynamic desktop wallpaper sync, requires sudo)? [y/N]: '
        read -r ans_gdm || ans_gdm="n"
        case "${ans_gdm,,}" in
            y|yes)
                WANT_GDM=1
                printf '  %s✓%s GDM login screen theme will be installed (with live wallpaper sync)\n\n' "$C_GRN" "$C_OFF"
                ;;
            *)
                WANT_GDM=0
                printf '  %s-%s GDM login screen left at stock\n\n' "$C_DIM" "$C_OFF"
                ;;
        esac

        # 6. GDM Primary Monitor Sync
        printf '%sStep 6: GDM Primary Monitor Sync%s\n' "$C_BLD" "$C_OFF"
        printf '  Sync primary monitor to GDM login screen (good for multi-monitor / external displays, requires sudo)? [y/N]: '
        read -r ans_mon || ans_mon="n"
        case "${ans_mon,,}" in
            y|yes)
                WANT_GDM_MONITORS=1
                printf '  %s✓%s Primary monitor layout will be synced to GDM\n\n' "$C_GRN" "$C_OFF"
                ;;
            *)
                WANT_GDM_MONITORS=0
                printf '  %s-%s GDM monitor layout left at system default\n\n' "$C_DIM" "$C_OFF"
                ;;
        esac
    fi

    # 7. Summary & Confirmation
    blur_desc="Frosted Glass"
    [ "$WANT_BLUR" = 0 ] && blur_desc="Solid (No blur)"
    popup_desc="Enabled"
    [ "$WANT_POPUP_BLUR" = 0 ] && popup_desc="Disabled (Flat)"
    win_desc="Enabled"
    [ "$WANT_WINDOW_BLUR" = 0 ] && win_desc="Disabled"
    icon_desc="Colloid ($ACCENT)"
    [ "$WANT_ICONS" = 0 ] && icon_desc="Keep current"
    [[ "$ICONS" =~ ^reversal ]] && icon_desc="$ICONS"
    cursor_desc="$CURSORS"
    [ "$WANT_CURSORS" = 0 ] && cursor_desc="Keep current"
    osd_desc="Pill OSD"
    [ "$WANT_OSD" = 0 ] && osd_desc="Stock GNOME"
    gdm_desc="Stock (Untouched)"
    [ "$WANT_GDM" = 1 ] && gdm_desc="Tahoe Glass (syncs desktop wallpaper)"
    mon_desc="System default"
    [ "$WANT_GDM_MONITORS" = 1 ] && mon_desc="Synced from ~/.config/monitors.xml (multi-monitor fix)"

    trans_desc="0 (Opaque)"
    if [ -n "${APP_TRANSPARENCY:-}" ] && [ "$APP_TRANSPARENCY" != 0 ] && [ "$APP_TRANSPARENCY" != "0.0" ]; then
        pct="$(python3 -c "
v = '$APP_TRANSPARENCY'.rstrip('%')
f = float(v)
if f > 1.0: f = f / 100.0 if f <= 100 else f / 255.0
print(round(f * 100))
" 2>/dev/null || echo "$APP_TRANSPARENCY")"
        trans_desc="${pct}% Opacity (level ${APP_TRANSPARENCY}, actor: ${APP_OPACITY:-230})"
    fi

    cat <<EOF
${C_BLD}================ Configuration Summary ================${C_OFF}
  ${C_BLD}Accent Color:${C_OFF}        $ACCENT
  ${C_BLD}Blur Mode:${C_OFF}           $blur_desc
  ${C_BLD}Popup Blur:${C_OFF}          $popup_desc
  ${C_BLD}Window Blur:${C_OFF}         $win_desc
  ${C_BLD}App Translucency:${C_OFF}    $trans_desc
  ${C_BLD}Icon Theme:${C_OFF}          $icon_desc
  ${C_BLD}Cursor Theme:${C_OFF}        $cursor_desc
  ${C_BLD}Custom OSD:${C_OFF}          $osd_desc
  ${C_BLD}GDM Login Theme:${C_OFF}     $gdm_desc
  ${C_BLD}GDM Monitor Sync:${C_OFF}    $mon_desc
  ${C_BLD}Window Controls:${C_OFF}     Kept at system default
  ${C_BLD}Optional Extensions:${C_OFF} ${#EXT_EXTRA[@]} selected
${C_BLD}=======================================================${C_OFF}

EOF
    if ! confirm "Proceed with installation?" 1; then
        printf '\n  Installation cancelled.\n\n'
        exit 0
    fi
fi

case "$CURSORS" in
    adwaita|mactahoe) ;;
    *) die "unknown --cursors '$CURSORS' — pick adwaita or mactahoe" ;;
esac

if [ -z "$ICONS" ] && [ -r "$CONF_DIR/icon-pack" ]; then
    ICONS="$(cat "$CONF_DIR/icon-pack" 2>/dev/null || true)"
fi
ICONS="${ICONS:-colloid}"

if [ "${WANT_BLUR:-1}" = 0 ] || [ "${WANT_WINDOW_BLUR:-1}" = 0 ]; then
    APP_TRANSPARENCY=0
    APP_OPACITY=255
elif [ -z "$APP_TRANSPARENCY" ]; then
    if [ -r "$CONF_DIR/app-transparency" ]; then
        APP_TRANSPARENCY="$(cat "$CONF_DIR/app-transparency" 2>/dev/null || true)"
    else
        APP_TRANSPARENCY=0.90
    fi
fi
if [ -z "$APP_OPACITY" ] && [ -r "$CONF_DIR/app-opacity" ]; then
    APP_OPACITY="$(cat "$CONF_DIR/app-opacity" 2>/dev/null || true)"
fi

if [ -n "$APP_TRANSPARENCY" ]; then
    norm_res="$(python3 - "${APP_TRANSPARENCY:-0}" "${APP_OPACITY:-}" <<'PY'
import sys
raw_t = sys.argv[1].strip() if len(sys.argv) > 1 else "0"
raw_o = sys.argv[2].strip() if len(sys.argv) > 2 else ""

if raw_t in ("0", "0.0", "0%", "off", "none", "no"):
    print("0\n255")
    sys.exit(0)

val = raw_t.rstrip("%")
try:
    v = float(val) if val else 0.90
    if v > 100:
        op = max(0, min(255, int(round(v))))
        frac = round(op / 255.0, 2)
    elif v > 1.0:
        frac = round(v / 100.0, 2)
        op = max(0, min(255, int(round(frac * 255.0))))
    elif v > 0.0:
        frac = round(v, 2)
        op = max(0, min(255, int(round(frac * 255.0))))
    else:
        frac = 0.0
        op = 255
except Exception:
    frac = 0.90
    op = 230

if op in (209, 210) or frac == 0.82:
    op, frac = 210, 0.82
elif op in (229, 230) or frac == 0.90:
    op, frac = 230, 0.90
elif op in (239, 240) or frac == 0.94:
    op, frac = 240, 0.94

if raw_o:
    try:
        op = max(0, min(255, int(float(raw_o))))
    except Exception:
        pass

if frac < 0.70 and frac != 0.0:
    frac = 0.70
if frac > 1.00:
    frac = 1.00

print(f"{frac:.2f}\n{op}")
PY
)"
    APP_TRANSPARENCY="$(printf '%s\n' "$norm_res" | head -n 1)"
    APP_OPACITY="$(printf '%s\n' "$norm_res" | tail -n 1)"
fi
APP_TRANSPARENCY="${APP_TRANSPARENCY:-0}"
APP_OPACITY="${APP_OPACITY:-255}"

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

# --no-blur does not install Blur My Shell at all, so asking it to blur behind
# windows cannot be honoured. Rejected rather than silently resolved either way:
# whichever of the two we picked would be the opposite of what half the users
# writing that line meant, and apply_app_blur would otherwise write a dconf key
# for an extension this mode deliberately leaves out.
if [ "$WANT_BLUR" != 1 ] && [ "$WANT_WINDOW_BLUR" = 1 ]; then
    die "--no-blur and --window-blur contradict each other — --no-blur leaves Blur My Shell out entirely, so there is nothing to blur behind a window. Pick one."
fi

printf '\n%s  aura-glass%s  %saccent %s%s\n' \
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
if [ "$WANT_BLUR" = 1 ]; then
    install_rounded_blur
else
    step "Blur"
    skip "no blur (--no-blur) — opaque surfaces, and Blur My Shell left out"
fi
if [ "$WANT_ICONS" = 1 ]; then install_icons; else step "Icons"; skip "left alone (--no-icons)"; fi
if [ "$WANT_CURSORS" = 1 ]; then install_cursors; else step "Cursors"; skip "left alone (--no-cursors)"; fi
load_dconf
install_css
apply_gsettings
install_icon_sync
flatpak_override
install_panel_blur_unit
enable_extensions
if [ "$WANT_GDM_MONITORS" = 1 ]; then
    sync_gdm_monitors
    [ "$WANT_GDM" != 1 ] && install_gdm_sync_unit
fi
if [ "$WANT_GDM" = 1 ]; then
    install_gdm
fi
finish
