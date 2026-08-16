# shellcheck shell=bash
# aura-glass — installing and enabling the shell extensions.
#
# Three of them cannot come from extensions.gnome.org as they are. Blur My Shell
# is built from a pinned commit because no release carries the popup component;
# Open Bar and Custom OSD are built from their last upstream commit plus a patch
# in patches/, because neither has a GNOME 50 release. gnome-rounded-blur is not
# an extension at all but the C library that lets the popup blur be dynamic, and
# it is the only thing this project installs outside $HOME.
#
# Sourced by install.sh. See lib/steps.sh for the pins these use.

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
# the css/shell-NN-*.css sheets paint their own flat translucency behind them,
# and why the OSD used to carry a hand-rolled corner shader. Upstream's master has the
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
    if [ -d "$src/.git" ]; then
        run git -C "$src" checkout --quiet -- . 2>/dev/null || true
    fi
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

    info "this is the one part of aura-glass that installs outside \$HOME:"
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

    if [ "${WANT_EXTRAS:-0}" = 1 ] && [ "${#EXT_EXTRA[@]}" -gt 0 ]; then
        step "Installing optional extensions (${#EXT_EXTRA[@]} selected)"
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
    if [ "${WANT_EXTRAS:-0}" = 1 ] && [ "${#EXT_EXTRA[@]}" -gt 0 ]; then
        want+=("${EXT_EXTRA[@]}")
    fi

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
