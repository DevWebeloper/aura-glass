# shellcheck shell=bash
# aura-glass — installing and enabling the shell extensions.
#
# Three of them cannot come from extensions.gnome.org as they are. Blur My Shell
# is built from a pinned commit with overview, subwindow and notification
# patches of this project's own; Open Bar and Custom OSD are built from
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
versions = [str(v).split(".")[0] for v in d.get("shell-version", [])]
target = str(sys.argv[1])
if target in versions:
    sys.exit(0)
if target == "51" and "50" in versions:
    sys.exit(0)
sys.exit(1)
' "$major"
}

ensure_extension_supports_shell() {
    local target="$EXT_DIR/$1"
    [ -f "$target/metadata.json" ] || return 0
    python3 - "$target/metadata.json" "${GNOME_MAJOR:-}" <<'PY' || true
import sys, json
meta_path, major = sys.argv[1], str(sys.argv[2])
if not major:
    sys.exit(0)
try:
    with open(meta_path, "r", encoding="utf-8") as f:
        meta = json.load(f)
    shells = [str(v).split(".")[0] for v in meta.get("shell-version", [])]
    if major not in shells:
        meta.setdefault("shell-version", []).append(major)
        with open(meta_path, "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)
except Exception:
    pass
PY
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
        ensure_extension_supports_shell "$uuid"
        ok "$uuid"
    fi
    rm -rf "$tmp"
    return "$rc"
}

# Blur My Shell v73 carries the popup component upstream: menus, quick
# settings, notifications, dialogs and the OSD get blur directly. We build from
# pinned release v73 with our overview, subwindow and notification patches
# applied on top. gnome-extensions pack and gnome-extensions install both write
# under $HOME, so this needs no root.
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

    # Probe for the component and check the stamp — the directory test matters
    # on its own because ./uninstall.sh --extensions removes the extension but
    # leaves $CONF_DIR.
    if [ "${FORCE:-0}" != 1 ] \
       && [ -f "$EXT_DIR/$BMS_UUID/components/popup/index.js" ] \
       && [ "$(cat "$CONF_DIR/bms-ref" 2>/dev/null || true)" = "$BMS_REF" ] \
       && patch_stamp_current bms-overview-patch "$REPO_ROOT/patches/$BMS_PATCH" \
       && patch_stamp_current bms-subwindow-patch "$REPO_ROOT/patches/$BMS_SUBWIN_PATCH" \
       && patch_stamp_current bms-notification-patch "$REPO_ROOT/patches/$BMS_NOTIF_PATCH" \
       && ext_supports_shell "$EXT_DIR/$BMS_UUID" "$GNOME_MAJOR"; then
        skip "$BMS_UUID already built from $BMS_REF"
        return 0
    fi

    info "building Blur My Shell from $BMS_REF + patches/$BMS_PATCH + patches/$BMS_SUBWIN_PATCH + patches/$BMS_NOTIF_PATCH"
    local src="$SRC_CACHE/blur-my-shell"
    if [ -d "$src/.git" ]; then
        run git -C "$src" checkout --quiet -- . 2>/dev/null || true
    fi
    clone_pinned "$BMS_REPO" "$BMS_REF" "$src"

    # Upstream's `blur-on-overview: false` leaves the blur actor in the window,
    # and the overview clones it into every window preview, where it shows a
    # frozen picture of the desktop that changes when the preview is hovered.
    # The overview patch makes the setting mean what it says. The subwindow
    # patch makes check_blur match a window's whole transient-for chain and
    # its GTK application id, not just its own wm_class, and adds ATTACHED and
    # UTILITY to the frame types it accepts — without it a blurred app's own
    # dialogs and tool palettes stay unblurred. Order matters: the second
    # patch's hunks are offset against the first's output. The checkout above
    # is reset by the `git checkout -- .` that precedes it, so this always
    # applies to a clean tree.
    if [ "${DRY_RUN:-0}" != 1 ]; then
        git -C "$src" apply --whitespace=nowarn "$REPO_ROOT/patches/$BMS_PATCH" \
            || die "the Blur My Shell overview patch did not apply — upstream may have moved"
        git -C "$src" apply --whitespace=nowarn "$REPO_ROOT/patches/$BMS_SUBWIN_PATCH" \
            || die "the Blur My Shell subwindow patch did not apply — upstream may have moved"
        git -C "$src" apply --whitespace=nowarn "$REPO_ROOT/patches/$BMS_NOTIF_PATCH" \
            || die "the Blur My Shell notification patch did not apply — upstream may have moved"
    fi

    local podir=(--podir=../po)
    if ! have msgfmt; then
        warn "msgfmt not found (install gettext) — building without translations"
        podir=()
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: apply patches/$BMS_PATCH, patches/$BMS_SUBWIN_PATCH and patches/$BMS_NOTIF_PATCH, gnome-extensions pack in $src/src, then install the zip"
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
    rm -rf "$HOME/.local/share/gnome-shell/extension-updates/$BMS_UUID"
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
    patch_stamp_write bms-subwindow-patch "$REPO_ROOT/patches/$BMS_SUBWIN_PATCH"
    patch_stamp_write bms-notification-patch "$REPO_ROOT/patches/$BMS_NOTIF_PATCH"
    ok "$BMS_UUID (built from $BMS_REF, with the popup component, the overview patch, the subwindow patch, and the notification patch)"
}

# aura-glass-blur@aura-glass.local — "Blur This App" in the window right-click
# menu, editing the same Blur My Shell allow/block lists apply_app_blur does.
# First-party, so this is a straight copy from extensions/ rather than a git
# clone — there is no upstream to pin. It ships no gsettings schema of its
# own, so there is nothing here to compile.
#
# Skipped along with Blur My Shell itself: the extension already adds nothing
# to the menu when BMS's schema is not there (see _openBmsApplicationsSettings
# in its own source), so installing it under --no-blur would only be dead
# weight enabled for no reason.
install_aura_ext() {
    local uuid="$AURA_EXT_UUID"

    # The helper reads this memo itself and adds or drops "Blur This App"
    # live, so --no-window-menu needs no reload. Written only when a flag
    # chose it, like the OSD: an unanswered default keeps the menu.
    if remembering && [ -n "${WINDOW_MENU_EXPLICIT:-}" ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "${WANT_WINDOW_MENU:-1}" > "$CONF_DIR/window-menu"
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: copy extensions/$uuid to $EXT_DIR/$uuid"
        return 0
    fi

    local changed=0
    local target="$EXT_DIR/$uuid"
    if [ ! -d "$target" ] || ! diff -rq "$REPO_ROOT/extensions/$uuid" "$target" >/dev/null 2>&1; then
        changed=1
        mkdir -p "$EXT_DIR"
        rm -rf "$target"
        cp -a "$REPO_ROOT/extensions/$uuid" "$target"
    fi

    if [ "$changed" = 1 ]; then
        # Reload the first-party extension after source changes, with next-login fallback
        if gnome-extensions list --enabled 2>/dev/null | grep -qxF "$uuid"; then
            if ! { run gnome-extensions disable "$uuid" 2>/dev/null && run gnome-extensions enable "$uuid" 2>/dev/null; }; then
                info "$uuid live reload refused by GNOME Shell — will reload on next login"
            fi
        fi
    fi
}

# Custom OSD is what turns the volume and brightness popup into the bar on its
# own. Upstream's last release is for GNOME 46 and its last commit does not run
# on 50 — the ShellBlurEffect:sigma property, the meta_*_clutter_debug_flags()
# calls and OsdWindowManager.show()'s signature have all gone since. The patch
# in patches/ fixes exactly those and nothing else. The blur behind the pill,
# and the rounding of it, come from Blur My Shell's popup component.
install_custom_osd() {
    local uuid="custom-osd@neuromorph"

    # Remembered when it was answered, for the same reason as the pack.
    if remembering && [ -n "${OSD_EXPLICIT:-}" ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "${WANT_OSD:-1}" > "$CONF_DIR/osd"
    fi

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

    # Only a typed --rounded-blur / --no-rounded-blur is a choice. --no-blur
    # forces the variable to 0 for a Performance run, and recording that would
    # keep the library off after switching back to Frosted. Not "rounded-blur":
    # that file is the mutter-version stamp, and its presence means installed.
    if remembering && [ -n "${ROUNDED_BLUR_EXPLICIT:-}" ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "${WANT_ROUNDED_BLUR:-1}" > "$CONF_DIR/rounded-blur-choice"
    fi

    if [ "${WANT_ROUNDED_BLUR:-1}" != 1 ]; then
        skip "not installed (--no-rounded-blur)"
        return 0
    fi

    if LD_LIBRARY_PATH="/usr/lib/mutter-$GNOME_MAJOR:/usr/lib/mutter-18:${LD_LIBRARY_PATH:-}" gjs -c 'const Blur = imports.gi.Blur; void Blur.BlurEffect;' >/dev/null 2>&1 && [ "${FORCE:-0}" != 1 ]; then
        skip "gnome-rounded-blur already installed and functional"
        rounded_blur_stamp
        return 0
    fi

    # A build in ~/.local, from releases that compiled one there, never loads:
    # the shell searches neither ~/.local/lib nor ~/.local/share/girepository-1.0
    # (KI-12). It goes, so nothing is left that looks like it might.
    if [ -e "$HOME/.local/lib/libblur-effect-1.0.so.1" ] \
        || [ -e "$HOME/.local/share/girepository-1.0/Blur-1.0.typelib" ]; then
        run rm -f "$HOME/.local/lib/libblur-effect-1.0.so" \
                  "$HOME/.local/lib/libblur-effect-1.0.so.1" \
                  "$HOME/.local/share/girepository-1.0/Blur-1.0.typelib"
        [ "${DRY_RUN:-0}" = 1 ] || info "removed the old ~/.local build, which the shell could not load"
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: install gnome-rounded-blur system-wide (AUR helper or meson + sudo)"
        return 0
    fi

    local helper='' h
    for h in paru yay; do have "$h" && { helper="$h"; break; }; done

    if [ -z "$helper" ] && ! have meson; then
        warn "no AUR helper (paru, yay) or meson found to build gnome-rounded-blur."
        warn "Popup blur remains dynamic with corner shader fallback."
        return 0
    fi

    local cmd
    if [ -n "$helper" ]; then
        cmd="$helper -S --needed gnome-rounded-blur"
    else
        cmd="meson setup --prefix=/usr build && sudo meson install -C build"
    fi

    info "building gnome-rounded-blur:"
    info "    $cmd"

    if [ -n "$helper" ]; then
        "$helper" -S --needed gnome-rounded-blur \
            || { warn "the AUR build failed — popup blur uses corner shader fallback"; return 0; }
    else
        local src="$SRC_CACHE/gnome-rounded-blur"
        clone_pinned "$ROUNDEDBLUR_REPO" "$ROUNDEDBLUR_REF" "$src"
        ( cd "$src" && rm -rf build \
            && meson setup --prefix=/usr build \
            && meson compile -C build \
            && sudo meson install -C build ) \
            || { warn "the meson build failed — popup blur uses corner shader fallback"; return 0; }
    fi

    rounded_blur_stamp
    ok "gnome-rounded-blur installed"
}

# Whether install_rounded_blur may reach for sudo, so install.sh only asks for
# a password up front when it will be used (KI-11). An AUR helper asks for its
# own; only the meson fallback runs `sudo meson install`. There is no rootless
# build: one in ~/.local is never found by the shell (KI-12).
rounded_blur_needs_root() {
    [ "${WANT_ROUNDED_BLUR:-1}" = 1 ] || return 1
    if LD_LIBRARY_PATH="/usr/lib/mutter-$GNOME_MAJOR:/usr/lib/mutter-18:${LD_LIBRARY_PATH:-}" gjs -c 'const Blur = imports.gi.Blur; void Blur.BlurEffect;' >/dev/null 2>&1 && [ "${FORCE:-0}" != 1 ]; then
        return 1
    fi
    have paru && return 1
    have yay && return 1
    have meson
}

# Records the mutter it was built against, which is what makes staleness
# detectable later.
rounded_blur_stamp() {
    [ "${DRY_RUN:-0}" = 1 ] && return 0
    mkdir -p "$CONF_DIR"
    printf '%s\n' "$(pkg-config --modversion "libmutter-$GNOME_MAJOR" 2>/dev/null || pkg-config --modversion libmutter-18 2>/dev/null || gnome_major)" \
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
    warn "Mutter has probably been updated — it can be rebuilt against it:"
    warn "    ./install.sh --rounded-blur --force"
    warn "Popup blur remains dynamic with corner shader fallback."
}

install_extensions() {
    step "Installing shell extensions"
    # The pack is a choice with no flag to reproduce it from on an update or a
    # full reinstall, so it is remembered here, where it is applied, and only
    # when it was chosen: an unanswered default stays whatever the release's
    # Recommended pack is. An empty file is Minimal.
    if remembering && [ -n "${EXT_PACK_EXPLICIT:-}" ]; then
        mkdir -p "$CONF_DIR"
        if [ "${WANT_EXTRAS:-0}" = 1 ]; then
            ( IFS=,; printf '%s\n' "${EXT_EXTRA[*]}" ) > "$CONF_DIR/extension-pack"
        else
            : > "$CONF_DIR/extension-pack"
        fi
    fi
    # Allow safe extensions that haven't updated metadata yet for newer GNOME releases to load.
    run gsettings set org.gnome.shell disable-extension-version-validation true
    disable_retired_extensions

    declare -g -A PRE_INSTALLED_EXTS=()
    local d
    for d in "$EXT_DIR"/* /usr/share/gnome-shell/extensions/*; do
        [ -d "$d" ] && PRE_INSTALLED_EXTS["$(basename "$d")"]=1
    done

    local u
    for u in "${EXT_CORE[@]}"; do install_ext_ego "$u" || true; done
    # Blur My Shell is always installed so that switching between frosted and
    # performance mode in the Aura Glass app or via flags works without
    # needing a full re-install.
    install_bms
    install_aura_ext
    install_custom_osd

    if [ "${WANT_EXTRAS:-0}" = 1 ] && [ "${#EXT_EXTRA[@]}" -gt 0 ]; then
        step "Installing optional extensions (${#EXT_EXTRA[@]} selected)"
        for u in "${EXT_EXTRA[@]}"; do install_ext_ego "$u" || true; done
    fi
    patch_copyous_extension
}

patch_copyous_extension() {
    local target="$EXT_DIR/copyous@boerdereinar.dev"
    [ -d "$target" ] || return 0
    local file="$target/lib/ui/items/clipboardItem.js"
    [ -f "$file" ] || return 0
    if grep -q "Shell.GLSLEffect || Clutter.Effect" "$file"; then
        return 0
    fi
    info "Patching Copyous for GNOME 50/51 GLSLEffect compatibility..."
    python3 - "$file" "$target/metadata.json" <<'PY' || true
import sys, json

js_path, meta_path = sys.argv[1], sys.argv[2]
try:
    with open(js_path, "r", encoding="utf-8") as f:
        content = f.read()
    if "const BaseEffect" not in content and "let HoleEffect = class HoleEffect extends Shell.GLSLEffect" in content:
        content = content.replace(
            "let HoleEffect = class HoleEffect extends Shell.GLSLEffect {",
            "const BaseEffect = Shell.GLSLEffect || Clutter.Effect;\nlet HoleEffect = class HoleEffect extends BaseEffect {"
        )
        content = content.replace(
            "this._sizeLocation = this.get_uniform_location('size');",
            "if (Shell.GLSLEffect) {\n\t\t\tthis._sizeLocation = this.get_uniform_location('size');"
        )
        content = content.replace(
            "target.connect('notify::allocation', () => this.queue_repaint());",
            "target.connect('notify::allocation', () => this.queue_repaint());\n\t\t}"
        )
        content = content.replace(
            "vfunc_paint_target(node, paintContext) {",
            "vfunc_paint_target(node, paintContext) {\n\t\tif (!Shell.GLSLEffect) return;"
        )
        content = content.replace(
            "vfunc_build_pipeline() {",
            "vfunc_build_pipeline() {\n\t\tif (!Shell.GLSLEffect) return;"
        )
        with open(js_path, "w", encoding="utf-8") as f:
            f.write(content)
except Exception:
    pass

try:
    with open(meta_path, "r", encoding="utf-8") as f:
        meta = json.load(f)
    shells = meta.get("shell-version", [])
    changed = False
    for v in ["50", "51"]:
        if v not in shells:
            shells.append(v)
            changed = True
    if changed:
        meta["shell-version"] = shells
        with open(meta_path, "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)
except Exception:
    pass
PY
}

# dconf can reach the running extension after it has constructed its components:
# on a reload, PipelinesManager may still have only the default pipeline when
# OverviewBlur creates its background actor. The later pipeline update adds the
# named pipeline to the settings object but does not recreate that actor, so the
# overview stays unblurred and logs "pipeline ... not found". Refresh only an
# already-active instance after load_dconf has finished writing the complete
# preset; a disabled instance is enabled later by enable_extensions with the
# finished settings already in place.
refresh_bms_after_dconf() {
    [ "${WANT_BLUR:-1}" = 1 ] || return 0
    # The adaptive transition reaches here through load_dconf too, but it
    # loads no pipelines: it only flips the keys a mode owns, live. A restore
    # runs with WANT_BLUR=1, and on GNOME 48-50 would otherwise cycle the
    # extension, a visible flicker on every trigger clearing.
    [ -z "${ADAPTIVE_BLUR:-}" ] || return 0
    [ -d "$EXT_DIR/$BMS_UUID" ] || return 0
    gnome-extensions info "$BMS_UUID" 2>/dev/null | grep -q 'State: ACTIVE' || return 0

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: refresh active $BMS_UUID after loading its pipelines"
        return 0
    fi

    # In GNOME Shell 51+, dynamically disabling Blur My Shell while actors are live
    # causes Mutter/Clutter to segfault in clutter_actor_meta_get_actor during
    # actor disposal, crashing the compositor and killing the session.
    # Pipelines are updated live via dconf without unloading the extension.
    local major="${GNOME_MAJOR:-}"
    [ -n "$major" ] || major="$(gnome_major 2>/dev/null || echo 0)"
    if [ "$major" -ge 51 ]; then
        skip "$BMS_UUID not reloaded on GNOME $major (it would crash Mutter); its pipelines update live"
        return 0
    fi

    if ! run gnome-extensions disable "$BMS_UUID" 2>/dev/null; then
        warn "could not refresh active $BMS_UUID after loading its pipelines"
        return 0
    fi
    # Give the shell one turn to tear down the old actors and D-Bus object before
    # enabling the extension again; otherwise the reload can race its cleanup.
    sleep 1
    if ! run gnome-extensions enable "$BMS_UUID" 2>/dev/null; then
        warn "could not re-enable $BMS_UUID after loading its pipelines"
        return 0
    fi
    ok "$BMS_UUID refreshed after loading its pipelines"
}

enable_extensions() {
    step "Enabling extensions"
    local is_update=0
    if [ -f "$CONF_DIR/repo-path" ] || [ -f "$CONF_DIR/accent" ]; then
        is_update=1
    fi

    # $BMS_UUID is named explicitly rather than left in EXT_CORE so that it is
    # enabled whichever source install_bms took it from.
    local want=("${EXT_CORE[@]}" "$AURA_EXT_UUID" "$BMS_UUID") u
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
        if is_in_disabled_extensions "$u"; then
            skip "$u is in disabled-extensions — keeping disabled"
            continue
        fi
        if [ "$is_update" = 1 ] && [ -n "${PRE_INSTALLED_EXTS[$u]:-}" ] && ! is_extension_enabled "$u"; then
            if [ "$u" != "tiling-assistant@leleat-on-github" ]; then
                skip "$u was disabled by the user — keeping disabled"
                continue
            fi
        fi
        dequeue_from_disabled_extensions "$u" || true
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

# Remove a UUID from org.gnome.shell disabled-extensions so it can actually run.
dequeue_from_disabled_extensions() {
    python3 - "$1" <<'PY'
import subprocess, sys
uuid = sys.argv[1]
KEY = ["org.gnome.shell", "disabled-extensions"]
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
PY
}

# Append a UUID to org.gnome.shell enabled-extensions without disturbing what
# is already there.
enqueue_extension() {
    dequeue_from_disabled_extensions "$1" || true
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

# Check if a UUID is currently listed in enabled-extensions
is_extension_enabled() {
    python3 - "$1" <<'PY'
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
sys.exit(0 if uuid in items else 1)
PY
}

# Check if a UUID is currently in disabled-extensions
is_in_disabled_extensions() {
    python3 - "$1" <<'PY'
import subprocess, sys
uuid = sys.argv[1]
KEY = ["org.gnome.shell", "disabled-extensions"]
cur = subprocess.run(["gsettings", "get", *KEY], capture_output=True, text=True).stdout.strip()
if cur.startswith("@as "):
    cur = cur[4:]
try:
    items = [x.strip().strip("'\"") for x in cur.strip("[]").split(",") if x.strip()]
except Exception:
    items = []
sys.exit(0 if uuid in items else 1)
PY
}

# Automatically disable extensions that have been retired from the theme
disable_retired_extensions() {
    local retired=(
        compiz-alike-magic-lamp-effect@hermes83.github.com
        openbar@neuromorph
        just-perfection-desktop@just-perfection
        gnome-ui-tune@itstime.tech
        space-bar@luchrioh
        clipboard-indicator@tudmotu.com
        auto-accent-colour@Wartybix
        ddterm@amezin.github.com
        xwayland-indicator@swsnr.de
        add-to-steam@pupper.space
    )
    local u
    for u in "${retired[@]}"; do
        if [ "${DRY_RUN:-0}" = 1 ]; then
            continue
        fi
        if is_extension_enabled "$u"; then
            run gnome-extensions disable "$u" 2>/dev/null || true
            dequeue_extension "$u" || true
            ok "disabled retired extension: $u"
        fi
        if [ -d "$EXT_DIR/$u" ]; then
            run gnome-extensions uninstall "$u" 2>/dev/null || run rm -rf "$EXT_DIR/$u"
            ok "removed retired extension: $u"
        fi
    done
}

# ------------------------------------------------------------------- icons --
