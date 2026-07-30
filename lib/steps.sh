# shellcheck shell=bash
# tahoe-glass — the individual install steps.

# Upstreams are pinned. Both move regularly, and a theme that changes under the
# CSS tweaks is exactly how you get a half-applied look with no error message.
THEME_REPO="https://github.com/kayozxo/GNOME-macOS-Tahoe.git"
THEME_REF="6dfcd9d941e5"

OPENBAR_REPO="https://github.com/neuromorph/openbar.git"
OPENBAR_REF="01fb24217e0c"       # last upstream commit; patched for GNOME 50

COLLOID_REPO="https://github.com/vinceliuice/Colloid-icon-theme.git"
COLLOID_REF="c9e702beb96f"

MACTAHOE_REPO="https://github.com/vinceliuice/MacTahoe-icon-theme.git"
MACTAHOE_REF="b85923bb87f5"

EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
CONF_DIR="$HOME/.config/tahoe-glass"
BACKUP_DIR="$CONF_DIR/backups"
SRC_CACHE="$HOME/.cache/tahoe-glass/src"

# Everything the look actually needs. openbar is absent because it installs
# differently on GNOME 50 — see install_openbar.
EXT_CORE=(
    user-theme@gnome-shell-extensions.gcampax.github.com
    blur-my-shell@aunetx
)
# The rest of the reference desktop. None of it is required.
EXT_EXTRA=(
    just-perfection-desktop@just-perfection
    gnome-ui-tune@itstime.tech
    space-bar@luchrioh
    dash-to-dock@micxgx.gmail.com
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
        *)       die "this is a GNOME desktop theme, but the session is '$desktop'.
       On Bazzite that usually means you are on the KDE image; the GNOME
       image is bazzite-gnome." ;;
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
        atomic)  ok "$DISTRO_PRETTY (atomic — everything installs under \$HOME)" ;;
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
    # override into ~/.config/gtk-4.0. Both are per-user, so this works
    # unchanged on an ostree system. </dev/null keeps its gum prompts quiet.
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

    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
    curl -sLo "$tmp/e.zip" "https://extensions.gnome.org$url" \
        || { warn "$uuid: download failed — skipped"; return 1; }

    if ! ext_supports_shell "$tmp/e.zip" "$GNOME_MAJOR"; then
        ver="$(unzip -p "$tmp/e.zip" metadata.json | python3 -c 'import sys,json;print(json.load(sys.stdin).get("shell-version"))')"
        warn "$uuid: published build supports $ver, not GNOME $GNOME_MAJOR — skipped"
        return 1
    fi

    gnome-extensions install --force "$tmp/e.zip" >/dev/null \
        || { warn "$uuid: install failed — skipped"; return 1; }
    ok "$uuid"
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

install_extensions() {
    step "Installing shell extensions"
    local u
    for u in "${EXT_CORE[@]}"; do install_ext_ego "$u" || true; done
    install_openbar

    if [ "${WANT_EXTRAS:-0}" = 1 ]; then
        step "Installing optional extensions"
        for u in "${EXT_EXTRA[@]}"; do install_ext_ego "$u" || true; done
    fi
}

enable_extensions() {
    step "Enabling extensions"
    local want=("${EXT_CORE[@]}" openbar@neuromorph) u
    [ "${WANT_EXTRAS:-0}" = 1 ] && want+=("${EXT_EXTRA[@]}")

    for u in "${want[@]}"; do
        if [ ! -d "$EXT_DIR/$u" ] && [ ! -d "/usr/share/gnome-shell/extensions/$u" ]; then
            skip "$u not installed — not enabling"
            continue
        fi
        run gnome-extensions enable "$u" 2>/dev/null \
            && ok "enabled $u" \
            || warn "could not enable $u yet — it will be picked up after logout"
    done
}

# ------------------------------------------------------------------- icons --

install_icons() {
    step "Installing the Colloid icon theme ($ACCENT)"

    local name; name="$(accent_to_colloid_name "$ACCENT")"
    if [ "${FORCE:-0}" != 1 ] \
       && { [ -d "$HOME/.local/share/icons/$name" ] || [ -d "/usr/share/icons/$name" ]; }; then
        skip "$name already installed"
        return 0
    fi

    local src="$SRC_CACHE/Colloid-icon-theme"
    clone_pinned "$COLLOID_REPO" "$COLLOID_REF" "$src"

    # No -d: unprivileged runs default to ~/.local/share/icons, which is the
    # only writable location on an atomic system anyway.
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: $src/install.sh -t $(accent_to_colloid_arg "$ACCENT")"
    else
        ( cd "$src" && ./install.sh -t "$(accent_to_colloid_arg "$ACCENT")" ) >/dev/null \
            || die "the Colloid installer failed"
    fi
    ok "$name"
}

install_cursors() {
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
}

apply_gsettings() {
    step "Setting themes and accent"

    local icons; icons="$(accent_to_colloid_name "$ACCENT")"
    [ -d "$HOME/.local/share/icons/$icons" ] || [ -d "/usr/share/icons/$icons" ] \
        || { warn "icon theme $icons is not installed — falling back to Adwaita"; icons="Adwaita"; }

    run gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    run gsettings set org.gnome.desktop.interface gtk-theme    'Tahoe-Dark'
    run gsettings set org.gnome.desktop.interface accent-color "$ACCENT"
    run gsettings set org.gnome.desktop.interface icon-theme   "$icons"

    if [ -d "$HOME/.local/share/icons/MacTahoe-dark" ]; then
        run gsettings set org.gnome.desktop.interface cursor-theme 'MacTahoe-dark'
    fi

    # Single close button on the right, appmenu on the left — the reference
    # desktop's layout. Change it in Tweaks if you prefer three buttons.
    if [ "${WANT_WM_BUTTONS:-1}" = 1 ]; then
        run gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:close'
    fi

    ok "gtk-theme=Tahoe-Dark  icons=$icons  accent=$ACCENT"
}

# ------------------------------------------------------------- integration --

flatpak_override() {
    have flatpak || { skip "flatpak not installed"; return 0; }
    step "Letting Flatpak apps read the GTK config"

    # Without this a Flatpak app is sandboxed away from ~/.config/gtk-4.0 and
    # silently keeps stock Adwaita — which looks exactly like the tweaks
    # failing to apply. On an atomic system most apps are Flatpaks, so this is
    # the difference between a themed desktop and a half-themed one.
    run flatpak override --user \
        --filesystem=xdg-config/gtk-4.0:ro \
        --filesystem=xdg-config/gtk-3.0:ro \
        --filesystem=xdg-data/themes:ro \
        --filesystem=xdg-data/icons:ro
    ok "read-only access granted to themes, icons and GTK config"
}

install_panel_blur_unit() {
    step "Blur My Shell panel fix at login"

    # Blur My Shell builds one background actor per monitor and clips it to the
    # panel geometry, which is not settled at login — the left part of the bar
    # ends up showing a mismatched strip. Toggling the blur once the session
    # has settled rebuilds the actor against correct geometry.
    if ! confirm "Install the login-time panel blur rebuild (recommended on multi-monitor)?" 1; then
        skip "not installed"
        return 0
    fi
    run install -Dm644 "$REPO_ROOT/systemd/tahoe-glass-panel-blur.service" \
        "$HOME/.config/systemd/user/tahoe-glass-panel-blur.service"
    run systemctl --user daemon-reload
    run systemctl --user enable tahoe-glass-panel-blur.service >/dev/null 2>&1 || true
    ok "tahoe-glass-panel-blur.service enabled"

    # Enabling only queues the unit for the *next* graphical-session.target, so
    # a session that is already up keeps the mismatched strip until logout —
    # which reads as "the blur is broken" immediately after running this. Kick
    # it once now if a session is live. --no-block because the unit deliberately
    # sleeps 12s waiting for geometry to settle, and there is no reason to hold
    # the installer for that.
    if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        run systemctl --user start --no-block tahoe-glass-panel-blur.service 2>/dev/null || true
        info "rebuilding panel blur in the current session (~15s)"
    fi
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
