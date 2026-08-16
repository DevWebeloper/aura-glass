# shellcheck shell=bash
# tahoe-glass — the dconf preset, and the gsettings that go with it.
#
# dconf/core.ini holds the preset so it stays readable in one file. What cannot
# live there is anything whose right value depends on the machine or on a flag,
# because dconf load rewrites the whole section on every run — so a flagless
# re-install would quietly undo a deliberate choice. Those keys are written
# afterwards by the apply_* functions here, several of which remember the answer
# in $CONF_DIR for exactly that reason.
#
# Sourced by install.sh.

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

    # Open Bar regenerates its stylesheet when this key changes, so toggling it
    # is what makes the preset take effect without a restart.
    run dconf write /org/gnome/shell/extensions/openbar/trigger-reload false
    run dconf write /org/gnome/shell/extensions/openbar/trigger-reload true

    apply_grain
    apply_popup_blur
    apply_app_blur
    apply_app_opacity
    sync_osd_profile
}

# [applications] opacity controls the compositor-level window actor opacity for
# windows on top of the blur effect. For GTK4 apps, the stylesheet handles inner
# translucency; for Electron/IDE/browser apps, this actor opacity allows the blur
# to show through the window content.
apply_app_opacity() {
    local base=/org/gnome/shell/extensions/blur-my-shell
    local opacity="${APP_OPACITY:-255}" memo="$CONF_DIR/app-opacity"

    if [ "${WANT_BLUR:-1}" != 1 ] || [ "${WANT_WINDOW_BLUR:-1}" != 1 ]; then
        run dconf write "$base/applications/opacity" 255
        return 0
    fi

    if [ -z "${APP_OPACITY_EXPLICIT:-}" ] && [ -r "$memo" ]; then
        opacity="$(cat "$memo" 2>/dev/null || true)"
        opacity="${opacity:-255}"
    fi

    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$opacity" > "$memo"
    fi

    run dconf write "$base/applications/opacity" "$opacity"
    if [ "$opacity" != 255 ]; then
        local pct
        pct="$(python3 -c "print(round($opacity / 255.0 * 100))" 2>/dev/null || echo "$opacity")"
        ok "window actor opacity set to $opacity (${pct}% opacity, translucent blur for apps)"
    else
        ok "window actor opacity set to 255 (opaque actor)"
    fi
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
# The window blur is its own opt-in, not a consequence of anything else.
#
# It is the most expensive thing this preset can switch on — a blur behind every
# window, rebuilt as the window moves, which measured the overview at p90 99%
# GPU against 32% without it on an RX 7600 — and it only becomes visible at all
# once --app-transparency has made the surfaces translucent. Paired with
# --app-transparency it is a real effect for a real cost; on its own it is a
# cost for almost nothing, since the window sits at 94% opacity.
#
# The cheaper way to the same readable, see-through window is the tint: darken
# the ground under the alpha instead of blurring what is behind it. That costs
# no GPU at all. See TOKEN_APP_TINT in tokens/tokens.sh.
#
# Deliberately not remembered, like the popup-blur memo it sits beside: a flag
# that persists past the run that set it is how --no-blur left menus unblurred
# after a return to glass.
apply_app_blur() {
    local base=/org/gnome/shell/extensions/blur-my-shell
    local want="${WANT_WINDOW_BLUR:-1}" memo="$CONF_DIR/window-blur"

    if [ "${WANT_BLUR:-1}" != 1 ]; then
        run dconf write "$base/applications/blur" false
        skip "window blur off with the rest of it (--no-blur)"
        return 0
    fi

    if [ -z "${WINDOW_BLUR_EXPLICIT:-}" ] && [ -r "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
        want="${want:-1}"
    fi

    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi

    if [ "$want" != 1 ]; then
        run dconf write "$base/applications/blur" false
        skip "window blur off — pass --window-blur if you want it"
        return 0
    fi

    run dconf write "$base/applications/blur" true
    ok "window blur on behind app windows"
    if [ -z "${APP_TRANSPARENCY:-}" ] || [ "${APP_TRANSPARENCY:-0}" = 0 ]; then
        warn "without --app-transparency the windows stay 94% opaque, so very"
        warn "little of that blur will be visible for what it costs"
    fi
}

apply_popup_blur() {
    local base=/org/gnome/shell/extensions/blur-my-shell
    local want="${WANT_POPUP_BLUR:-1}" memo="$CONF_DIR/popup-blur"

    # --no-blur turns this off as a consequence of turning everything off, not
    # because the user asked for flat popups. Remembering it would outlive the
    # mode: installing --no-blur and later going back to glass came up with
    # blurred windows and unblurred menus, because the memo said 0 and nothing
    # on the second run contradicted it. So solid mode neither reads nor writes
    # the memo — it leaves whatever the last real choice was intact, ready for
    # the next glass install.
    if [ "${WANT_BLUR:-1}" != 1 ]; then
        run dconf write "$base/popup/blur" false
        skip "popup blur off with the rest of it (--no-blur)"
        return 0
    fi

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

    # Remembered so the next flagless run comes back to this accent rather than
    # to the default. install.sh reads it back before validating. Written here
    # rather than at parse time so that a run which died before this point
    # leaves the previous answer standing.
    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$ACCENT" > "$CONF_DIR/accent"
    fi

    local cursor='Adwaita'
    if [ "${CURSORS:-adwaita}" = mactahoe ] \
       && { [ -d "$HOME/.local/share/icons/MacTahoe-dark" ] \
            || [ -d "/usr/share/icons/MacTahoe-dark" ]; }; then
        cursor='MacTahoe-dark'
    fi
    run gsettings set org.gnome.desktop.interface cursor-theme "$cursor"

    ok "gtk-theme=Tahoe-Dark  icons=$icons  cursor=$cursor  accent=$ACCENT"
}
