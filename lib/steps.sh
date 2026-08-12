# shellcheck shell=bash
# tahoe-glass — the individual install steps.

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

    if [ -d "$EXT_DIR/$uuid" ] && ext_supports_shell "$EXT_DIR/$uuid" "$GNOME_MAJOR" \
       && patch_stamp_current openbar-patch "$REPO_ROOT/patches/openbar-gnome50.patch" \
       && [ "${FORCE:-0}" != 1 ]; then
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
    patch_stamp_write openbar-patch "$REPO_ROOT/patches/openbar-gnome50.patch"
    ok "$uuid (patched for GNOME $GNOME_MAJOR)"
}

# Custom OSD is what turns the volume and brightness popup into the bar on its
# own. Upstream's last release is for GNOME 46 and its last commit does not run
# on 50 — the ShellBlurEffect:sigma property, the meta_*_clutter_debug_flags()
# calls and OsdWindowManager.show()'s signature have all gone since. The patch
# in patches/ fixes exactly those and nothing else. The blur behind the pill,
# and the rounding of it, come from Blur My Shell's popup component.
install_custom_osd() {
    local uuid="custom-osd@neuromorph"

    if [ "${WANT_OSD:-1}" != 1 ]; then
        step "Custom OSD"
        skip "not installed (--no-osd)"
        return 0
    fi

    if [ -d "$EXT_DIR/$uuid" ] && ext_supports_shell "$EXT_DIR/$uuid" "$GNOME_MAJOR" \
       && patch_stamp_current custom-osd-patch "$REPO_ROOT/patches/custom-osd-gnome50.patch" \
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
    patch_stamp_write custom-osd-patch "$REPO_ROOT/patches/custom-osd-gnome50.patch"
    ok "$uuid (patched for GNOME $GNOME_MAJOR)"
}

# Blur My Shell gets rounded corners on a *dynamic* blur from Blur.BlurEffect,
# which comes from this small C library — a vendored copy of gnome-shell's own
# shell-blur-effect.c with a corner mask. Without it the popup blur falls back
# to static, which still rounds (see apply_popup_blur); this is the upgrade
# from "blurred wallpaper" to "blurred whatever is actually behind the popup".
#
# It is the only thing this project installs outside $HOME, so it is the only
# step that asks first — and it asks even under --yes, because agreeing to a
# theme installer is not the same as agreeing to a package from the AUR.
#
# It hard-pins libmutter-18, so every mutter update breaks it until it is
# rebuilt. That failure is silent by design upstream: Blur My Shell just falls
# back to Shell.BlurEffect. rounded_blur_staleness_check is what makes it loud.
install_rounded_blur() {
    step "Rounded corners for dynamic blur"

    if [ "${WANT_ROUNDED_BLUR:-1}" != 1 ]; then
        skip "not installed (--no-rounded-blur) — popup blur stays static"
        return 0
    fi

    if gjs -c 'imports.gi.Blur;' >/dev/null 2>&1 && [ "${FORCE:-0}" != 1 ]; then
        skip "gnome-rounded-blur already installed"
        rounded_blur_stamp
        return 0
    fi

    local helper='' h
    for h in paru yay; do have "$h" && { helper="$h"; break; }; done

    if [ -z "$helper" ] && ! have meson; then
        warn "neither an AUR helper (paru/yay) nor meson is installed."
        warn "Popup blur still works and its corners are still round — it just"
        warn "samples the wallpaper instead of the window behind it."
        return 0
    fi

    local cmd
    if [ -n "$helper" ]; then
        cmd="$helper -S --needed gnome-rounded-blur"
    else
        cmd="meson setup --prefix=/usr build && sudo meson install -C build"
    fi

    info "this is the one part of tahoe-glass that installs outside \$HOME:"
    info "    $cmd"
    if ! confirm_always "Install gnome-rounded-blur? It needs root."; then
        skip "not installed — popup blur stays static, and still rounded"
        return 0
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: $cmd"
        return 0
    fi

    if [ -n "$helper" ]; then
        "$helper" -S --needed gnome-rounded-blur \
            || { warn "the AUR build failed — popup blur stays static"; return 0; }
    else
        local src="$SRC_CACHE/gnome-rounded-blur"
        clone_pinned "$ROUNDEDBLUR_REPO" "$ROUNDEDBLUR_REF" "$src"
        ( cd "$src" && rm -rf build \
            && meson setup --prefix=/usr build \
            && meson compile -C build \
            && sudo meson install -C build ) \
            || { warn "the meson build failed — popup blur stays static"; return 0; }
    fi

    if gjs -c 'imports.gi.Blur;' >/dev/null 2>&1; then
        rounded_blur_stamp
        ok "gnome-rounded-blur installed — popup blur can be dynamic"
        info "it is compiled against this mutter, so re-run with --rounded-blur --force after a mutter update"
    else
        warn "installed, but the shell still cannot import gi://Blur"
    fi
}

# Records the mutter it was built against, which is what makes staleness
# detectable later.
rounded_blur_stamp() {
    [ "${DRY_RUN:-0}" = 1 ] && return 0
    mkdir -p "$CONF_DIR"
    printf '%s\n' "$(pkg-config --modversion libmutter-18 2>/dev/null || gnome_major)" \
        > "$CONF_DIR/rounded-blur"
}

# Blur My Shell publishes the answer itself: it writes rounded-blur-found at
# every enable. If this machine installed the library but the shell is no
# longer finding it, mutter has moved and the library needs rebuilding.
rounded_blur_staleness_check() {
    [ -f "$CONF_DIR/rounded-blur" ] || return 0
    local found
    found="$(dconf read /org/gnome/shell/extensions/blur-my-shell/rounded-blur-found 2>/dev/null || true)"
    [ "$found" = false ] || return 0
    warn "gnome-rounded-blur is installed here, but the shell is not finding it."
    warn "Mutter has probably been updated — it has to be rebuilt against it:"
    warn "    ./install.sh --rounded-blur --force"
    warn "Until then the popup blur falls back to static. Still rounded, but it"
    warn "samples the wallpaper rather than the window behind it."
}

install_extensions() {
    step "Installing shell extensions"
    local u
    for u in "${EXT_CORE[@]}"; do install_ext_ego "$u" || true; done
    # Solid mode does not install Blur My Shell at all. Disabling its components
    # would leave the extension loaded and still building one background actor
    # per surface; not installing it is what actually removes the cost.
    if [ "${WANT_BLUR:-1}" = 1 ]; then
        install_bms
    else
        skip "$BMS_UUID left out (--no-blur)"
    fi
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
    # enabled whichever source install_bms took it from — and so that solid
    # mode can leave it out without editing the shared list.
    local want=("${EXT_CORE[@]}" openbar@neuromorph) u
    if [ "${WANT_BLUR:-1}" = 1 ]; then
        want+=("$BMS_UUID")
    fi
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

# css/gtk4-transparency.css is written at the shipped level — the sheet is
# readable on its own that way. That level is TOKEN_APP_TRANSPARENCY_SHIPPED in
# tokens/tokens.sh, which is also what the scaling below measures from, so the
# two cannot disagree. --app-transparency N rewrites both spellings of
# every value in the installed copy, scaling the whole ladder rather than
# flattening it: the header bar is meant to stay a little more transparent than
# the window and the content view a little less, at any setting.
install_transparency_css() {
    local level="${APP_TRANSPARENCY:-0}"

    if [ "$level" = 0 ]; then
        run rm -f "$CONF_DIR/gtk4-transparency.css"
        [ "${DRY_RUN:-0}" = 1 ] || { mkdir -p "$CONF_DIR"; printf '0\n' > "$CONF_DIR/app-transparency"; }
        return 0
    fi

    run install -Dm644 "$REPO_ROOT/css/gtk4-transparency.css" "$CONF_DIR/gtk4-transparency.css"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: rewrite the transparency sheet to $level"
        return 0
    fi

    python3 - "$CONF_DIR/gtk4-transparency.css" "$level" \
             "$TOKEN_APP_TRANSPARENCY_SHIPPED" <<'PY'
import re, sys
path, want = sys.argv[1], float(sys.argv[2])
SHIPPED = float(sys.argv[3])

def scale(base):
    # Keep each surface's distance from opaque in proportion, so the ladder
    # written into the sheet survives being retuned.
    if want >= 1.0:
        return 1.0
    return max(0.0, min(1.0, 1 - (1 - base) * (1 - want) / (1 - SHIPPED)))

css = open(path, encoding="utf-8").read()
css = re.sub(r"alpha\((@[a-z_]+), ([0-9.]+)\)",
             lambda m: "alpha(%s, %.2f)" % (m.group(1), scale(float(m.group(2)))), css)
css = re.sub(r"(var\(--[a-z-]+\)) ([0-9.]+)%",
             lambda m: "%s %g%%" % (m.group(1), round(scale(float(m.group(2)) / 100) * 100, 1)), css)
open(path, "w", encoding="utf-8").write(css)
PY

    mkdir -p "$CONF_DIR"
    printf '%s\n' "$level" > "$CONF_DIR/app-transparency"
    ok "app windows translucent at $level (remembered for later runs)"
}

install_css() {
    step "Installing the CSS tweaks"

    # The shell and gtk4 sheets are split by concern, and the numeric prefix is
    # the cascade order tahoe-glass-apply concatenates them in. Copy whatever
    # css/ actually holds rather than naming each one twice.
    local sheet
    for sheet in "$REPO_ROOT"/css/shell-[0-9][0-9]-*.css \
                 "$REPO_ROOT"/css/gtk4-[0-9][0-9]-*.css; do
        run install -Dm644 "$sheet" "$CONF_DIR/$(basename "$sheet")"
    done
    run install -Dm644 "$REPO_ROOT/css/gtk3-tweaks.css"  "$CONF_DIR/gtk3-tweaks.css"
    run install -Dm755 "$REPO_ROOT/bin/tahoe-glass-apply" "$HOME/.local/bin/tahoe-glass-apply"

    # Upgrading from a version that shipped one sheet per target. Both names are
    # gone from tahoe-glass-apply's lists, so leaving them would only be dead
    # weight — but they were also the file the density block used to be appended
    # to, and that copy would still be found by an older apply script.
    run rm -f "$CONF_DIR/shell-tweaks.css" "$CONF_DIR/gtk4-tweaks.css"

    # Installed or removed rather than switched on at read time: tahoe-glass-apply
    # concatenates whatever it finds in $CONF_DIR and has no way to know which
    # options this install was given.
    # --no-blur swaps the translucent ladder for opaque surfaces. Installed or
    # removed rather than switched on at read time, for the same reason as the
    # sheets below: tahoe-glass-apply concatenates what it finds and cannot know
    # which options this install was given.
    if [ "${WANT_BLUR:-1}" = 1 ]; then
        run rm -f "$CONF_DIR/shell-80-solid.css"
    else
        run install -Dm644 "$REPO_ROOT/css/shell-80-solid.css" "$CONF_DIR/shell-80-solid.css"
    fi

    if [ "${WANT_POPUP_BLUR:-1}" = 1 ]; then
        run install -Dm644 "$REPO_ROOT/css/shell-popup-blur.css" "$CONF_DIR/shell-popup-blur.css"
    else
        run rm -f "$CONF_DIR/shell-popup-blur.css"
    fi
    install_transparency_css
    ok "css -> $CONF_DIR"
    ok "re-apply command -> ~/.local/bin/tahoe-glass-apply"

    # Generated rather than kept in css/, so it is written for whatever screen
    # the installer is actually run on. It gets its own sheet — prefix 90, so it
    # lands after every hand-written shell sheet and overrides them — rather
    # than being appended to one of them: an appended block would be silently
    # doubled the next time this ran, and would be lost the moment the sheet it
    # was appended to got recopied.
    local ppi extra
    ppi="$(measure_logical_ppi || true)"
    run rm -f "$CONF_DIR/shell-90-density.css"
    if [ -z "$ppi" ]; then
        skip "could not measure display density — panel sizes left as tuned"
    else
        extra="$(density_css "$ppi")"
        if [ -z "$extra" ]; then
            ok "display is ${ppi} logical PPI — no scaling needed"
        elif [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: scale panel icons for ${ppi} logical PPI"
        else
            printf '%s\n' "$extra" > "$CONF_DIR/shell-90-density.css"
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

    # Applied over the top rather than as a separate preset, so solid mode is
    # one overlay to read and to review rather than a second full copy of every
    # key that would then have to be kept in step with core.ini.
    if [ "${WANT_BLUR:-1}" != 1 ]; then
        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: dconf load /org/gnome/shell/extensions/ < dconf/solid.ini"
        else
            dconf load /org/gnome/shell/extensions/ < "$REPO_ROOT/dconf/solid.ini" \
                || die "dconf load of the solid preset failed"
        fi
        ok "solid mode loaded — no blur, opaque surfaces"
    fi

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
    apply_popup_blur
    apply_app_opacity
    sync_osd_profile
}

# [applications] opacity dims the whole window actor, text included. That is
# the only transparency available while GTK paints an opaque background, but
# once GTK is doing it properly the two multiply and the text goes muddy — so
# the actor goes back to fully opaque and the stylesheet does the work alone.
apply_app_opacity() {
    [ "${APP_TRANSPARENCY:-0}" != 0 ] || return 0
    run dconf write /org/gnome/shell/extensions/blur-my-shell/applications/opacity 255
    ok "window actor opacity back to 255 — GTK is doing the transparency now"
}

# The popup keys themselves ship in dconf/core.ini so the whole preset stays
# readable in one file. Two things cannot live there:
#
# The on/off choice, because dconf load rewrites the section on every run — a
# flagless re-install would quietly turn popup blur back on over a deliberate
# --no-popup-blur. Same reason --grain and --icons are remembered.
#
# static-blur, because the right value depends on the machine. Rounded corners
# on a dynamic blur need the gnome-rounded-blur library; a static blur rounds
# itself. So when the library is missing this falls back to static, and the
# corners stay round instead of going square. It self-heals: install the
# library, re-run, and it flips back to dynamic.
apply_popup_blur() {
    local base=/org/gnome/shell/extensions/blur-my-shell
    local want="${WANT_POPUP_BLUR:-1}" memo="$CONF_DIR/popup-blur"

    if [ -z "${POPUP_BLUR_EXPLICIT:-}" ] && [ -r "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
        want="${want:-1}"
    fi

    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi

    if [ "$want" != 1 ]; then
        run dconf write "$base/popup/blur" false
        skip "popup blur off — menus keep the flat translucent look"
        return 0
    fi

    # Written by Blur My Shell at every enable, so on a first install — before
    # the shell has ever loaded this build — it is absent and we start static.
    # The next run picks the library up.
    local found
    found="$(dconf read "$base/rounded-blur-found" 2>/dev/null || true)"

    run dconf write "$base/popup/blur" true
    if [ "$found" = true ]; then
        run dconf write "$base/popup/static-blur" false
        ok "popup blur on, dynamic — it tracks whatever is behind the popup"
    else
        run dconf write "$base/popup/static-blur" true
        ok "popup blur on, static — rounded, but sampling the wallpaper"
        info "install gnome-rounded-blur (--rounded-blur) for blur that tracks windows"
    fi
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

    # This unit exists to toggle Blur My Shell's panel blur off and on once the
    # session has settled, so the actor is rebuilt against correct geometry.
    # With no Blur My Shell there is no actor and nothing to rebuild, so in
    # solid mode it is a timer that waits twelve seconds after every login to
    # do nothing. Checked here rather than in the flag parsing so that the flag
    # order cannot defeat it: --no-blur --full would otherwise turn it back on.
    if [ "${WANT_BLUR:-1}" != 1 ]; then
        WANT_PANEL_BLUR_FIX=0
    fi

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
    # Runs whether or not --rounded-blur was passed, so a machine whose library
    # went stale after a mutter update finds out on the next install either way.
    rounded_blur_staleness_check
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
