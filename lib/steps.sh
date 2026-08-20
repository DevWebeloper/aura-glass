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

# What upstream's installer writes into ~/.themes, and what we rename it to.
# The first is a string literal inside their install.sh with no flag to change
# it, so the theme is adopted after they run rather than installed under our
# name — see adopt_theme_dir in lib/steps-migrate.sh.
UPSTREAM_THEME_NAME="Tahoe-Dark"
THEME_NAME="Aura-Glass"

BMS_REPO="https://github.com/aunetx/blur-my-shell.git"
BMS_REF="7d1290bbcff9"            # master; no release carries the popup component
BMS_UUID="blur-my-shell@aunetx"
# Applied on top of that pin: `blur-on-overview: false` does not take the blur
# out of the overview's window previews upstream, it only stops forcing window
# actors visible. See the patch's own comments.
BMS_PATCH="blur-my-shell-overview.patch"

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

# Hatter has no tags and no releases, so the pin is a bare commit. It is also
# the one pack big enough for that to matter: a full clone is over a gigabyte
# of history, and a checkout of everything in it is 328M. install_hatter fetches
# it shallow and sparse for that reason — see the comment there.
HATTER_REPO="https://github.com/Mibea/Hatter.git"
# Full length, unlike the pins above it: those are resolved locally after a full
# clone, where an abbreviation is enough. This one is asked for by name in a
# shallow fetch, and a server will only hand over a SHA spelled out in full.
HATTER_REF="89287fa3f1bdc25d94a2ef358ecd27696e1ee09a"

# The only pack here that is not built from a checkout. Upstream ships no
# installer and no prebuilt theme in the tree — building it needs bun,
# kcursorgen and xcursorgen — but every release carries a ready Linux theme,
# so the release is what gets fetched. Pinned by version and by hash, which is
# what a tarball has instead of a commit.
AOSP_CURSORS_VERSION="1.3.1"
AOSP_CURSORS_URL="https://github.com/Tech-Tac/aosp-cursors/releases/download/$AOSP_CURSORS_VERSION/aosp-cursors-linux-$AOSP_CURSORS_VERSION.tar.xz"
AOSP_CURSORS_SHA256="d271d2be20a6d7ac13747e4d9224a28ddbf7e2c1fab2e805cdf03bde05a0a3ae"

# The three fonts --font can install. None of them is packaged widely enough to
# assume, so each is fetched the way its upstream publishes it.
#
# Inter ships one release asset with everything in it. Inter.ttc is the static
# collection and the only file taken: its family is `Inter`, which is the name
# the gsettings keys will carry. The InterVariable pair beside it registers as
# a separate family called `Inter Variable`, so installing them as well would
# put a second name in every font list for no gain.
INTER_VERSION="4.1"
INTER_URL="https://github.com/rsms/inter/releases/download/v$INTER_VERSION/Inter-$INTER_VERSION.zip"
INTER_SHA256="9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e"

# MiSans comes from Xiaomi as one zip per script. The Latin one is the interface
# font — 3.4M against 218M for the full family, whose extra 214M is the CJK
# coverage GNOME already has from Noto — and the Arabic one is there because the
# Latin zip has no Arabic at all, so without it every Arabic string on the
# desktop would drop back to Noto and read as a different typeface mid-sentence.
# fonts/misans-arabic.conf is what points fontconfig at it.
#
# Both URLs are unversioned: Xiaomi overwrite them in place. The checksums are
# a notice rather than a pin for that reason — see fetch_zip_pinned.
MISANS_LATIN_URL="https://hyperos.mi.com/font-download/MiSans_Latin.zip"
MISANS_LATIN_SHA256="d24091ccd409a4152ffcc12cd659c16df9cdcdb4c702d8ae355b321e711f0004"
MISANS_ARABIC_URL="https://hyperos.mi.com/font-download/MiSans_Arabic.zip"
MISANS_ARABIC_SHA256="f2cc4939d202d6c645c5cb06133fbdf7caa420d43250682f9d3792884c8b72e5"

# San Francisco is Apple's, and Apple do not license it for this. There is no
# upstream to pin, so the pin is a mirror that has carried the OTFs unchanged
# since 2019 — the same arrangement every "SF Pro on Linux" guide relies on, and
# it is called out in the README rather than left to be discovered.
SFPRO_REPO="https://github.com/sahibjotsaggu/San-Francisco-Pro-Fonts.git"
SFPRO_REF="8bfea09aa6f1"

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

# Catalogued and installable, but never switched on by a pack. Auto Accent
# Colour rewrites org.gnome.desktop.interface accent-color from the wallpaper
# every time the wallpaper changes — and that key is the one thing the wizard
# asks for by name, so with this on the accent someone picked is replaced by
# whatever their wallpaper averages to (orange, for a warm one) within a
# session. It stays in EXT_EXTRA_ALL so the settings window still lists it and
# can install it for anyone who would rather the wallpaper decided; what it does
# not get is to arrive switched on behind an --all-extras.
EXT_NO_AUTO_ENABLE=(
    auto-accent-colour@Wartybix
)

# Active selection of extra extensions (defaults to recommended pack)
EXT_EXTRA=("${EXT_EXTRA_RECOMMENDED[@]}")

# Helper to describe an extension UUID
ext_description() {
    case "$1" in
        # The four the theme is built out of. They had no entry here while this
        # was only read for the optional tiers; the settings window lists them
        # too, and a row titled with a bare UUID is not a description.
        user-theme@gnome-shell-extensions.gcampax.github.com)
            printf 'User Themes — lets the shell load a theme from your home directory' ;;
        openbar@neuromorph)
            printf 'Open Bar — paints the panel, menus and popups this theme styles' ;;
        blur-my-shell@aunetx)
            printf 'Blur My Shell — the blur behind windows, popups and the panel' ;;
        custom-osd@neuromorph)
            printf 'Custom OSD — the volume and brightness pill' ;;
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

    # Before anything is applied, and only ever the first time: this is what
    # --icons original and --cursors original restore to. Idempotent after that,
    # like the backup_once calls in install_theme.
    gsettings_backup_once org.gnome.desktop.interface icon-theme icon-theme
    gsettings_backup_once org.gnome.desktop.interface cursor-theme cursor-theme
}

# ------------------------------------------------------------------- theme --

install_theme() {
    step "Installing the GTK + shell theme"

    local src="$SRC_CACHE/GNOME-macOS-Tahoe"
    clone_pinned "$THEME_REPO" "$THEME_REF" "$src"

    # Back up whatever libadwaita override was there before we overwrite it.
    # Three of these are called gtk.css, hence the explicit backup names.
    backup_once "$HOME/.config/gtk-4.0/gtk.css"      "$BACKUP_DIR" "gtk4-gtk.css"
    backup_once "$HOME/.config/gtk-4.0/gtk-dark.css" "$BACKUP_DIR" "gtk4-gtk-dark.css"
    backup_once "$HOME/.config/gtk-3.0/gtk.css"      "$BACKUP_DIR" "gtk3-gtk.css"

    # Upstream backs up anything already sitting on its target name, which is
    # how ~/.themes filled up with Tahoe-Dark.backup.<timestamp> copies that
    # nothing ever collected. We rename its output away on every run, so the
    # target is normally clear already; clearing it here makes that certain.
    run rm -rf "$HOME/.themes/$UPSTREAM_THEME_NAME"

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

    [ "${DRY_RUN:-0}" = 1 ] || [ -d "$HOME/.themes/$UPSTREAM_THEME_NAME" ] \
        || die "expected ~/.themes/$UPSTREAM_THEME_NAME after install, but it is not there"

    # Renamed before it is backed up or spliced, so every path from here on —
    # including the backup below — refers to the theme under our own name.
    adopt_theme_dir
    ok "$THEME_NAME installed"

    backup_once "$HOME/.themes/$THEME_NAME/gnome-shell/gnome-shell.css" "$BACKUP_DIR" "gnome-shell.css"
}

# -------------------------------------------------------------- extensions --

finish() {
    # Runs whether or not --rounded-blur was passed, so a machine whose library
    # went stale after a mutter update finds out on the next install either way.
    rounded_blur_staleness_check
    # Here rather than beside install_gui in the main sequence, because this is
    # the one thing that is about the logout below rather than about the
    # install: everything that reaches finish() ends with one, and nothing that
    # skips finish() — --settings-only, --deps-only — needs one.
    install_first_open_autostart
    step "Done"
    cat <<EOF

    Log out and back in. Extensions cannot be loaded into a running shell on
    Wayland, so the top bar, the blur and the quick settings will only look
    right on the next session. Aura Glass will open itself once when you get
    back, so you can see what landed — after that it stays out of the way.

    Afterwards:
      aura-glass-apply          re-apply the CSS (needed after any theme update)
      ./uninstall.sh            put everything back

    If ~/.local/bin is not on your PATH, add it:
      fish_add_path ~/.local/bin        # fish
      export PATH="\$HOME/.local/bin:\$PATH"   # bash / zsh

EOF
    prompt_logout
}
