# shellcheck shell=bash
# aura-glass — the shared values every step works from, and the two steps that
# bracket a run.
#
# The steps themselves were one 1300-line file until they were split by concern,
# the same way css/ was. What lives where:
#
#   lib/steps.sh              the upstream pins, the paths, the extension lists,
#                             preflight, the theme itself, and the closing note
#   lib/steps-extensions.sh   every extension: the ones fetched from EGO, the
#                             three built from a pinned commit, and the
#                             rounded-blur library
#   lib/steps-assets.sh       icon and cursor themes
#   lib/steps-css.sh          the CSS tweaks and the display-density correction
#   lib/steps-dconf.sh        the dconf preset, and the gsettings beside it
#   lib/steps-integration.sh  the icon-sync agent, the Flatpak override and the
#                             panel blur unit
#
# install.sh sources all six. They are definitions only — nothing runs at source
# time — so the order between them does not matter, except that this file has to
# come first: it defines CONF_DIR, which install.sh reads while parsing flags.

# Upstreams are pinned. Both move regularly, and a theme that changes under the
# CSS tweaks is exactly how you get a half-applied look with no error message.
THEME_REPO="https://github.com/kayozxo/GNOME-macOS-Tahoe.git"
THEME_REF="6dfcd9d941e5"

BMS_REPO="https://github.com/aunetx/blur-my-shell.git"
BMS_REF="7d1290bbcff9"            # master; no release carries the popup component
BMS_UUID="blur-my-shell@aunetx"

ROUNDEDBLUR_REPO="https://github.com/kancko/gnome-rounded-blur.git"
ROUNDEDBLUR_REF="9c7efb7ac5de"    # v1.0.1

OPENBAR_REPO="https://github.com/neuromorph/openbar.git"
OPENBAR_REF="01fb24217e0c"       # last upstream commit; patched for GNOME 50

CUSTOMOSD_REPO="https://github.com/neuromorph/custom-osd.git"
CUSTOMOSD_REF="334ac17e9348"     # last upstream commit; patched for GNOME 50

COLLOID_REPO="https://github.com/vinceliuice/Colloid-icon-theme.git"
COLLOID_REF="c9e702beb96f"

REVERSAL_REPO="https://github.com/yeyushengfan258/Reversal-icon-theme.git"
REVERSAL_REF="2c8122287e3b"

MACTAHOE_REPO="https://github.com/vinceliuice/MacTahoe-icon-theme.git"
MACTAHOE_REF="b85923bb87f5"

EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
CONF_DIR="$HOME/.config/aura-glass"
BACKUP_DIR="$CONF_DIR/backups"
SRC_CACHE="$HOME/.cache/aura-glass/src"

# Everything the look actually needs that comes straight from the extensions
# site. openbar, custom-osd and blur-my-shell are absent because each is built
# from a pinned commit instead — see install_openbar, install_custom_osd and
# install_bms.
EXT_CORE=(
    user-theme@gnome-shell-extensions.gcampax.github.com
)
# The rest of the reference desktop, in the order the shell lays them out.
# None of it is strictly required. Recommended pack is selected by default.
#
# Some of these may already be packaged by the distro. install_ext_ego checks
# /usr/share/gnome-shell/extensions before downloading, so those are enabled in
# place rather than shadowed by a second copy under $HOME that would then drift
# from whatever the system ships.
EXT_EXTRA_RECOMMENDED=(
    just-perfection-desktop@just-perfection
    gnome-ui-tune@itstime.tech
    space-bar@luchrioh
    appindicatorsupport@rgcjonas.gmail.com
    clipboard-indicator@tudmotu.com
    compiz-alike-magic-lamp-effect@hermes83.github.com
)

EXT_EXTRA_ALL=(
    just-perfection-desktop@just-perfection
    gnome-ui-tune@itstime.tech
    space-bar@luchrioh
    appindicatorsupport@rgcjonas.gmail.com
    clipboard-indicator@tudmotu.com
    compiz-alike-magic-lamp-effect@hermes83.github.com
    Vitals@CoreCoding.com
    auto-accent-colour@Wartybix
    ddterm@amezin.github.com
    kiwimenu@kemma
    hotedge@jonathan.jdoda.ca
    restartto@tiagoporsch.github.io
    xwayland-indicator@swsnr.de
    add-to-steam@pupper.space
)

# Active selection of extra extensions (defaults to recommended pack)
EXT_EXTRA=("${EXT_EXTRA_RECOMMENDED[@]}")

# Helper to describe an extension UUID
ext_description() {
    case "$1" in
        just-perfection-desktop@just-perfection)
            printf 'Just Perfection — GNOME UI tweaker & visibility manager' ;;
        gnome-ui-tune@itstime.tech)
            printf 'GNOME UI Tune — Overview 300%% thumbnail enlargement & tweaks' ;;
        space-bar@luchrioh)
            printf 'Space Bar — macOS/i3-style workspace pill indicator in panel' ;;
        appindicatorsupport@rgcjonas.gmail.com)
            printf 'AppIndicator Support — System tray icons (Steam, Discord, Slack, etc.)' ;;
        clipboard-indicator@tudmotu.com)
            printf 'Clipboard Indicator — Top-bar clipboard history with search & hotkey' ;;
        compiz-alike-magic-lamp-effect@hermes83.github.com)
            printf 'Magic Lamp Effect — macOS Genie window minimize animation' ;;
        Vitals@CoreCoding.com)
            printf 'Vitals — Live CPU, RAM, temp, load & network monitor in panel' ;;
        auto-accent-colour@Wartybix)
            printf 'Auto Accent Colour — Automatically syncs accent color with wallpaper' ;;
        ddterm@amezin.github.com)
            printf 'ddterm — Drop-down terminal toggleable with global hotkey' ;;
        kiwimenu@kemma)
            printf 'Kiwi Menu — macOS-style Applications menu on left of top bar' ;;
        hotedge@jonathan.jdoda.ca)
            printf 'Hot Edge — Triggers dock/overview by touching bottom screen edge' ;;
        restartto@tiagoporsch.github.io)
            printf 'Restart To — Adds UEFI/BIOS reboot entries in power menu' ;;
        xwayland-indicator@swsnr.de)
            printf 'XWayland Indicator — Indicator icon for legacy XWayland apps' ;;
        add-to-steam@pupper.space)
            printf 'Add to Steam — Shortcut to add non-Steam games/apps to Steam' ;;
        *)
            printf '%s' "$1" ;;
    esac
}

preflight() {
    step "Checking the session"

    [ -n "${BASH_VERSION:-}" ] || die "run this with bash, not sh"

    local desktop="${XDG_CURRENT_DESKTOP:-}"
    case "$desktop" in
        *GNOME*) ok "GNOME session detected ($desktop)" ;;
        '')      warn "XDG_CURRENT_DESKTOP is unset — cannot confirm this is GNOME" ;;
        *)       die "this is a GNOME desktop theme, but the session is '$desktop'" ;;
    esac

    GNOME_MAJOR="$(gnome_major)" || die "gnome-shell not found"
    if [ "$GNOME_MAJOR" -lt 48 ]; then
        die "GNOME $GNOME_MAJOR is older than this project supports (48+)"
    elif [ "$GNOME_MAJOR" -gt 50 ]; then
        warn "GNOME $GNOME_MAJOR is newer than this was tested against (48-50)"
    fi
    ok "GNOME Shell $GNOME_MAJOR"

    if [ "${XDG_SESSION_TYPE:-}" = x11 ]; then
        warn "X11 session — Blur My Shell is far less reliable here than on Wayland"
    fi

    detect_distro
    case "$DISTRO_FAMILY" in
        arch)    ok "$DISTRO_PRETTY (arch family)" ;;
        *)       warn "$DISTRO_PRETTY — untested family '$DISTRO_FAMILY', continuing anyway" ;;
    esac

    run mkdir -p "$CONF_DIR" "$BACKUP_DIR" "$SRC_CACHE" "$EXT_DIR"
}

# ------------------------------------------------------------------- theme --

install_theme() {
    step "Installing the Tahoe GTK + shell theme"

    local src="$SRC_CACHE/GNOME-macOS-Tahoe"
    clone_pinned "$THEME_REPO" "$THEME_REF" "$src"

    # Back up whatever libadwaita override was there before we overwrite it.
    # Three of these are called gtk.css, hence the explicit backup names.
    backup_once "$HOME/.config/gtk-4.0/gtk.css"      "$BACKUP_DIR" "gtk4-gtk.css"
    backup_once "$HOME/.config/gtk-4.0/gtk-dark.css" "$BACKUP_DIR" "gtk4-gtk-dark.css"
    backup_once "$HOME/.config/gtk-3.0/gtk.css"      "$BACKUP_DIR" "gtk3-gtk.css"

    # -d installs the dark theme into ~/.themes, -la writes the libadwaita
    # override into ~/.config/gtk-4.0. Both are per-user, so this needs no
    # root. </dev/null keeps its gum prompts quiet.
    info "running the theme's own installer (dark + libadwaita override)"
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: $src/install.sh -d -la"
    else
        ( cd "$src" && ./install.sh -d -la ) </dev/null \
            || die "the Tahoe theme installer failed"
    fi

    [ "${DRY_RUN:-0}" = 1 ] || [ -d "$HOME/.themes/Tahoe-Dark" ] \
        || die "expected ~/.themes/Tahoe-Dark after install, but it is not there"
    ok "Tahoe-Dark installed"

    backup_once "$HOME/.themes/Tahoe-Dark/gnome-shell/gnome-shell.css" "$BACKUP_DIR" "gnome-shell.css"
}

# -------------------------------------------------------------- extensions --

finish() {
    # Runs whether or not --rounded-blur was passed, so a machine whose library
    # went stale after a mutter update finds out on the next install either way.
    rounded_blur_staleness_check
    step "Done"
    cat <<EOF

    Log out and back in. Extensions cannot be loaded into a running shell on
    Wayland, so the top bar, the blur and the quick settings will only look
    right on the next session.

    Afterwards:
      aura-glass-apply          re-apply the CSS (needed after any theme update)
      ./uninstall.sh            put everything back

    If ~/.local/bin is not on your PATH, add it:
      fish_add_path ~/.local/bin        # fish
      export PATH="\$HOME/.local/bin:\$PATH"   # bash / zsh

EOF
    prompt_logout
}
