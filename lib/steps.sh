# shellcheck shell=bash
# tahoe-glass — the individual install steps.

# Upstreams are pinned. Both move regularly, and a theme that changes under the
# CSS tweaks is exactly how you get a half-applied look with no error message.
THEME_REPO="https://github.com/kayozxo/GNOME-macOS-Tahoe.git"
THEME_REF="6dfcd9d941e5"

BMS_REPO="https://github.com/aunetx/blur-my-shell.git"
BMS_REF="7d1290bbcff9"            # master; no release carries the popup component
BMS_UUID="blur-my-shell@aunetx"

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
CONF_DIR="$HOME/.config/tahoe-glass"
BACKUP_DIR="$CONF_DIR/backups"
SRC_CACHE="$HOME/.cache/tahoe-glass/src"

# Everything the look actually needs that comes straight from the extensions
# site. openbar, custom-osd and blur-my-shell are absent because each is built
# from a pinned commit instead — see install_openbar, install_custom_osd and
# install_bms.
EXT_CORE=(
    user-theme@gnome-shell-extensions.gcampax.github.com
)
# The rest of the reference desktop, in the order the shell lays them out.
# None of it is required, and --extras is what asks for it.
#
# Some of these may already be packaged by the distro. install_ext_ego checks
# /usr/share/gnome-shell/extensions before downloading, so those are enabled in
# place rather than shadowed by a second copy under $HOME that would then drift
# from whatever the system ships.
EXT_EXTRA=(
    just-perfection-desktop@just-perfection
    gnome-ui-tune@itstime.tech
    space-bar@luchrioh
    auto-accent-colour@Wartybix
    Vitals@CoreCoding.com
    clipboard-indicator@tudmotu.com
    ddterm@amezin.github.com
    kiwimenu@kemma
    hotedge@jonathan.jdoda.ca
    restartto@tiagoporsch.github.io
    xwayland-indicator@swsnr.de
    appindicatorsupport@rgcjonas.gmail.com
    compiz-alike-magic-lamp-effect@hermes83.github.com
    add-to-steam@pupper.space
)

# GNOME's accent enum -> Colloid's folder-colour variant. Colloid calls blue
# "default" on the command line and leaves it out of the theme name.
accent_to_colloid_arg() {
    case "$1" in
        blue)   echo default ;;
        slate)  echo grey ;;
        teal|green|yellow|orange|red|pink|purple) echo "$1" ;;
        *)      echo default ;;
    esac
}
accent_to_colloid_name() {
    case "$1" in
        blue)  echo "Colloid-Dark" ;;
        slate) echo "Colloid-Grey-Dark" ;;
        teal)  echo "Colloid-Teal-Dark" ;;
        *)     echo "Colloid-${1^}-Dark" ;;
    esac
}

# ---------------------------------------------------------------- preflight --

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

# EGO's shell_version filter is loose — it will happily hand you a build whose
# metadata stops at 49 when you ask for 50 — so the download is always checked
# against the running shell rather than trusted.
ext_supports_shell() {
    local dir_or_zip="$1" major="$2"
    local meta
    if [ -d "$dir_or_zip" ]; then
        meta="$(cat "$dir_or_zip/metadata.json" 2>/dev/null)" || return 1
    else
        meta="$(unzip -p "$dir_or_zip" metadata.json 2>/dev/null)" || return 1
    fi
    printf '%s' "$meta" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if str(sys.argv[1]) in [str(v).split(".")[0] for v in d.get("shell-version", [])] else 1)
' "$major"
}

install_ext_ego() {
    local uuid="$1" tmp url info_json ver

    if [ -d "$EXT_DIR/$uuid" ] && ext_supports_shell "$EXT_DIR/$uuid" "$GNOME_MAJOR"; then
        skip "$uuid already installed"
        return 0
    fi
    # Distro-packaged extensions (user-theme on most systems) count as present.
    if [ -d "/usr/share/gnome-shell/extensions/$uuid" ] \
       && ext_supports_shell "/usr/share/gnome-shell/extensions/$uuid" "$GNOME_MAJOR"; then
        skip "$uuid provided by the system"
        return 0
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: download and install $uuid from extensions.gnome.org"
        return 0
    fi

    info_json="$(curl -sf "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$GNOME_MAJOR")" \
        || { warn "$uuid: not listed for GNOME $GNOME_MAJOR — skipped"; return 1; }
    url="$(printf '%s' "$info_json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["download_url"])')" \
        || { warn "$uuid: no download url — skipped"; return 1; }

    # Deliberately not `trap ... RETURN`: that trap is not scoped to this
    # function, so it stays registered and fires again on the next function
    # return in the whole script — by which point $tmp is gone and `set -u`
    # turns the stale cleanup into a fatal "unbound variable" mid-install.
    tmp="$(mktemp -d)"
    local rc=0
    if ! curl -sLo "$tmp/e.zip" "https://extensions.gnome.org$url"; then
        warn "$uuid: download failed — skipped"; rc=1
    elif ! ext_supports_shell "$tmp/e.zip" "$GNOME_MAJOR"; then
        ver="$(unzip -p "$tmp/e.zip" metadata.json | python3 -c 'import sys,json;print(json.load(sys.stdin).get("shell-version"))')"
        warn "$uuid: published build supports $ver, not GNOME $GNOME_MAJOR — skipped"; rc=1
    elif ! gnome-extensions install --force "$tmp/e.zip" >/dev/null; then
        warn "$uuid: install failed — skipped"; rc=1
    else
        ok "$uuid"
    fi
    rm -rf "$tmp"
    return "$rc"
}

# Blur My Shell's published build (v72) has no popup component: menus, quick
# settings, notifications, dialogs and the OSD get no blur at all. That is why
# css/shell-tweaks.css paints its own flat translucency behind them, and why the
# OSD used to carry a hand-rolled corner shader. Upstream's master has the
# component; there is no release with it yet, so it is built from a pinned
# commit. gnome-extensions pack and gnome-extensions install both write under
# $HOME, so this needs no root.
install_bms() {
    if [ "${WANT_BMS_GIT:-1}" != 1 ]; then
        install_ext_ego "$BMS_UUID" || true
        if [ "${DRY_RUN:-0}" != 1 ]; then
            mkdir -p "$CONF_DIR"
            printf 'ego\n' > "$CONF_DIR/bms-source"
            rm -f "$CONF_DIR/bms-ref"
        fi
        skip "Blur My Shell from extensions.gnome.org (--no-bms-git) — no popup blur"
        return 0
    fi

    # master still declares "version": 72, the same as the published build, so
    # the version number cannot tell the two apart. Probe for the component and
    # check the stamp — the directory test matters on its own because
    # ./uninstall.sh --extensions removes the extension but leaves $CONF_DIR.
    if [ "${FORCE:-0}" != 1 ] \
       && [ -f "$EXT_DIR/$BMS_UUID/components/popup/index.js" ] \
       && [ "$(cat "$CONF_DIR/bms-ref" 2>/dev/null || true)" = "$BMS_REF" ] \
       && ext_supports_shell "$EXT_DIR/$BMS_UUID" "$GNOME_MAJOR"; then
        skip "$BMS_UUID already built from $BMS_REF"
        return 0
    fi

    info "no release carries the popup component — building from $BMS_REF"
    local src="$SRC_CACHE/blur-my-shell"
    clone_pinned "$BMS_REPO" "$BMS_REF" "$src"

    local podir=(--podir=../po)
    if ! have msgfmt; then
        warn "msgfmt not found (install gettext) — building without translations"
        podir=()
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: gnome-extensions pack in $src/src, then install the zip"
        return 0
    fi

    # This mirrors upstream's Makefile 'build' target rather than calling make,
    # because make is not one of this project's dependencies. Doing it here also
    # means a failed build never gets as far as deleting the working extension.
    # The mkdir is not optional: given a -o directory that does not exist,
    # gnome-extensions pack segfaults (139) instead of reporting an error.
    rm -rf "$src/build"
    mkdir -p "$src/build"
    ( cd "$src/src" && gnome-extensions pack -f \
        --extra-source=../metadata.json \
        --extra-source=../LICENSE \
        --extra-source=../resources/icons \
        --extra-source=../resources/ui \
        --extra-source=./components \
        --extra-source=./conveniences \
        --extra-source=./effects \
        --extra-source=./preferences \
        --extra-source=./dbus \
        --extra-source=./styles \
        "${podir[@]}" \
        --schema=../schemas/org.gnome.shell.extensions.blur-my-shell.gschema.xml \
        -o ../build ) >/dev/null \
        || die "packing Blur My Shell failed — upstream's layout may have moved"

    local zip="$src/build/$BMS_UUID.shell-extension.zip"
    [ -f "$zip" ] || die "expected $zip after packing, but it is not there"
    ext_supports_shell "$zip" "$GNOME_MAJOR" \
        || die "the pinned Blur My Shell does not support GNOME $GNOME_MAJOR"

    # Upstream's Makefile removes the directory before installing, and it is
    # right to: v72 keeps its components as flat files where master keeps
    # directories, so an overlay would leave both and load the wrong one.
    # Settings live in dconf, not here, so nothing is lost. This runs only
    # after the zip exists and has been checked.
    rm -rf "$EXT_DIR/$BMS_UUID"
    gnome-extensions install --force "$zip" >/dev/null \
        || die "installing Blur My Shell failed"

    # gnome-extensions install compiles the schema itself, but the whole popup
    # section is unreadable if it ever stops, and that would show up as the
    # preset silently doing nothing rather than as an error.
    if [ ! -f "$EXT_DIR/$BMS_UUID/schemas/gschemas.compiled" ]; then
        glib-compile-schemas "$EXT_DIR/$BMS_UUID/schemas" \
            || die "failed to compile Blur My Shell's gsettings schemas"
    fi

    mkdir -p "$CONF_DIR"
    printf '%s\n' "$BMS_REF" > "$CONF_DIR/bms-ref"
    printf 'git\n' > "$CONF_DIR/bms-source"
    ok "$BMS_UUID (built from $BMS_REF, with the popup component)"
}

# Open Bar is the one extension with no GNOME 50 release. Upstream's last
# commit targets 49, so on 50 it is built from that commit plus the patch in
# patches/. On 49 and below the published build is used unchanged.
install_openbar() {
    local uuid="openbar@neuromorph"

    if [ "$GNOME_MAJOR" -lt 50 ]; then
        install_ext_ego "$uuid"
        return
    fi

    if [ -d "$EXT_DIR/$uuid" ] && ext_supports_shell "$EXT_DIR/$uuid" "$GNOME_MAJOR" && [ "${FORCE:-0}" != 1 ]; then
        skip "$uuid already patched for GNOME $GNOME_MAJOR"
        return 0
    fi

    info "no GNOME 50 release exists — building from $OPENBAR_REF + patches/openbar-gnome50.patch"
    local src="$SRC_CACHE/openbar"
    clone_pinned "$OPENBAR_REPO" "$OPENBAR_REF" "$src"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: apply patch, copy to $EXT_DIR/$uuid, compile schemas"
        return 0
    fi

    git -C "$src" apply --whitespace=nowarn "$REPO_ROOT/patches/openbar-gnome50.patch" \
        || die "the Open Bar patch did not apply — upstream may have moved"

    rm -rf "$EXT_DIR/$uuid"
    mkdir -p "$EXT_DIR"
    cp -a "$src/$uuid" "$EXT_DIR/$uuid"

    if [ -d "$EXT_DIR/$uuid/schemas" ]; then
        glib-compile-schemas "$EXT_DIR/$uuid/schemas" \
            || die "failed to compile Open Bar's gsettings schemas"
    fi
    ok "$uuid (patched for GNOME $GNOME_MAJOR)"
}

# Custom OSD is what turns the volume and brightness popup into the bar on its
# own. Upstream's last release is for GNOME 46 and its last commit does not run
# on 50 — the ShellBlurEffect:sigma property, the meta_*_clutter_debug_flags()
# calls and OsdWindowManager.show()'s signature have all gone since. The patch
# in patches/ fixes those, and rounds the blur to the popup's corners: a
# background blur covers the actor's bounding box, so without it the pill sits
# in a hard-edged rectangle of blur no matter what radius is set.
install_custom_osd() {
    local uuid="custom-osd@neuromorph"

    if [ "${WANT_OSD:-1}" != 1 ]; then
        step "Custom OSD"
        skip "not installed (--no-osd)"
        return 0
    fi

    if [ -d "$EXT_DIR/$uuid" ] && ext_supports_shell "$EXT_DIR/$uuid" "$GNOME_MAJOR" \
       && [ "${FORCE:-0}" != 1 ]; then
        skip "$uuid already patched for GNOME $GNOME_MAJOR"
        return 0
    fi

    info "no GNOME $GNOME_MAJOR release exists — building from $CUSTOMOSD_REF + patches/custom-osd-gnome50.patch"
    local src="$SRC_CACHE/custom-osd"
    # A cached checkout still carries the patch from last time, and git refuses
    # to check out over modified files — so --force would fail on the second
    # run rather than rebuild.
    if [ -d "$src/.git" ]; then
        run git -C "$src" checkout --quiet -- . 2>/dev/null || true
    fi
    clone_pinned "$CUSTOMOSD_REPO" "$CUSTOMOSD_REF" "$src"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: apply patch, copy to $EXT_DIR/$uuid, compile schemas"
        return 0
    fi

    git -C "$src" apply --whitespace=nowarn "$REPO_ROOT/patches/custom-osd-gnome50.patch" \
        || die "the Custom OSD patch did not apply — upstream may have moved"

    # Upstream keeps the extension at the root of the repo rather than in a
    # directory named after the UUID, so this copies the checkout itself.
    rm -rf "$EXT_DIR/$uuid"
    mkdir -p "$EXT_DIR/$uuid"
    tar -C "$src" --exclude=.git --exclude=screens --exclude=po -cf - . \
        | tar -C "$EXT_DIR/$uuid" -xf -

    glib-compile-schemas "$EXT_DIR/$uuid/schemas" \
        || die "failed to compile Custom OSD's gsettings schemas"
    ok "$uuid (patched for GNOME $GNOME_MAJOR)"
}

install_extensions() {
    step "Installing shell extensions"
    local u
    for u in "${EXT_CORE[@]}"; do install_ext_ego "$u" || true; done
    install_bms
    install_openbar
    install_custom_osd

    if [ "${WANT_EXTRAS:-0}" = 1 ]; then
        step "Installing optional extensions"
        for u in "${EXT_EXTRA[@]}"; do install_ext_ego "$u" || true; done
    fi
}

enable_extensions() {
    step "Enabling extensions"
    # $BMS_UUID is named explicitly rather than left in EXT_CORE so that it is
    # enabled whichever source install_bms took it from.
    local want=("${EXT_CORE[@]}" "$BMS_UUID" openbar@neuromorph) u
    [ "${WANT_OSD:-1}" = 1 ] && want+=(custom-osd@neuromorph)
    [ "${WANT_EXTRAS:-0}" = 1 ] && want+=("${EXT_EXTRA[@]}")

    for u in "${want[@]}"; do
        if [ ! -d "$EXT_DIR/$u" ] && [ ! -d "/usr/share/gnome-shell/extensions/$u" ]; then
            skip "$u not installed — not enabling"
            continue
        fi
        if run gnome-extensions enable "$u" 2>/dev/null; then
            ok "enabled $u"
            continue
        fi

        # gnome-extensions enable goes through the running shell, which refuses
        # a UUID it has not loaded — and on Wayland it cannot load one that
        # appeared after login. Claiming it will be "picked up after logout" is
        # not enough: the shell only starts what is listed in enabled-
        # extensions, so the UUID has to be put there directly or the next
        # session comes up without it.
        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: add $u to enabled-extensions for the next session"
            continue
        fi
        if enqueue_extension "$u"; then
            ok "$u queued — active after logout"
        else
            warn "could not enable $u"
        fi
    done
}

# Append a UUID to org.gnome.shell enabled-extensions without disturbing what
# is already there.
enqueue_extension() {
    python3 - "$1" <<'PY'
import subprocess, sys
uuid = sys.argv[1]
KEY = ["org.gnome.shell", "enabled-extensions"]
cur = subprocess.run(["gsettings", "get", *KEY], capture_output=True, text=True).stdout.strip()
# "@as []" is how an empty array comes back; strip the type annotation.
if cur.startswith("@as "):
    cur = cur[4:]
try:
    items = [x.strip().strip("'\"") for x in cur.strip("[]").split(",") if x.strip()]
except Exception:
    items = []
if uuid in items:
    sys.exit(0)
items.append(uuid)
new = "[" + ", ".join("'" + i + "'" for i in items) + "]"
subprocess.run(["gsettings", "set", *KEY, new], check=True)
PY
}

# ------------------------------------------------------------------- icons --

# The icon set, minus any light/dark suffix. Everything downstream — the
# gsettings key and the light/dark agent — works from this one name.
#
# --icons takes either "colloid", which follows --accent, or a pack and colour
# like "reversal-purple". Folder colour and accent are separate on purpose:
# wanting purple folders under a pink accent is a perfectly ordinary thing to
# want, and tying them together would make it unsayable.
icon_base() {
    case "${ICONS:-colloid}" in
        colloid)
            local n; n="$(accent_to_colloid_name "$ACCENT")"
            n="${n%-Dark}"; n="${n%-Light}"
            printf '%s\n' "$n" ;;
        reversal)        printf 'Reversal\n' ;;
        reversal-*)      printf 'Reversal-%s\n' "${ICONS#reversal-}" ;;
        *)               printf '%s\n' "$ICONS" ;;
    esac
}

# Packs disagree about how they spell the pair: Colloid ships -Light/-Dark,
# Reversal ships the bare name plus -dark. Rather than teach every caller the
# conventions, ask the filesystem which of them exists.
icon_variant() {
    local base="$1" want="$2" c   # want: Dark | Light
    for c in "$base-$want" "$base-$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')" "$base"; do
        if [ -d "$HOME/.local/share/icons/$c" ] || [ -d "/usr/share/icons/$c" ]; then
            printf '%s\n' "$c"; return 0
        fi
    done
    return 1
}

install_reversal() {
    local color="${ICONS#reversal}"; color="${color#-}"
    [ -n "$color" ] || color=purple
    local name="Reversal-$color"

    step "Installing the Reversal icon theme ($color)"
    if [ "${FORCE:-0}" != 1 ] \
       && { [ -d "$HOME/.local/share/icons/$name" ] || [ -d "/usr/share/icons/$name" ]; }; then
        skip "$name already installed"
        return 0
    fi

    local src="$SRC_CACHE/Reversal-icon-theme"
    clone_pinned "$REVERSAL_REPO" "$REVERSAL_REF" "$src"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: $src/install.sh -t $color"
    else
        ( cd "$src" && ./install.sh -t "$color" ) >/dev/null \
            || die "the Reversal installer failed"
    fi
    ok "$name"
}

install_icons() {
    case "${ICONS:-colloid}" in
        reversal|reversal-*) install_reversal; return ;;
    esac

    step "Installing the Colloid icon theme ($ACCENT)"

    local name; name="$(accent_to_colloid_name "$ACCENT")"
    if [ "${FORCE:-0}" != 1 ] \
       && { [ -d "$HOME/.local/share/icons/$name" ] || [ -d "/usr/share/icons/$name" ]; }; then
        skip "$name already installed"
        return 0
    fi

    local src="$SRC_CACHE/Colloid-icon-theme"
    clone_pinned "$COLLOID_REPO" "$COLLOID_REF" "$src"

    # No -d: unprivileged runs default to ~/.local/share/icons, which keeps
    # this step out of /usr like every other one.
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: $src/install.sh -t $(accent_to_colloid_arg "$ACCENT")"
    else
        ( cd "$src" && ./install.sh -t "$(accent_to_colloid_arg "$ACCENT")" ) >/dev/null \
            || die "the Colloid installer failed"
    fi
    ok "$name"
}

install_cursors() {
    # Adwaita's cursors ship with GNOME itself, so there is nothing to fetch,
    # nothing to keep pinned, and they are crisper and better hinted at every
    # size than the MacTahoe set. --cursors mactahoe asks for the old ones.
    if [ "${CURSORS:-adwaita}" = adwaita ]; then
        step "Cursors"
        skip "using the stock Adwaita cursors (--cursors mactahoe for the macOS set)"
        return 0
    fi

    step "Installing MacTahoe cursors"

    if [ "${FORCE:-0}" != 1 ] \
       && { [ -d "$HOME/.local/share/icons/MacTahoe-dark/cursors" ] \
            || [ -d "/usr/share/icons/MacTahoe-dark/cursors" ]; }; then
        skip "MacTahoe-dark cursors already installed"
        return 0
    fi

    local src="$SRC_CACHE/MacTahoe-icon-theme"
    clone_pinned "$MACTAHOE_REPO" "$MACTAHOE_REF" "$src"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: $src/install.sh"
    else
        # The cursors ship inside the icon theme, so the icon theme comes with
        # them. Colloid still supplies the app icons — only the pointer changes.
        ( cd "$src" && ./install.sh ) >/dev/null || die "the MacTahoe installer failed"
    fi
    ok "MacTahoe-dark"
}

# --------------------------------------------------------------- css + dconf --

# The CSS is written in logical pixels and was tuned on a 3440x1440 34" display
# — 109 logical PPI. GNOME's stylesheet has no media queries, so those numbers
# are the same on every screen and a dense panel renders them proportionally
# smaller: at the 144 PPI of a 15" 1080p laptop the top bar status icons come
# out a third under the size they were drawn for. Measure the panel at install
# time and emit corrected rules.
TUNED_PPI=109

# Logical PPI of the primary output, or nothing if it cannot be measured.
measure_logical_ppi() {
    python3 - <<'PY' 2>/dev/null
import glob, math, os, re, subprocess

def primary_and_scale():
    """Connector name and scale of the primary logical monitor, per mutter."""
    try:
        out = subprocess.run(
            ["gdbus", "call", "--session", "--dest", "org.gnome.Mutter.DisplayConfig",
             "--object-path", "/org/gnome/Mutter/DisplayConfig",
             "--method", "org.gnome.Mutter.DisplayConfig.GetCurrentState"],
            capture_output=True, text=True, timeout=5).stdout
        m = re.search(r"\(\d+, \d+, ([0-9.]+), uint32 \d+, true, \[\('([^']+)'", out)
        if m:
            return m.group(2), float(m.group(1))
    except Exception:
        pass
    return None, 1.0

conn, scale = primary_and_scale()

def ppi_of(path):
    w, h = (int(x) for x in open(path + "modes").read().split()[0].split("x"))
    edid = open(path + "edid", "rb").read()
    wcm, hcm = edid[21], edid[22]        # EDID basic params: image size in cm
    if not (wcm and hcm):
        return None
    return math.hypot(w, h) / (math.hypot(wcm, hcm) / 2.54)

best = None
for path in sorted(glob.glob("/sys/class/drm/card*-*/")):
    try:
        if open(path + "status").read().strip() != "connected":
            continue
        name = os.path.basename(path.rstrip("/")).split("-", 1)[1]
        ppi = ppi_of(path)
        if ppi is None:
            continue
        # Prefer the output mutter calls primary; fall back to the first
        # connected one so this still works with no session bus (dry runs).
        if conn and name == conn:
            best = ppi
            break
        if best is None:
            best = ppi
    except Exception:
        continue

if best and scale:
    print(round(best / scale))
PY
}

# Emit the density correction, or nothing when the display is close enough to
# what the CSS assumes that rescaling would be noise.
density_css() {
    local ppi="$1"
    python3 - "$ppi" "$TUNED_PPI" <<'PY'
import sys
ppi, tuned = float(sys.argv[1]), float(sys.argv[2])
ratio = ppi / tuned
if ratio < 1.12:
    sys.exit(0)
icon = round(16 * ratio)
hpad = round(6 * ratio)
print(f"""
/* ---------- Display density -------------------------------------------
 * Sizes above are logical pixels tuned for {tuned:.0f} logical PPI. This
 * display measures {ppi:.0f}, so the same numbers land {(1 - 1/ratio) * 100:.0f}% smaller than
 * drawn. Scale the top bar status icons — wifi, bluetooth, volume, battery —
 * back to their intended size. Generated at install time by install.sh. */
#panel .panel-button .system-status-icon {{
  icon-size: {icon}px;
  padding: 4px;
}}
#panel .panel-button {{
  -natural-hpadding: {hpad}px;
  -minimum-hpadding: {max(hpad - 2, 3)}px;
}}""")
PY
}

install_css() {
    step "Installing the CSS tweaks"

    run install -Dm644 "$REPO_ROOT/css/shell-tweaks.css" "$CONF_DIR/shell-tweaks.css"
    run install -Dm644 "$REPO_ROOT/css/gtk4-tweaks.css"  "$CONF_DIR/gtk4-tweaks.css"
    run install -Dm644 "$REPO_ROOT/css/gtk3-tweaks.css"  "$CONF_DIR/gtk3-tweaks.css"
    run install -Dm755 "$REPO_ROOT/bin/tahoe-glass-apply" "$HOME/.local/bin/tahoe-glass-apply"
    ok "css -> $CONF_DIR"
    ok "re-apply command -> ~/.local/bin/tahoe-glass-apply"

    # Appended to the copy rather than kept in css/, so it is regenerated for
    # whatever screen the installer is actually run on. Re-copying the file
    # above is what makes this idempotent.
    local ppi extra
    ppi="$(measure_logical_ppi || true)"
    if [ -z "$ppi" ]; then
        skip "could not measure display density — panel sizes left as tuned"
    else
        extra="$(density_css "$ppi")"
        if [ -z "$extra" ]; then
            ok "display is ${ppi} logical PPI — no scaling needed"
        elif [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: scale panel icons for ${ppi} logical PPI"
        else
            printf '%s\n' "$extra" >> "$CONF_DIR/shell-tweaks.css"
            ok "scaled panel icons for ${ppi} logical PPI (tuned at ${TUNED_PPI})"
        fi
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: tahoe-glass-apply"
    else
        "$HOME/.local/bin/tahoe-glass-apply" | sed 's/^/    /'
    fi
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

    if [ "${WANT_EXTRAS:-0}" = 1 ]; then
        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: dconf load /org/gnome/shell/extensions/ < dconf/extras.ini"
        else
            dconf load /org/gnome/shell/extensions/ < "$REPO_ROOT/dconf/extras.ini" || true
        fi
        ok "optional extension settings loaded"
    fi

    # Open Bar regenerates its stylesheet when this key changes, so writing it
    # last is what makes the preset take effect without a restart.
    run dconf write /org/gnome/shell/extensions/openbar/trigger-reload true

    apply_grain
    sync_osd_profile
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

apply_gsettings() {
    step "Setting themes and accent"

    # prefer-dark is set below, so pick the dark half of the pair here and save
    # the agent a visible swap a moment later.
    local base icons; base="$(icon_base)"
    icons="$(icon_variant "$base" Dark || true)"
    [ -n "$icons" ] \
        || { warn "icon theme $base is not installed — falling back to Adwaita"; icons="Adwaita"; }

    run gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    run gsettings set org.gnome.desktop.interface gtk-theme    'Tahoe-Dark'
    run gsettings set org.gnome.desktop.interface accent-color "$ACCENT"
    run gsettings set org.gnome.desktop.interface icon-theme   "$icons"

    local cursor='Adwaita'
    if [ "${CURSORS:-adwaita}" = mactahoe ] \
       && { [ -d "$HOME/.local/share/icons/MacTahoe-dark" ] \
            || [ -d "/usr/share/icons/MacTahoe-dark" ]; }; then
        cursor='MacTahoe-dark'
    fi
    run gsettings set org.gnome.desktop.interface cursor-theme "$cursor"

    # All three controls, minimise and maximise before close, appmenu on the
    # left. The window controls themselves are restyled in gtk4-tweaks.css.
    if [ "${WANT_WM_BUTTONS:-1}" = 1 ]; then
        run gsettings set org.gnome.desktop.wm.preferences button-layout \
            'appmenu:minimize,maximize,close'
    fi

    ok "gtk-theme=Tahoe-Dark  icons=$icons  cursor=$cursor  accent=$ACCENT"
}

# Colloid ships a -Light and a -Dark build of every accent; GNOME's icon-theme
# key holds exactly one name and knows nothing about the pair. Without this,
# switching Settings > Appearance to Light restyles everything except the
# icons, which stay dark and look wrong against the new background.
install_icon_sync() {
    step "Following the light/dark preference with the icons"

    if [ "${WANT_ICONS:-1}" != 1 ]; then
        skip "icons left alone (--no-icons)"
        return 0
    fi

    # The base name without the variant suffix, which is what the agent needs
    # in order to find the light and dark halves of the pair.
    local base; base="$(icon_base)"

    run install -Dm755 "$REPO_ROOT/bin/tahoe-glass-icon-sync" \
        "$HOME/.local/bin/tahoe-glass-icon-sync"
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: remember icon set $base"
    else
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$base" > "$CONF_DIR/icons"
        printf '%s\n' "${ICONS:-colloid}" > "$CONF_DIR/icon-pack"
    fi

    run install -Dm644 "$REPO_ROOT/systemd/tahoe-glass-icon-sync.service" \
        "$HOME/.config/systemd/user/tahoe-glass-icon-sync.service"
    run systemctl --user daemon-reload
    run systemctl --user enable tahoe-glass-icon-sync.service >/dev/null 2>&1 || true

    # enable alone only arms it for the next login, and there is no reason to
    # make the user log out to see their icons follow the theme.
    if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        run systemctl --user restart tahoe-glass-icon-sync.service 2>/dev/null || true
    fi
    ok "icons follow Settings > Appearance ($(icon_variant "$base" Dark || echo "$base") / $(icon_variant "$base" Light || echo "$base"))"
}

# ------------------------------------------------------------- integration --

flatpak_override() {
    have flatpak || { skip "flatpak not installed"; return 0; }
    step "Letting Flatpak apps read the GTK config"

    # Without this a Flatpak app is sandboxed away from ~/.config/gtk-4.0 and
    # silently keeps stock Adwaita — which looks exactly like the tweaks
    # failing to apply.
    run flatpak override --user \
        --filesystem=xdg-config/gtk-4.0:ro \
        --filesystem=xdg-config/gtk-3.0:ro \
        --filesystem=xdg-data/themes:ro \
        --filesystem=xdg-data/icons:ro
    ok "read-only access granted to themes, icons and GTK config"
}

install_panel_blur_unit() {
    step "Blur My Shell panel blur rebuild"

    if [ "${WANT_PANEL_BLUR_FIX:-1}" != 1 ]; then
        # bms-panel-blur-rebuild is the name this carried before the project
        # was named, and is still enabled on machines set up by hand back then.
        local found=0 u
        for u in tahoe-glass-panel-blur.service bms-panel-blur-rebuild.service; do
            [ -f "$HOME/.config/systemd/user/$u" ] || continue
            found=1
            run systemctl --user disable --now "$u" >/dev/null 2>&1 || true
            run rm -f "$HOME/.config/systemd/user/$u"
            ok "removed $u"
        done
        [ "$found" = 1 ] && run systemctl --user daemon-reload
        skip "not installed (--no-panel-blur-fix)"
        return 0
    fi

    if [ -f "$HOME/.config/systemd/user/bms-panel-blur-rebuild.service" ]; then
        run systemctl --user disable --now bms-panel-blur-rebuild.service >/dev/null 2>&1 || true
        run rm -f "$HOME/.config/systemd/user/bms-panel-blur-rebuild.service"
    fi

    run install -Dm755 "$REPO_ROOT/bin/tahoe-glass-panel-blur" \
        "$HOME/.local/bin/tahoe-glass-panel-blur"
    run install -Dm644 "$REPO_ROOT/systemd/tahoe-glass-panel-blur.service" \
        "$HOME/.config/systemd/user/tahoe-glass-panel-blur.service"
    run systemctl --user daemon-reload
    run systemctl --user enable tahoe-glass-panel-blur.service >/dev/null 2>&1 || true

    # enable only arms it for the next login, and the strip is on screen now.
    if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        run systemctl --user restart tahoe-glass-panel-blur.service 2>/dev/null || true
    fi
    ok "panel blur rebuilds on every monitor change, and once at login"
}

finish() {
    step "Done"
    cat <<EOF

    Log out and back in. Extensions cannot be loaded into a running shell on
    Wayland, so the top bar, the blur and the quick settings will only look
    right on the next session.

    Afterwards:
      tahoe-glass-apply         re-apply the CSS (needed after any theme update)
      ./uninstall.sh            put everything back

    If ~/.local/bin is not on your PATH, add it:
      fish_add_path ~/.local/bin        # fish
      export PATH="\$HOME/.local/bin:\$PATH"   # bash / zsh

EOF
}
