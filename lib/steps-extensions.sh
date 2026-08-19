# shellcheck shell=bash
# aura-glass — installing and enabling the shell extensions.
#
# Three of them cannot come from extensions.gnome.org as they are. Blur My Shell
# is built from a pinned commit because no release carries the popup component,
# plus a patch of this project's own; Open Bar and Custom OSD are built from
# their last upstream commit plus a patch in patches/, because neither has a
# GNOME 50 release. gnome-rounded-blur is not
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
       && patch_stamp_current bms-overview-patch "$REPO_ROOT/patches/$BMS_PATCH" \
       && ext_supports_shell "$EXT_DIR/$BMS_UUID" "$GNOME_MAJOR"; then
        skip "$BMS_UUID already built from $BMS_REF"
        return 0
    fi

    info "no release carries the popup component — building from $BMS_REF + patches/$BMS_PATCH"
    local src="$SRC_CACHE/blur-my-shell"
    if [ -d "$src/.git" ]; then
        run git -C "$src" checkout --quiet -- . 2>/dev/null || true
    fi
    clone_pinned "$BMS_REPO" "$BMS_REF" "$src"

    # Upstream's `blur-on-overview: false` leaves the blur actor in the window,
    # and the overview clones it into every window preview, where it shows a
    # frozen picture of the desktop that changes when the preview is hovered.
    # The patch makes the setting mean what it says. The checkout above is reset
    # by the `git checkout -- .` that precedes it, so this always applies to a
    # clean tree.
    if [ "${DRY_RUN:-0}" != 1 ]; then
        git -C "$src" apply --whitespace=nowarn "$REPO_ROOT/patches/$BMS_PATCH" \
            || die "the Blur My Shell overview patch did not apply — upstream may have moved"
    fi

    local podir=(--podir=../po)
    if ! have msgfmt; then
        warn "msgfmt not found (install gettext) — building without translations"
        podir=()
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: apply patches/$BMS_PATCH, gnome-extensions pack in $src/src, then install the zip"
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
    patch_stamp_write bms-overview-patch "$REPO_ROOT/patches/$BMS_PATCH"
    ok "$BMS_UUID (built from $BMS_REF, with the popup component and the overview patch)"
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
        # Installed, listed, and left off. EXT_NO_AUTO_ENABLE says why: these
        # undo a setting the installer was told to make, so being in a pack
        # buys them an install and not an enable.
        if ext_never_auto_enabled "$u"; then
            skip "$u installed but not enabled — it would overwrite the accent"
            continue
        fi
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

# Whether a UUID is one no pack may switch on. See EXT_NO_AUTO_ENABLE.
ext_never_auto_enabled() {
    local u
    for u in "${EXT_NO_AUTO_ENABLE[@]}"; do
        [ "$u" = "$1" ] && return 0
    done
    return 1
}

# Switch off anything that rewrites the accent behind the installer's back.
#
# Called from apply_gsettings, immediately after the accent is written, because
# that is the moment the two disagree: the wizard asked for one accent by name
# and Auto Accent Colour replaces it with the wallpaper's at the next wallpaper
# change or the next login. Whichever of them runs last is what Settings shows,
# so an accent that is only set is an accent that does not hold.
#
# Switched off rather than fought with: the extension itself stays installed and
# stays on the Extensions page, so putting it back is one switch away for anyone
# who would rather the wallpaper decided.
disable_accent_overriders() {
    local u enabled
    # Someone who turned it on from the Extensions page meant it. That is the
    # one opt-in this respects, and bin/aura-glass-ext writes the memo at the
    # moment of the switch — so the accent above is still written, and the
    # extension is still free to paint over it a moment later.
    if [ -e "$CONF_DIR/accent-from-wallpaper" ]; then
        info "the accent is set to follow the wallpaper — leaving Auto Accent Colour on"
        return 0
    fi
    enabled="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)"
    for u in "${EXT_NO_AUTO_ENABLE[@]}"; do
        case "$enabled" in
            *"'$u'"*) ;;
            *) continue ;;
        esac
        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: disable $u so it cannot overwrite the accent"
            continue
        fi
        # The gsettings key as well as the running shell: `gnome-extensions
        # disable` goes through the shell, and on Wayland it can decline for a
        # UUID this session never loaded — which would leave the extension
        # enabled for the next one, repainting the accent all over again.
        gnome-extensions disable "$u" 2>/dev/null || true
        dequeue_extension "$u" || true
        warn "$u switched off — it repaints the accent from the wallpaper, which would undo the accent just set. Turn it back on from the Extensions page to have the wallpaper decide instead."
    done
}

# The other half of enqueue_extension: take a UUID out of enabled-extensions
# without disturbing what else is there.
dequeue_extension() {
    python3 - "$1" <<'PYDEQ'
import subprocess, sys
uuid = sys.argv[1]
KEY = ["org.gnome.shell", "enabled-extensions"]
cur = subprocess.run(["gsettings", "get", *KEY], capture_output=True, text=True).stdout.strip()
if cur.startswith("@as "):
    cur = cur[4:]
try:
    items = [x.strip().strip("'\"") for x in cur.strip("[]").split(",") if x.strip()]
except Exception:
    items = []
if uuid not in items:
    sys.exit(0)
items = [i for i in items if i != uuid]
new = "[" + ", ".join("'" + i + "'" for i in items) + "]"
subprocess.run(["gsettings", "set", *KEY, new], check=True)
PYDEQ
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

# ---- standing the extensions down ---------------------------------------

# Everything this project ever enables, which is the set it is entitled to
# switch off again. A user's own extensions are outside it and are never
# touched in either direction — that is the whole point of computing the
# intersection rather than disabling a list.
glass_owned_extensions() {
    printf '%s\n' "${EXT_CORE[@]}" openbar@neuromorph "$BMS_UUID" \
        custom-osd@neuromorph "${EXT_EXTRA_ALL[@]}"
}

# Solid mode. The UUIDs that are enabled right now and are ours get switched
# off; nothing else about them is touched, so every one of them keeps its own
# settings and comes back exactly as it was. The record is what makes the way
# back exact rather than a guess at what was on.
stand_down_extensions() {
    step "Standing the extensions down"
    local record enabled u
    local -a disabled_now=()
    record="$CONF_DIR/modes/solid/disabled-extensions"

    enabled="$(gnome-extensions list --enabled 2>/dev/null || true)"
    if [ -z "$enabled" ]; then
        skip "the shell lists nothing enabled — nothing to switch off, any earlier record is left as it is"
        return 0
    fi

    while IFS= read -r u; do
        [ -n "$u" ] || continue
        # Whole-line match against the enabled list, not a substring search —
        # a UUID that merely contains another must never be treated as enabled.
        grep -qxF "$u" <<< "$enabled" || continue

        disabled_now+=("$u")
        run gnome-extensions disable "$u" 2>/dev/null \
            || warn "could not switch $u off — it is still written down, so the way back still tries it"
    done < <(glass_owned_extensions)

    # Nothing of ours was on. On a second solid entry this is the normal case
    # — everything is already off from last time — so any record an earlier
    # run left behind is exactly right as it stands and is not touched: not
    # created, not truncated, not deleted.
    if [ "${#disabled_now[@]}" -eq 0 ]; then
        skip "none of this project's extensions are enabled — any earlier record is left as it is"
        return 0
    fi

    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR/modes/solid"
        # The union of what the record already named and what just went off,
        # never a replacement: a solid stay can span more than one run of this
        # script — some of ours off since an earlier entry, one switched back
        # on by hand in between — and the record has to keep naming everything
        # that is currently off because of this project, or the way back only
        # recovers part of it.
        local -A seen=()
        local -a union=()
        if [ -r "$record" ]; then
            while IFS= read -r u; do
                [ -n "$u" ] || continue
                [ -z "${seen[$u]:-}" ] || continue
                seen[$u]=1
                union+=("$u")
            done < "$record"
        fi
        for u in "${disabled_now[@]}"; do
            [ -z "${seen[$u]:-}" ] || continue
            seen[$u]=1
            union+=("$u")
        done
        printf '%s\n' "${union[@]}" > "$record"
    fi

    ok "${#disabled_now[@]} extension(s) switched off, their settings untouched"
}

# The way back out of solid mode. Exactly what was written down, in the order
# it was written, and then the record goes: it describes a state that no longer
# exists the moment this succeeds.
restore_extensions() {
    local record="$CONF_DIR/modes/solid/disabled-extensions" u back=0
    [ -r "$record" ] || return 0

    # A record that exists but names nothing is not the same as no record at
    # all. stand_down_extensions only ever writes one holding at least the
    # UUIDs it just switched off, so an empty or whitespace-only file here
    # means something upstream went wrong, not that nothing was ever switched
    # off. Deleting it would erase the one clue that happened, so it is left
    # alone instead of being silently swept away as a no-op.
    if ! grep -qE '[^[:space:]]' "$record"; then
        warn "$record exists but names nothing — left alone rather than guessed at"
        return 0
    fi
    step "Switching the extensions back on"

    while IFS= read -r u; do
        [ -n "$u" ] || continue
        if [ ! -d "$EXT_DIR/$u" ] && [ ! -d "/usr/share/gnome-shell/extensions/$u" ]; then
            skip "$u is no longer installed"
            continue
        fi
        if run gnome-extensions enable "$u" 2>/dev/null; then
            back=$((back + 1))
            continue
        fi
        # The same fallback enable_extensions uses: on Wayland the running
        # shell will not load a UUID it did not start with, so it goes into
        # enabled-extensions for the next session instead.
        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: add $u to enabled-extensions for the next session"
        elif enqueue_extension "$u"; then
            ok "$u queued — active after logout"
            back=$((back + 1))
        else
            warn "could not switch $u back on"
        fi
    done < "$record"

    [ "${DRY_RUN:-0}" = 1 ] || rm -f "$record"
    ok "$back extension(s) back on"
}

# ------------------------------------------------------------------- icons --
