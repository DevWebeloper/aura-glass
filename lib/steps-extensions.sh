# shellcheck shell=bash
# aura-glass — installing and enabling the shell extensions.
#
# Three of them cannot come from extensions.gnome.org as they are. Blur My Shell
# is built from a pinned commit with a subwindow patch of this project's own;
# Open Bar and Custom OSD are built from their last upstream commit plus a
# patch in patches/, because neither has a GNOME 50 release.
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

# Blur My Shell carries the popup component upstream: menus, quick settings,
# notifications, dialogs and the OSD get blur directly. We build from pinned
# release v76 with the subwindow patch applied on top (see BMS_SUBWIN_PATCH in
# lib/steps.sh).
# gnome-extensions pack and gnome-extensions install both write under $HOME, so
# this needs no root.
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
       && patch_stamp_current bms-subwindow-patch "$REPO_ROOT/patches/$BMS_SUBWIN_PATCH" \
       && ext_supports_shell "$EXT_DIR/$BMS_UUID" "$GNOME_MAJOR"; then
        skip "$BMS_UUID already built from $BMS_REF"
        return 0
    fi

    info "building Blur My Shell from $BMS_REF + patches/$BMS_SUBWIN_PATCH"
    local src="$SRC_CACHE/blur-my-shell"
    if [ -d "$src/.git" ]; then
        run git -C "$src" checkout --quiet -- . 2>/dev/null || true
    fi
    clone_pinned "$BMS_REPO" "$BMS_REF" "$src"

    # The subwindow patch makes the window rules match a window's whole
    # transient-for chain and its GTK application id, not just its own
    # wm_class, and adds ATTACHED and UTILITY to the frame types they accept.
    # Without it a blurred app's own dialogs and tool palettes stay unblurred.
    # The checkout above is reset by the `git checkout -- .` that precedes it,
    # so this always applies to a clean tree.
    if [ "${DRY_RUN:-0}" != 1 ]; then
        git -C "$src" apply --whitespace=nowarn "$REPO_ROOT/patches/$BMS_SUBWIN_PATCH" \
            || die "the Blur My Shell subwindow patch did not apply — upstream may have moved"
    fi

    local podir=(--podir=../po)
    if ! have msgfmt; then
        warn "msgfmt not found (install gettext) — building without translations"
        podir=()
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: apply patches/$BMS_SUBWIN_PATCH, bundle the stylesheets, gnome-extensions pack in $src/src, then install the zip"
        return 0
    fi

    # This mirrors upstream's Makefile 'build' target rather than calling make,
    # because make is not one of this project's dependencies. Doing it here also
    # means a failed build never gets as far as deleting the working extension.
    # The mkdir is not optional: given a -o directory that does not exist,
    # gnome-extensions pack segfaults (139) instead of reporting an error.
    rm -rf "$src/build"
    mkdir -p "$src/build"
    # v76 ships one stylesheet bundled from its component sheets, in this
    # order (its Makefile's STYLESHEETS), because St does not give a sheet's
    # @imports the extension stylesheet's priority. Every source directory but
    # styles/ goes in the zip, read off the tree so a directory upstream adds
    # is not silently left out.
    local sheet sources=()
    for sheet in panel dash popup/base popup/transparent popup/light \
                 popup/dark popup/menu-items overview appfolders panel-light-text; do
        cat "$src/src/styles/$sheet.css" \
            || die "Blur My Shell has no styles/$sheet.css — upstream's layout may have moved"
    done > "$src/build/stylesheet.css"
    local dir
    for dir in "$src"/src/*/; do
        dir="$(basename "$dir")"
        [ "$dir" = styles ] || sources+=("--extra-source=./$dir")
    done
    ( cd "$src/src" && gnome-extensions pack -f \
        --extra-source=../build/stylesheet.css \
        --extra-source=../metadata.json \
        --extra-source=../LICENSE \
        --extra-source=../resources/icons \
        --extra-source=../resources/ui \
        "${sources[@]}" \
        "${podir[@]}" \
        --schema=../schemas/org.gnome.shell.extensions.blur-my-shell.gschema.xml \
        -o ../build ) >/dev/null \
        || die "packing Blur My Shell failed — upstream's layout may have moved"

    local zip="$src/build/$BMS_UUID.shell-extension.zip"
    [ -f "$zip" ] || die "expected $zip after packing, but it is not there"
    ext_supports_shell "$zip" "$GNOME_MAJOR" \
        || die "the pinned Blur My Shell does not support GNOME $GNOME_MAJOR"

    # Upstream's Makefile removes the directory before installing, and it is
    # right to: v73 keeps applications and panel as flat files where v76 keeps
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
    patch_stamp_write bms-subwindow-patch "$REPO_ROOT/patches/$BMS_SUBWIN_PATCH"
    ok "$BMS_UUID (built from $BMS_REF, with the subwindow patch)"
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
        # What the pack was chosen from, so a later release can tell an
        # extension the user turned off from one that did not exist yet.
        ( IFS=,; printf '%s\n' "${EXT_EXTRA_ALL[*]}" ) > "$CONF_DIR/extension-catalog"
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
    patch_wiggly_extension
}

# Wiggly 10 measures the pointer once, at enable, in texture pixels, and eases
# its pivot in from the top-left corner. On a scaled monitor the shrink ended
# larger than the pointer and snapped down; a theme or size change was never
# seen; the growth drifted off the tip. It also only draws a picture someone
# wrote into cursor-path. patches/wiggly-follow-cursor.patch measures in logical
# pixels before every shake, pins the pivot on the hotspot, and adds theme.js,
# which finds the active cursor theme's pointer itself, in the order GNOME
# Shell draws it (St's SVG set, built-in Adwaita included, else the Xcursor
# file), on every cursor-theme change, from any tool.
# Applied to the EGO download, so a Wiggly update that moves the code skips
# the patch with a warning rather than half-applying it.
patch_wiggly_extension() {
    local target="$EXT_DIR/wiggly@mojarch"
    local patch="$REPO_ROOT/patches/wiggly-follow-cursor.patch"
    [ -d "$target" ] || return 0
    # The ceiling keeps git from treating a dotfiles repo above the extension
    # as the tree to patch: with no repository found it applies to the cwd.
    _wiggly_git_apply() {
        ( cd "$target" && GIT_CEILING_DIRECTORIES="$EXT_DIR" git apply "$@" "$patch" ) 2>/dev/null
    }
    if _wiggly_git_apply --reverse --check; then
        return 0
    fi
    # theme.js is this patch's own file, so an install that has it and takes
    # neither direction carries an earlier version of the patch (the first one
    # measured the texture and shrank to twice the pointer on fractional
    # scales). Fetched again from EGO and patched fresh; the old copy is put
    # back if the download fails, so Wiggly is never left missing.
    if [ -f "$target/theme.js" ] && ! _wiggly_git_apply --check \
       && [ "${DRY_RUN:-0}" != 1 ]; then
        mv "$target" "$target.aura-glass-old"
        if install_ext_ego wiggly@mojarch && [ -d "$target" ]; then
            rm -rf "$target.aura-glass-old"
        else
            rm -rf "$target"
            mv "$target.aura-glass-old" "$target"
        fi
    fi
    if ! _wiggly_git_apply --check; then
        warn "Wiggly changed upstream; its magnified cursor will not follow the cursor theme"
        return 0
    fi
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: apply $(basename "$patch") to wiggly@mojarch"
        return 0
    fi
    if _wiggly_git_apply; then
        ok "Wiggly follows the cursor theme"
    else
        warn "could not patch Wiggly; its magnified cursor will not follow the cursor theme"
    fi
}

patch_copyous_extension() {
    local target="$EXT_DIR/copyous@boerdereinar.dev"
    [ -d "$target" ] || return 0

    # Copyous 2.1.2 (and upstream main) connects TextItem's entry listener with
    # no tracking object, so connectObject throws "No object to track signals"
    # and that clipboard entry is never built. Its destroy() already calls
    # entry.disconnectObject(this), so `this` is the object it meant. Checked
    # apart from the GLSLEffect marker below, which an older run already wrote.
    local text="$target/lib/ui/items/textItem.js"
    local untracked="entry.connectObject('notify::content', this.updateTextInfo.bind(this));"
    if [ -f "$text" ] && grep -qF "$untracked" "$text"; then
        run sed -i "s|entry\.connectObject('notify::content', this\.updateTextInfo\.bind(this));|entry.connectObject('notify::content', this.updateTextInfo.bind(this), this);|" "$text"
    fi

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

# Offer to disable and remove extensions an older release installed and the
# theme no longer needs. Asked, not done: the user may have installed one
# themselves or come to rely on it. Asked even under --yes, which answers the
# theme's questions and not whether to take away something the user has, and a
# non-interactive run (the settings app's Apply, the adaptive worker, a pipe)
# keeps them. A "no" is remembered in kept-extensions so it is asked once.
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
    [ "${DRY_RUN:-0}" = 1 ] && return 0
    [ -t 0 ] || return 0
    local kept="$CONF_DIR/kept-extensions" u name meta found=()
    for u in "${retired[@]}"; do
        [ -f "$kept" ] && grep -qxF "$u" "$kept" && continue
        if [ -d "$EXT_DIR/$u" ] || is_extension_enabled "$u"; then found+=("$u"); fi
    done
    [ "${#found[@]}" -gt 0 ] || return 0
    info "These extensions are no longer needed by the Aura Glass theme."
    for u in "${found[@]}"; do
        name="$u"
        for meta in "$EXT_DIR/$u/metadata.json" "/usr/share/gnome-shell/extensions/$u/metadata.json"; do
            [ -f "$meta" ] || continue
            name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name") or sys.argv[2])' "$meta" "$u" 2>/dev/null || echo "$u")"
            break
        done
        if ! confirm_always "Remove $name ($u)?"; then
            if remembering; then
                mkdir -p "$CONF_DIR"
                printf '%s\n' "$u" >> "$kept"
            fi
            skip "keeping $u"
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
