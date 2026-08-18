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
# shellcheck source=lib/steps-modes.sh
. "$REPO_ROOT/lib/steps-modes.sh"
# shellcheck source=lib/steps-css.sh
. "$REPO_ROOT/lib/steps-css.sh"
# shellcheck source=lib/steps-dconf.sh
. "$REPO_ROOT/lib/steps-dconf.sh"
# shellcheck source=lib/steps-integration.sh
. "$REPO_ROOT/lib/steps-integration.sh"
# shellcheck source=lib/steps-gdm.sh
. "$REPO_ROOT/lib/steps-gdm.sh"
# shellcheck source=lib/steps-gui.sh
. "$REPO_ROOT/lib/steps-gui.sh"
# shellcheck source=lib/steps-wizard.sh
. "$REPO_ROOT/lib/steps-wizard.sh"
# Values written down in more than one place live here, so that the copy in a
# stylesheet and the copy in a dconf key cannot drift apart unnoticed.
# tools/check-tokens.sh asserts they still agree.
# shellcheck source=tokens/tokens.sh
. "$REPO_ROOT/tokens/tokens.sh"

ACCENT=""          # empty = remembered choice, then $ACCENT_DEFAULT
ACCENT_DEFAULT="purple"
WANT_EXTRAS=1
EXT_LIST=""        # comma-separated UUIDs, replacing the pack. Empty = a pack
EXT_LIST_EXPLICIT=""
WANT_ICONS=1
WANT_CURSORS=1
WANT_DEPS=1
WANT_OSD=1
WANT_PANEL_BLUR_FIX=1
PANEL_BLUR_FIX_EXPLICIT=""
WANT_GDM=0
WANT_GDM_MONITORS=0
GDM_BG="default"
WANT_BMS_GIT=1
WANT_BLUR=1
GLASS_MODE=""            # empty = the memo, then derived from the flags
GLASS_MODE_EXPLICIT=""
BLUR_EXPLICIT=""         # --blur / --no-blur were typed, so a mode must not move them
WANT_STYLING=1           # 0 = the theme stands down (solid mode)
VALID_GLASS_MODES="frosted transparent solid"
WANT_WINDOW_BLUR=1
WINDOW_BLUR_EXPLICIT=""
APP_BLUR_SCOPE="gtk"     # gtk (default, whitelisted GTK/GNOME apps) | all
APP_BLUR_SCOPE_EXPLICIT=""
APP_BLUR_ALLOW=""        # comma-separated wm_class patterns
APP_BLUR_ALLOW_EXPLICIT=""
APP_BLUR_BLOCK=""
APP_BLUR_BLOCK_EXPLICIT=""
WANT_POPUP_BLUR=1
POPUP_BLUR_EXPLICIT=""
WINDOW_BUTTONS=""        # empty = leave the titlebar as the system has it
WINDOW_BUTTONS_EXPLICIT=""
WANT_ROUNDED_BLUR=1
APP_TRANSPARENCY=""   # empty = remembered choice, then off (e.g. 0.90 / 90%)
APP_TRANSPARENCY_EXPLICIT=""
APP_OPACITY=""        # empty = remembered choice, then 255 (e.g. 230)
APP_OPACITY_EXPLICIT=""
CURSORS=""          # empty = remembered choice, then adwaita | mactahoe
CURSORS_EXPLICIT=""
ICONS=""            # empty = remembered choice, then colloid
ICONS_EXPLICIT=""
GRAIN=""          # empty keeps the preset's value, or the remembered choice
BLUR_STRENGTH=""    # empty = remembered choice, then the tuned radii (100)
APP_TINT_COLOR=""   # empty = remembered choice, then black (#000000)
SHELL_TINT_COLOR="" # empty = remembered choice, then black (#000000)
RADIUS_PRESET=""       # empty = remembered choice, then default
RADIUS_PRESET_EXPLICIT=""
RADIUS_CUSTOM=""       # seven comma-separated pixel values, in RADIUS_TOKENS order
RADIUS_CUSTOM_EXPLICIT=""
SETTINGS_ONLY=0
DEPS_ONLY=0
WANT_GUI=1
WANT_UPDATE_CHECK=1
UPDATE_CHECK_EXPLICIT=""
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
    --extensions LIST comma-separated extension UUIDs to install instead of a
                      pack, e.g. 'space-bar@luchrioh,Vitals@CoreCoding.com'.
                      Each must be one --all-extras would install. An empty list
                      is the same as --no-extras. This is what the setup
                      wizard's per-extension list sends
    --grain N         film grain over blurred surfaces, 0-1. Default is 0
    --no-grain        no grain at all (same as --grain 0, and the default)
    --blur-strength P how far every blur reaches, as a percentage of the tuned
                      radii: 25-200, 100 is the tuned look (remembered)
    --app-tint-color HEX
                      the colour a translucent app window is darkened toward,
                      e.g. #101820. Default #000000 (remembered)
    --shell-tint-color HEX
                      the same, for the panel, menus and notifications.
                      Default #000000 (remembered)
    --radius-preset P corner rounding for windows, menus, dialogs and
                      notifications. One of: $RADIUS_PRESETS (default: default,
                      and remembered for later runs)
    --radius-custom LIST
                      seven corner radii of your own, in pixels, comma separated:
                      window,menu,quick-settings,notification,dialog,popup,osd
                      (e.g. 30,26,33,20,20,20,12). Each is bounded by what the
                      presets already cover. Overrides --radius-preset
    --panel-blur-fix  agent that rebuilds Blur My Shell's panel blur on layout change (default: on)
    --no-panel-blur-fix skip the panel blur rebuild agent
    --icons WHICH     colloid (default) or reversal, either bare to follow
                      --accent or with a colour of its own: colloid-teal,
                      reversal-purple. Colloid takes accent names, Reversal its
                      own ($VALID_REVERSAL). Or original, for whatever was set
                      before aura-glass first ran here.
                      Remembered for later runs
    --cursors WHICH   adwaita (default, ships with GNOME), mactahoe, or original
                      (whatever was set before aura-glass first ran here)
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
    --app-blur-allow LIST
                      comma-separated wm_class patterns to blur in GTK/GNOME mode,
                      replacing the shipped list (e.g. 'org.gnome.Nautilus,*term*').
                      Wildcards allowed. Remembered for later runs
    --app-blur-block LIST
                      comma-separated wm_class patterns to exclude in all-apps
                      mode, replacing the shipped list. Remembered for later runs
    --deps-only       install the missing command-line dependencies and stop.
                      Needs root, so it is the one step the settings window
                      hands to a terminal rather than running itself
    --window-buttons WHICH
                      titlebar buttons: close (close alone) or all (minimize,
                      maximize and close). Left as the system has it unless given
    --window-blur     blur behind app windows (default: on behind GTK/GNOME apps)
    --gtk-apps-blur   blur behind GTK / GNOME applications only (Files, Settings, Terminal - default, low CPU)
    --all-apps-blur   blur behind all application windows (heavy on CPU/GPU)
    --no-window-blur  keep window blur off (opaque windows)
    --glass-mode M    frosted (blur behind windows and popups), transparent
                      (translucent windows, no window blur) or solid (the theme
                      stands down: no styling, stock shell, the extensions it
                      enabled switched off and their settings left alone).
                      Remembered; each mode keeps its own opacity and tint
    --no-blur         solid mode: no blur anywhere, opaque surfaces instead of
                      translucent ones (best for low-end GPUs or battery saver)
    --no-rounded-blur skip gnome-rounded-blur library (popup blur falls back to static)
    --gdm             theme the GDM login screen with blurred Aura Glass style (requires sudo)
    --gdm-background PATH
                      set custom background image for GDM (default: blurred wallpaper)
    --no-gdm          do not theme the GDM login screen (default)
    --gdm-monitors    sync primary monitor layout to GDM login screen (good for multi-monitor, requires sudo)
    --no-gdm-monitors keep default GDM monitor layout (default)
    --no-gui          skip the aura-glass-settings window (installed by default
                      where PyGObject and libadwaita are present)
    --no-update-check skip the daily check for a newer release. The check asks
                      the git remote for its tags and notifies once per release;
                      it never installs anything on its own
    --no-icons        keep your current icon theme
    --no-cursors      keep your current cursor theme
    --settings-only   retune an existing install and nothing else: reapply the
                      dconf preset, the CSS and the gsettings, leaving the theme,
                      the extensions, the icons and the cursors alone. Needs no
                      network and no root. This is what aura-glass-settings runs
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

# A function rather than a bare loop, because it is run twice: once over this
# script's own argv, and again over whatever the graphical setup wizard settled
# on. That is what makes the window a front end for the flags rather than a
# second way to configure anything — it produces a command line, and the command
# line is parsed here by the same code that parses a hand-typed one.
parse_flags() {
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
        --extensions)    EXT_LIST="${2:-}"; EXT_LIST_EXPLICIT=1; EXPLICIT_FLAGS=1; shift 2 ;;
        --extensions=*)  EXT_LIST="${1#*=}"; EXT_LIST_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --full)          WANT_EXTRAS=1; EXT_EXTRA=("${EXT_EXTRA_ALL[@]}"); WANT_ICONS=1; WANT_CURSORS=1
                         WANT_OSD=1; WANT_PANEL_BLUR_FIX=1; EXPLICIT_FLAGS=1; shift ;;
        --grain)         GRAIN="${2:-}"; EXPLICIT_FLAGS=1; shift 2 ;;
        --grain=*)       GRAIN="${1#*=}"; EXPLICIT_FLAGS=1; shift ;;
        --no-grain)      GRAIN=0; EXPLICIT_FLAGS=1; shift ;;
        --blur-strength) BLUR_STRENGTH="${2:-100}"; EXPLICIT_FLAGS=1; shift 2 ;;
        --blur-strength=*) BLUR_STRENGTH="${1#*=}"; EXPLICIT_FLAGS=1; shift ;;
        --app-tint-color) APP_TINT_COLOR="${2:-}"; EXPLICIT_FLAGS=1; shift 2 ;;
        --app-tint-color=*) APP_TINT_COLOR="${1#*=}"; EXPLICIT_FLAGS=1; shift ;;
        --shell-tint-color) SHELL_TINT_COLOR="${2:-}"; EXPLICIT_FLAGS=1; shift 2 ;;
        --shell-tint-color=*) SHELL_TINT_COLOR="${1#*=}"; EXPLICIT_FLAGS=1; shift ;;
        --radius-custom) RADIUS_CUSTOM="${2:-}"; RADIUS_CUSTOM_EXPLICIT=1; EXPLICIT_FLAGS=1; shift 2 ;;
        --radius-custom=*) RADIUS_CUSTOM="${1#*=}"; RADIUS_CUSTOM_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --radius-preset) RADIUS_PRESET="${2:-}"; RADIUS_PRESET_EXPLICIT=1; EXPLICIT_FLAGS=1; shift 2 ;;
        --radius-preset=*)
                         RADIUS_PRESET="${1#*=}"; RADIUS_PRESET_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --panel-blur-fix)    WANT_PANEL_BLUR_FIX=1; PANEL_BLUR_FIX_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --no-panel-blur-fix) WANT_PANEL_BLUR_FIX=0; PANEL_BLUR_FIX_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --cursors)       CURSORS="${2:-}"; CURSORS_EXPLICIT=1; EXPLICIT_FLAGS=1; shift 2 ;;
        --cursors=*)     CURSORS="${1#*=}"; CURSORS_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --icons)         ICONS="${2:-}"; ICONS_EXPLICIT=1; EXPLICIT_FLAGS=1; shift 2 ;;
        --icons=*)       ICONS="${1#*=}"; ICONS_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --osd)           WANT_OSD=1; EXPLICIT_FLAGS=1; shift ;;
        --no-osd)        WANT_OSD=0; EXPLICIT_FLAGS=1; shift ;;
        --bms-git)       WANT_BMS_GIT=1; EXPLICIT_FLAGS=1; shift ;;
        --no-bms-git)    WANT_BMS_GIT=0; WANT_POPUP_BLUR=0
                         POPUP_BLUR_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --popup-blur)    WANT_POPUP_BLUR=1; WANT_BMS_GIT=1
                         POPUP_BLUR_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --no-popup-blur) WANT_POPUP_BLUR=0; POPUP_BLUR_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --glass-mode)    GLASS_MODE="${2:-}"; GLASS_MODE_EXPLICIT=1; EXPLICIT_FLAGS=1; shift 2 ;;
        --glass-mode=*)  GLASS_MODE="${1#*=}"; GLASS_MODE_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --blur)          WANT_BLUR=1; BLUR_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --all-apps-blur|--all-app-blur)
                         WANT_WINDOW_BLUR=1; WINDOW_BLUR_EXPLICIT=1; APP_BLUR_SCOPE="all"; APP_BLUR_SCOPE_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --gtk-apps-blur|--gtk-app-blur)
                         WANT_WINDOW_BLUR=1; WINDOW_BLUR_EXPLICIT=1; APP_BLUR_SCOPE="gtk"; APP_BLUR_SCOPE_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --app-blur-scope)
                         APP_BLUR_SCOPE="${2:-gtk}"; APP_BLUR_SCOPE_EXPLICIT=1; EXPLICIT_FLAGS=1; shift 2 ;;
        --app-blur-scope=*)
                         APP_BLUR_SCOPE="${1#*=}"; APP_BLUR_SCOPE_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --app-blur-allow) APP_BLUR_ALLOW="${2:-}"; APP_BLUR_ALLOW_EXPLICIT=1; EXPLICIT_FLAGS=1; shift 2 ;;
        --app-blur-allow=*) APP_BLUR_ALLOW="${1#*=}"; APP_BLUR_ALLOW_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --app-blur-block) APP_BLUR_BLOCK="${2:-}"; APP_BLUR_BLOCK_EXPLICIT=1; EXPLICIT_FLAGS=1; shift 2 ;;
        --app-blur-block=*) APP_BLUR_BLOCK="${1#*=}"; APP_BLUR_BLOCK_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --window-blur)   WANT_WINDOW_BLUR=1; WINDOW_BLUR_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --no-window-blur) WANT_WINDOW_BLUR=0; WINDOW_BLUR_EXPLICIT=1; APP_BLUR_SCOPE="none"; APP_BLUR_SCOPE_EXPLICIT=1; [ -z "$APP_TRANSPARENCY_EXPLICIT" ] && APP_TRANSPARENCY=0.95; EXPLICIT_FLAGS=1; shift ;;
        --no-blur)       WANT_BLUR=0; BLUR_EXPLICIT=1; WANT_POPUP_BLUR=0; POPUP_BLUR_EXPLICIT=1
                         WANT_WINDOW_BLUR=0; WINDOW_BLUR_EXPLICIT=1
                         WANT_ROUNDED_BLUR=0; EXPLICIT_FLAGS=1; shift ;;
        --rounded-blur)      WANT_ROUNDED_BLUR=1; EXPLICIT_FLAGS=1; shift ;;
        --no-rounded-blur)   WANT_ROUNDED_BLUR=0; EXPLICIT_FLAGS=1; shift ;;
        --app-transparency|--window-opacity|--window-transparency)
                         APP_TRANSPARENCY="${2:-$TOKEN_APP_TRANSPARENCY_SHIPPED}"; APP_TRANSPARENCY_EXPLICIT=1; EXPLICIT_FLAGS=1; APP_OPACITY_EXPLICIT=1; shift 2 ;;
        --app-transparency=*|--window-opacity=*|--window-transparency=*)
                         APP_TRANSPARENCY="${1#*=}"; APP_TRANSPARENCY_EXPLICIT=1; EXPLICIT_FLAGS=1; APP_OPACITY_EXPLICIT=1; shift ;;
        --no-app-transparency|--no-window-opacity|--no-window-transparency)
                         APP_TRANSPARENCY=0; APP_TRANSPARENCY_EXPLICIT=1; APP_OPACITY=255; EXPLICIT_FLAGS=1; APP_OPACITY_EXPLICIT=1; shift ;;
        --gdm)           WANT_GDM=1; EXPLICIT_FLAGS=1; shift ;;
        --no-gdm)        WANT_GDM=0; EXPLICIT_FLAGS=1; shift ;;
        --gdm-monitors|--sync-monitors) WANT_GDM_MONITORS=1; EXPLICIT_FLAGS=1; shift ;;
        --no-gdm-monitors) WANT_GDM_MONITORS=0; EXPLICIT_FLAGS=1; shift ;;
        --gdm-background) GDM_BG="${2:-default}"; WANT_GDM=1; EXPLICIT_FLAGS=1; shift 2 ;;
        --gdm-background=*) GDM_BG="${1#*=}"; WANT_GDM=1; EXPLICIT_FLAGS=1; shift ;;
        --gui)           WANT_GUI=1; EXPLICIT_FLAGS=1; shift ;;
        --no-gui)        WANT_GUI=0; EXPLICIT_FLAGS=1; shift ;;
        --update-check)  WANT_UPDATE_CHECK=1; UPDATE_CHECK_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --no-update-check) WANT_UPDATE_CHECK=0; UPDATE_CHECK_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --no-icons)      WANT_ICONS=0; EXPLICIT_FLAGS=1; shift ;;
        --no-cursors)    WANT_CURSORS=0; EXPLICIT_FLAGS=1; shift ;;
        --no-wm-buttons|--wm-buttons) # Deprecated, and a no-op. --window-buttons
                         # replaces both: these two never said which layout they
                         # meant, so there was nothing to keep them doing.
                         EXPLICIT_FLAGS=1; shift ;;
        --window-buttons) WINDOW_BUTTONS="${2:-}"; WINDOW_BUTTONS_EXPLICIT=1; EXPLICIT_FLAGS=1; shift 2 ;;
        --window-buttons=*) WINDOW_BUTTONS="${1#*=}"; WINDOW_BUTTONS_EXPLICIT=1; EXPLICIT_FLAGS=1; shift ;;
        --settings-only) SETTINGS_ONLY=1; WANT_DEPS=0; EXPLICIT_FLAGS=1; shift ;;
        --deps-only)     DEPS_ONLY=1; EXPLICIT_FLAGS=1; shift ;;
        --no-deps)       WANT_DEPS=0; EXPLICIT_FLAGS=1; shift ;;
        --force)         FORCE=1; EXPLICIT_FLAGS=1; shift ;;
        -y|--yes)        ASSUME_YES=1; EXPLICIT_FLAGS=1; shift ;;
        -n|--dry-run)    DRY_RUN=1; EXPLICIT_FLAGS=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               usage; die "unknown option: $1" ;;
    esac
    done
}

parse_flags "$@"

# Resolve remembered accent or default
if [ -z "$ACCENT" ] && [ -r "$CONF_DIR/accent" ]; then
    ACCENT="$(cat "$CONF_DIR/accent" 2>/dev/null || true)"
fi
ACCENT="${ACCENT:-$ACCENT_DEFAULT}"

# Interactive setup wizard when running without flags in an interactive terminal.
#
# There are two of them and they ask the same questions: gui/aura_glass_setup_
# wizard.py in a window, and the text one below when no window is available. The
# window is tried first and falls back here for any reason at all — no display,
# no PyGObject, a declined package install, a crash — so an install is never
# blocked on a toolkit. Cancelling is the one answer that stops it, because that
# is a person saying no rather than a machine being unable to ask.
#
#   ┌─ PARITY ────────────────────────────────────────────────────────────────┐
#   │ Any question added below must also be added to the window, and any       │
#   │ question added to the window must also be added below. They are two      │
#   │ front ends for one flag surface; a question in only one of them is a     │
#   │ setting that half the users on half the machines are never offered.      │
#   └──────────────────────────────────────────────────────────────────────────┘
WIZARD_RC=3          # 3 = never attempted, so the text wizard below stays out
if { [ "$EXPLICIT_FLAGS" = 0 ] || [ "$FORCE_INTERACTIVE" = 1 ]; } && [ "$ASSUME_YES" = 0 ] && [ -t 0 ]; then
    WIZARD_RC=0
    run_setup_wizard || WIZARD_RC=$?
    case "$WIZARD_RC" in
        0) parse_flags "${WIZARD_ARGS[@]}" ;;
        1) printf '\n  Installation cancelled.\n\n'; exit 0 ;;
    esac
fi

# The same questions, asked here, when nothing could ask them in a window.
if [ "$WIZARD_RC" = 2 ]; then
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

            # Question 2: App window blur target scope
            printf '\n  App Window Blur Target:\n'
            printf '    %s[1]%s GTK / GNOME Applications only %s[Default — Files, Settings, Terminal (Low CPU)]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
            printf '    %s[2]%s All Applications %s[Heavy — blurs browsers, Electron, Discord]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
            printf '    %s[3]%s No blur on windows %s[95%% subtle translucency, crisp text, 0 CPU overhead]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
            printf '  Choice [1-3, default: 1]: '
            read -r ans_scope || ans_scope="1"
            case "$ans_scope" in
                3|disabled|off|none|no|n|no-blur)
                    WANT_WINDOW_BLUR=0
                    WINDOW_BLUR_EXPLICIT=1
                    APP_BLUR_SCOPE="none"
                    APP_BLUR_SCOPE_EXPLICIT=1
                    APP_TRANSPARENCY=0.95
                    APP_OPACITY=255
                    printf '  %s✓%s Window blur disabled; app transparency set to 95%% (readable text)\n\n' "$C_GRN" "$C_OFF"
                    ;;
                2|all|every)
                    WANT_WINDOW_BLUR=1
                    WINDOW_BLUR_EXPLICIT=1
                    APP_BLUR_SCOPE="all"
                    APP_BLUR_SCOPE_EXPLICIT=1
                    printf '  %s✓%s Window blur enabled for ALL applications (Heavy CPU/GPU)\n' "$C_GRN" "$C_OFF"
                    ;;
                *)
                    WANT_WINDOW_BLUR=1
                    WINDOW_BLUR_EXPLICIT=1
                    APP_BLUR_SCOPE="gtk"
                    APP_BLUR_SCOPE_EXPLICIT=1
                    printf '  %s✓%s Window blur enabled for GTK / GNOME applications only\n' "$C_GRN" "$C_OFF"
                    ;;
            esac

            if [ "$WANT_WINDOW_BLUR" = 1 ]; then
                printf '\n  Choose Window Transparency Level:\n'
                printf '    %s[1]%s 90%% Opacity %s[Default — balanced frosted glass (230)]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
                printf '    %s[2]%s 82%% Opacity %s[Deep glass, more transparent (210)]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
                printf '    %s[3]%s 95%% Opacity %s[Subtle glass, crisp and readable text (242)]%s\n' "$C_BLD" "$C_OFF" "$C_DIM" "$C_OFF"
                printf '  Choice [1-3 or %%, default: 1 (90%%)]: '
                read -r ans_trans || ans_trans="1"
                case "$ans_trans" in
                    2|82|82%|0.82|210)
                        APP_TRANSPARENCY=0.82
                        APP_OPACITY=210
                        printf '  %s✓%s Window transparency set to 82%% (Deep Glass, 210)\n\n' "$C_GRN" "$C_OFF"
                        ;;
                    3|95|95%|0.95|242|94|94%|0.94|240)
                        APP_TRANSPARENCY=0.95
                        APP_OPACITY=242
                        printf '  %s✓%s Window transparency set to 95%% (Subtle Glass, 242)\n\n' "$C_GRN" "$C_OFF"
                        ;;
                    *)
                        APP_TRANSPARENCY=0.90
                        APP_OPACITY=230
                        printf '  %s✓%s Window transparency set to 90%% (Balanced Glass, 230)\n\n' "$C_GRN" "$C_OFF"
                        ;;
                esac
            fi
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
            # Bare, so accent_to_reversal picks a colour Reversal actually ships.
            # "reversal-$ACCENT" was three broken answers out of nine here.
            ICONS="reversal"
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
        printf '  Theme GDM login screen with Aura Glass (dynamic desktop wallpaper sync, requires sudo)? [y/N]: '
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
    win_desc="GTK / GNOME Applications only (Low CPU)"
    [ "$APP_BLUR_SCOPE" = "all" ] && win_desc="All Applications (Heavy)"
    [ "$WANT_WINDOW_BLUR" = 0 ] && win_desc="Disabled (Opaque)"
    icon_desc="Colloid ($ACCENT)"
    [ "$WANT_ICONS" = 0 ] && icon_desc="Keep current"
    [[ "$ICONS" =~ ^reversal ]] && icon_desc="$ICONS"
    cursor_desc="$CURSORS"
    [ "$WANT_CURSORS" = 0 ] && cursor_desc="Keep current"
    osd_desc="Pill OSD"
    [ "$WANT_OSD" = 0 ] && osd_desc="Stock GNOME"
    gdm_desc="Stock (Untouched)"
    [ "$WANT_GDM" = 1 ] && gdm_desc="Aura Glass (syncs desktop wallpaper)"
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

# --extensions replaces the pack with a list of your own, which is what the setup
# wizard's per-extension switches send: a pack name cannot say "the recommended
# six, but not the magic lamp".
#
# Every UUID is checked against what --all-extras would install rather than taken
# on trust. A misspelled one would otherwise be looked for on the extensions site,
# not found, and reported as that extension being unavailable — which reads as
# upstream having removed it rather than as a typo here.
if [ -n "$EXT_LIST_EXPLICIT" ]; then
    EXT_EXTRA=()
    while IFS= read -r ext_uuid; do
        [ -n "$ext_uuid" ] || continue
        case " ${EXT_EXTRA_ALL[*]} " in
            *" $ext_uuid "*) EXT_EXTRA+=("$ext_uuid") ;;
            *) die "unknown --extensions UUID '$ext_uuid' — it is not one of the ${#EXT_EXTRA_ALL[@]} that --all-extras installs" ;;
        esac
    done < <(printf '%s\n' "$EXT_LIST" | tr ',' '\n')
    # An empty list is a minimal install said the long way round, and reaching
    # enable_extensions with WANT_EXTRAS=1 and nothing to enable would be a step
    # that announces itself and does nothing.
    if [ "${#EXT_EXTRA[@]}" -eq 0 ]; then WANT_EXTRAS=0; else WANT_EXTRAS=1; fi
fi

if [ -z "$CURSORS" ] && [ -r "$CONF_DIR/cursor-pack" ]; then
    CURSORS="$(cat "$CONF_DIR/cursor-pack" 2>/dev/null || true)"
fi
CURSORS="${CURSORS:-adwaita}"
case "$CURSORS" in
    adwaita|mactahoe|original) ;;
    *) die "unknown --cursors '$CURSORS' — pick adwaita, mactahoe or original" ;;
esac

if [ -z "$ICONS" ] && [ -r "$CONF_DIR/icon-pack" ]; then
    ICONS="$(cat "$CONF_DIR/icon-pack" 2>/dev/null || true)"
fi
ICONS="${ICONS:-colloid}"

resolve_glass_mode
apply_glass_mode

if [ "${WANT_BLUR:-1}" = 0 ]; then
    APP_TRANSPARENCY=0
    APP_OPACITY=255
elif [ -z "$APP_TRANSPARENCY" ]; then
    if [ -r "$CONF_DIR/app-transparency" ]; then
        APP_TRANSPARENCY="$(cat "$CONF_DIR/app-transparency" 2>/dev/null || true)"
    elif [ "${WANT_WINDOW_BLUR:-1}" = 0 ]; then
        APP_TRANSPARENCY=0.95
    else
        APP_TRANSPARENCY=0.90
    fi
fi
# Only when this run is not itself deciding the level. --app-transparency sets
# APP_OPACITY_EXPLICIT precisely so that the actor opacity follows the level it
# was given, and reading the memo here defeated that: the normalisation below
# takes a non-empty $APP_OPACITY as final, so `--app-transparency 0.88` rewrote
# the stylesheet to 0.88 while leaving the actor at the remembered 230.
#
# The two are the same setting seen twice — the alpha inside a GTK4 window, and
# the compositor-level opacity that is all an Electron or browser window has —
# so they drifting apart means one kind of window is more transparent than the
# other for no reason a user could see. It went unnoticed while the only levels
# anyone passed were the three buckets, whose remembered opacity already matched.
if [ -z "$APP_OPACITY" ] && [ -z "$APP_OPACITY_EXPLICIT" ] \
   && [ -r "$CONF_DIR/app-opacity" ]; then
    APP_OPACITY="$(cat "$CONF_DIR/app-opacity" 2>/dev/null || true)"
fi
if [ -z "$APP_BLUR_SCOPE_EXPLICIT" ] && [ -r "$CONF_DIR/app-blur-scope" ]; then
    APP_BLUR_SCOPE="$(cat "$CONF_DIR/app-blur-scope" 2>/dev/null || true)"
fi
APP_BLUR_SCOPE="${APP_BLUR_SCOPE:-gtk}"

# No default: empty means the key is not ours to write. apply_window_buttons
# reads the memo itself, so this only has to validate what a flag asked for —
# and validating here rather than there means a typo fails before the install
# has written anything, like --radius-preset below.
if [ -n "$WINDOW_BUTTONS_EXPLICIT" ]; then
    case "$WINDOW_BUTTONS" in
        close|all) ;;
        *) die "unknown --window-buttons '$WINDOW_BUTTONS' — pick close or all" ;;
    esac
fi

# Asking for seven values of your own is asking for the preset to be `custom`.
# One flag decides both so they cannot be remembered disagreeing with each other.
[ -n "$RADIUS_CUSTOM_EXPLICIT" ] && { RADIUS_PRESET="custom"; RADIUS_PRESET_EXPLICIT=1; }

if [ -z "$PANEL_BLUR_FIX_EXPLICIT" ] && [ -r "$CONF_DIR/panel-blur-fix" ]; then
    WANT_PANEL_BLUR_FIX="$(cat "$CONF_DIR/panel-blur-fix" 2>/dev/null || true)"
fi
WANT_PANEL_BLUR_FIX="${WANT_PANEL_BLUR_FIX:-1}"

if [ -z "$RADIUS_PRESET_EXPLICIT" ] && [ -r "$CONF_DIR/radius-preset" ]; then
    RADIUS_PRESET="$(cat "$CONF_DIR/radius-preset" 2>/dev/null || true)"
fi
RADIUS_PRESET="${RADIUS_PRESET:-default}"

if [ "$RADIUS_PRESET" = custom ]; then
    # The seven values, from the flag or from the memo the last one wrote.
    if [ -z "$RADIUS_CUSTOM_EXPLICIT" ] && [ -r "$CONF_DIR/radius-custom" ]; then
        RADIUS_CUSTOM="$(cat "$CONF_DIR/radius-custom" 2>/dev/null || true)"
    fi
    [ -n "$RADIUS_CUSTOM" ] \
        || die "--radius-preset custom needs seven values — pass --radius-custom"

    # Bounded per surface rather than free. The ranges are the ones the curated
    # presets already cover, except the OSD's ceiling, which is lower than
    # arithmetic would suggest and is documented at TOKEN_RADIUS_OSD.
    radius_bounds
    _rc_names="WINDOW MENU QUICK_SETTINGS NOTIFICATION DIALOG POPUP OSD"
    _rc_i=1
    for _rc_name in $_rc_names; do
        _rc_val="$(printf '%s' "$RADIUS_CUSTOM" | cut -d, -f"$_rc_i")"
        case "$_rc_val" in
            ''|*[!0-9]*) die "--radius-custom needs seven whole numbers of pixels, got '$RADIUS_CUSTOM'" ;;
        esac
        eval "_rc_min=\$RADIUS_MIN_$_rc_name; _rc_max=\$RADIUS_MAX_$_rc_name"
        if [ "$_rc_val" -lt "$_rc_min" ] || [ "$_rc_val" -gt "$_rc_max" ]; then
            die "--radius-custom: $_rc_name is $_rc_val, outside $_rc_min-$_rc_max"
        fi
        eval "TOKEN_RADIUS_$_rc_name=\$_rc_val"
        _rc_i=$((_rc_i + 1))
    done
    # An eighth field is a typo, not a value that happens not to be read.
    [ -z "$(printf '%s' "$RADIUS_CUSTOM" | cut -d, -f8)" ] \
        || die "--radius-custom takes seven values, got more"
else
    # Sets the seven TOKEN_RADIUS_* values for this run, which is what
    # apply_radius_css and apply_radius_dconf both read. Validated here rather
    # than at the point of use so a typo fails before anything has been written,
    # and rejected rather than defaulted: a --radius-preset that silently
    # installed the shipped look would be indistinguishable from the flag
    # working.
    radius_preset_values "$RADIUS_PRESET" \
        || die "unknown --radius-preset '$RADIUS_PRESET' — pick one of: $RADIUS_PRESETS custom"
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
elif op in (239, 240, 241, 242, 243) or frac in (0.94, 0.95):
    op, frac = 242, 0.95

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

# The one line tools/check-glass-modes.sh reads. Printed on every dry run rather
# than behind a flag of its own: the resolution is the whole of what a mode is,
# and a dry run that did not say which mode it resolved to would be describing
# everything except the question that was asked.
if [ "$DRY_RUN" = 1 ]; then
    printf '  glass-mode: %s blur=%s window=%s popup=%s transparency=%s styling=%s\n' \
        "$(glass_mode_from_state)" "$WANT_BLUR" "$WANT_WINDOW_BLUR" \
        "$WANT_POPUP_BLUR" "$APP_TRANSPARENCY" "$WANT_STYLING"
fi

VALID_REVERSAL="default black blue brown cyan green grey lightblue orange pink purple red"
# Colloid is named in accent terms rather than in its own: it calls blue
# "default" and slate "grey" on the command line, and accent_to_colloid_arg
# already knows that. Asking for colloid-blue and letting that function do the
# translation keeps one copy of the mapping instead of two.
case "$ICONS" in
    colloid|reversal|original) ;;
    colloid-*)
        case " $VALID_ACCENTS " in
            *" ${ICONS#colloid-} "*) ;;
            *) die "unknown Colloid colour '${ICONS#colloid-}' — pick one of: $VALID_ACCENTS" ;;
        esac ;;
    reversal-*)
        case " $VALID_REVERSAL " in
            *" ${ICONS#reversal-} "*) ;;
            *) die "unknown Reversal colour '${ICONS#reversal-}' — pick one of: $VALID_REVERSAL" ;;
        esac ;;
    *) die "unknown --icons '$ICONS' — colloid, reversal, original, or a pack with -COLOUR" ;;
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
    if [ "${GLASS_MODE:-}" = solid ]; then
        die "--glass-mode solid and --window-blur contradict each other — solid mode stands the theme down entirely, so there is no blur to put behind a window. Pick one."
    fi
    die "--no-blur and --window-blur contradict each other — --no-blur leaves Blur My Shell out entirely, so there is nothing to blur behind a window. Pick one."
fi

printf '\n%s  aura-glass%s  %saccent %s%s\n' \
    "$C_BLD" "$C_OFF" "$C_DIM" "$ACCENT" "$C_OFF"
[ "$DRY_RUN" = 1 ] && printf '%s  dry run — nothing will be changed%s\n' "$C_DIM" "$C_OFF"

preflight

# Retuning an existing install is the three steps that read a flag and write a
# setting. Everything skipped here either fetches something (the theme, the
# extensions, the icon and cursor packs) or wants root (the rounded-blur library,
# GDM), which is what makes this path fast, offline and unprivileged — and
# therefore the one a GUI can drive without a terminal to answer prompts in.
#
# The three steps are the same functions a full install runs, in the same order,
# rather than a settings-only reimplementation of them: the precedence between a
# flag, a $CONF_DIR memo and a default lives in one place and is exercised the
# same way by both paths.
# The dependency check on its own, for the settings window to hand to a terminal.
# install_deps runs sudo, which is why the window cannot run it: there is no
# password prompt in a GTK dialog reading a pipe. A narrow entry point rather
# than telling someone to run the whole installer, so the command in the
# terminal says exactly what it is about to do.
if [ "$DEPS_ONLY" = 1 ]; then
    install_deps || die "dependencies are still missing"
    step "Done"
    exit 0
fi

if [ "$SETTINGS_ONLY" = 1 ]; then
    if [ ! -d "$CONF_DIR" ] || [ ! -d "$HOME/.themes/Tahoe-Dark" ]; then
        die "--settings-only retunes an existing install, but there is nothing installed yet. Run ./install.sh first."
    fi
    # Asking for a different pack is asking for it to be installed, so these run
    # here despite fetching — but only when the flag was actually given. A
    # flagless --settings-only stays offline, which is what makes it the thing a
    # window can press without warning anyone. Switching between packs already
    # on disk does not download either: both steps skip when the theme is there.
    if [ -n "$ICONS_EXPLICIT" ] && [ "$WANT_ICONS" = 1 ]; then install_icons; fi
    if [ -n "$CURSORS_EXPLICIT" ] && [ "$WANT_CURSORS" = 1 ]; then install_cursors; fi
    load_dconf
    install_css
    apply_gsettings
    remember_glass_mode
    # Included because it is local, quick and needs nothing: it also refreshes
    # the installed copy of the window, so pulling the repo and pressing Apply
    # is enough to be running the current one.
    install_gui
    install_update_check
    # Local, quick, needs nothing and is a plain user systemd unit — the same
    # grounds install_gui is here on. Without it the window's switch for it
    # would write a memo that nothing acted on until the next full install.
    install_panel_blur_unit
    step "Done"
    cat <<EOF

    The shell picked this up already — aura-glass-apply reloaded it. Restart any
    GTK app that is open to get the GTK side.

    Nothing else was touched: the theme, the extensions, the icons and the
    cursors are exactly as they were.

EOF
    exit 0
fi

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
remember_glass_mode
install_icon_sync
install_gui
install_update_check
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
