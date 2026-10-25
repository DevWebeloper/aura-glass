# shellcheck shell=bash
# aura-glass — GDM login screen theme installation, wallpaper sync, and restoration.
#
# Unlike user themes which live under $HOME, GDM runs as a separate system user
# and loads its theme from /usr/share/gnome-shell/gnome-shell-theme.gresource.
# Modifying it requires root/sudo privileges.
#
# Sourced by install.sh and uninstall.sh.

WHITESUR_REPO="https://github.com/vinceliuice/WhiteSur-gtk-theme.git"
WHITESUR_REF="1912dee2e48d"

# The files tweaks.sh -g may compile the login theme into, in WhiteSur's own
# order (install_only_gdm_theme in libs/lib-install.sh at WHITESUR_REF): it takes
# the first one the distribution ships. All of them belong to a distribution
# package, so a gnome-shell (or Yaru/Pop/Zorin theme) update puts the stock file
# back and the login screen silently loses the theme and its wallpaper.
GDM_GRESOURCE_CANDIDATES=(
    /usr/share/gnome-shell/theme/Pop/gnome-shell-theme.gresource
    /usr/share/gnome-shell/theme/Yaru/gnome-shell-theme.gresource
    /usr/share/gnome-shell/theme/ZorinBlue-Dark/gnome-shell-theme.gresource
    /usr/share/gnome-shell/theme/ZorinBlue-Light/gnome-shell-theme.gresource
    /usr/share/gnome-shell/gnome-shell-theme.gresource
)

get_desktop_wallpaper() {
    local uri
    uri="$(gsettings get org.gnome.desktop.background picture-uri-dark 2>/dev/null || true)"
    uri="${uri//\'/}"
    if [ -z "$uri" ] || [ "$uri" = "nothing" ] || [ "$uri" = "''" ]; then
        uri="$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || true)"
        uri="${uri//\'/}"
    fi
    if [[ "$uri" =~ ^file://(.*) ]]; then
        python3 -c "import urllib.parse, sys; print(urllib.parse.unquote(sys.argv[1][7:]))" "$uri" 2>/dev/null || echo "${uri#file://}"
    else
        echo "$uri"
    fi
}

generate_gdm_wallpaper() {
    local src="$1" dst="$2"
    [ -f "$src" ] || return 1

    python3 - "$src" "$dst" <<'PY' || return 1
import os, sys, urllib.parse, subprocess
from PIL import Image, ImageFilter, ImageEnhance, ImageOps

src = sys.argv[1]
dst = sys.argv[2]

if not os.path.exists(src):
    sys.exit(1)


def render():
    if src.lower().endswith(('.svg', '.svgz')):
        try:
            subprocess.run([
                "magick", "-density", "150", src,
                "-resize", "2560x1440^", "-gravity", "center", "-extent", "2560x1440",
                "-blur", "0x30", "-fill", "black", "-colorize", "40%", dst
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except Exception:
            pass

    try:
        im = Image.open(src).convert('RGB')
        im.thumbnail((2560, 1440), Image.Resampling.LANCZOS)
        im = im.filter(ImageFilter.GaussianBlur(radius=30))
        enhancer = ImageEnhance.Brightness(im)
        im = enhancer.enhance(0.55)
        im.save(dst, format="PNG")
        return True
    except Exception:
        try:
            subprocess.run([
                "magick", src,
                "-resize", "2560x1440^", "-gravity", "center", "-extent", "2560x1440",
                "-blur", "0x30", "-fill", "black", "-colorize", "40%", dst
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except Exception:
            return False


def monitor_rects():
    """Logical rects of this session's monitors: the layout sync_monitors copies to GDM."""
    try:
        import gi
        gi.require_version('Gio', '2.0')
        from gi.repository import Gio
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        state = bus.call_sync(
            'org.gnome.Mutter.DisplayConfig', '/org/gnome/Mutter/DisplayConfig',
            'org.gnome.Mutter.DisplayConfig', 'GetCurrentState',
            None, None, Gio.DBusCallFlags.NONE, 2000, None).unpack()
    except Exception:
        return []
    serial, monitors, logical, props = state
    modes = {}
    for spec, mode_list, _ in monitors:
        for mode in mode_list:
            if mode[6].get('is-current'):
                modes[spec[0]] = (mode[1], mode[2])
    physical = props.get('layout-mode') == 2
    rects = []
    for x, y, scale, transform, _, specs, _ in logical:
        if not specs or specs[0][0] not in modes:
            continue
        w, h = modes[specs[0][0]]
        if transform % 2:
            w, h = h, w
        if not physical:
            w, h = round(w / scale), round(h / scale)
        rects.append((x, y, w, h))
    return rects


# The greeter has no per-monitor backgrounds (layout.js returns early from
# _updateBackgrounds when sessionMode.isGreeter), so this image is only ever
# drawn as the `#lockDialogGroup` CSS background, and that actor spans the whole
# stage. With one image, background-size: cover stretched it across every
# monitor at once. Instead lay it out like the stage: one zoomed copy per
# monitor rect, the canvas the size of the stage's bounding box, so cover maps
# it back 1:1. Gaps between unequal monitors are never on screen; they take the
# theme's #lockDialogGroup background-color.
def span_monitors():
    rects = monitor_rects()
    if len(rects) < 2:
        return
    x0 = min(r[0] for r in rects)
    y0 = min(r[1] for r in rects)
    width = max(r[0] + r[2] for r in rects) - x0
    height = max(r[1] + r[3] for r in rects) - y0
    # The image is blurred, so 3840 px across keeps the file small with no
    # visible loss on a wide two-monitor stage.
    k = min(1.0, 3840 / width)
    im = Image.open(dst).convert('RGB')
    canvas = Image.new('RGB', (max(1, round(width * k)), max(1, round(height * k))), (0x22, 0x22, 0x26))
    for x, y, w, h in rects:
        tile = ImageOps.fit(im, (max(1, round(w * k)), max(1, round(h * k))), Image.Resampling.LANCZOS)
        canvas.paste(tile, (round((x - x0) * k), round((y - y0) * k)))
    canvas.save(dst, format="PNG")


if not render():
    sys.exit(1)
try:
    span_monitors()
except Exception:
    pass
sys.exit(0)
PY
}

sync_gdm_monitors() {
    step "Syncing primary monitor to GDM login screen (requires sudo)"

    local user_monitors="$HOME/.config/monitors.xml"
    if [ ! -f "$user_monitors" ]; then
        warn "no ~/.config/monitors.xml found — monitor layout not configured in GNOME Settings"
        return 0
    fi

    local synced=0

    # 1. Global XDG config directory — standard for Mutter / GDM 40-50+ with systemd dynamic users
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: sudo mkdir -p /etc/xdg && sudo cp -f $user_monitors /etc/xdg/monitors.xml"
        synced=1
    else
        sudo mkdir -p /etc/xdg
        sudo cp -f "$user_monitors" /etc/xdg/monitors.xml
        sudo chmod 666 /etc/xdg/monitors.xml || sudo chmod 644 /etc/xdg/monitors.xml
        synced=1
    fi

    # 2. GDM user home & seat0 directories for legacy/standard setups across distributions
    for gdm_dir in /var/lib/gdm /var/lib/gdm3; do
        if [ -d "$gdm_dir" ] || [ "$gdm_dir" = "/var/lib/gdm" ]; then
            if [ "${DRY_RUN:-0}" = 1 ]; then
                info "dry-run: sudo mkdir -p $gdm_dir/.config && sudo cp -f $user_monitors $gdm_dir/.config/monitors.xml"
                synced=1
            else
                sudo mkdir -p "$gdm_dir/.config"
                sudo cp -f "$user_monitors" "$gdm_dir/.config/monitors.xml"
                sudo chmod 755 "$gdm_dir/.config"
                sudo chmod 666 "$gdm_dir/.config/monitors.xml" || sudo chmod 644 "$gdm_dir/.config/monitors.xml"
                synced=1
            fi
        fi
    done

    drop_gdm_seat_monitors

    if [ "$synced" = 1 ]; then
        if [ "${DRY_RUN:-0}" != 1 ]; then
            mkdir -p "$CONF_DIR"
            touch "$CONF_DIR/gdm-monitors-synced"
        fi
        ok "primary monitor synced to GDM login screen (good for multi-monitor setups)"
    fi
}

# GDM with dynamic greeter users (the .migrated-dyn-users marker in
# /var/lib/gdm; GDM 51.1 on the dev machine) runs the login screen with its
# config home in $gdm_dir/seat0/config, a 0700 directory owned by that user. Earlier installs
# copied monitors.xml in there (and into seat0/.config). Mutter reads
# /etc/xdg/monitors.xml first and the config home's file over it, key by key, so
# that copy pinned the login screen to the layout and scale of install day:
# aura-glass-gdm-sync runs as the desktop user and cannot reach it, only
# /etc/xdg. After a scale change the greeter kept the old scale under a
# wallpaper laid out for the new one. With the copies gone, the greeter falls
# back to /etc/xdg/monitors.xml, which the sync service keeps current.
drop_gdm_seat_monitors() {
    local gdm_dir target
    for gdm_dir in /var/lib/gdm /var/lib/gdm3; do
        [ -d "$gdm_dir/seat0" ] || continue
        for target in "$gdm_dir/seat0/config/monitors.xml" "$gdm_dir/seat0/.config/monitors.xml"; do
            if [ "${DRY_RUN:-0}" = 1 ]; then
                info "dry-run: sudo rm -f $target"
            else
                sudo rm -f "$target" 2>/dev/null || true
            fi
        done
    done
}

unsync_gdm_monitors() {
    step "Removing synced GDM monitor configuration (requires sudo)"

    local targets=(
        "/etc/xdg/monitors.xml"
        "/var/lib/gdm/.config/monitors.xml"
        "/var/lib/gdm3/.config/monitors.xml"
        "/var/lib/gdm/seat0/config/monitors.xml"
        "/var/lib/gdm/seat0/.config/monitors.xml"
        "/var/lib/gdm3/seat0/config/monitors.xml"
        "/var/lib/gdm3/seat0/.config/monitors.xml"
    )
    for target in "${targets[@]}"; do
        if [ -f "$target" ]; then
            if [ "${DRY_RUN:-0}" = 1 ]; then
                info "dry-run: sudo rm -f $target"
            else
                sudo rm -f "$target" 2>/dev/null || true
            fi
        fi
    done
    rm -f "$CONF_DIR/gdm-monitors-synced"
    ok "GDM monitor layout reverted to system default"
}

install_gdm_sync_unit() {
    if [ -f "$HOME/.config/systemd/user/tahoe-glass-gdm-sync.service" ]; then
        run systemctl --user disable --now tahoe-glass-gdm-sync.service >/dev/null 2>&1 || true
        run rm -f "$HOME/.config/systemd/user/tahoe-glass-gdm-sync.service"
    fi

    run install -Dm755 "$REPO_ROOT/bin/aura-glass-gdm-sync" \
        "$HOME/.local/bin/aura-glass-gdm-sync"
    run ln -sf "$HOME/.local/bin/aura-glass-gdm-sync" "$HOME/.local/bin/tahoe-glass-gdm-sync" 2>/dev/null || true
    run install -Dm644 "$REPO_ROOT/systemd/aura-glass-gdm-sync.service" \
        "$HOME/.config/systemd/user/aura-glass-gdm-sync.service"
    run systemctl --user daemon-reload || true
    run systemctl --user enable aura-glass-gdm-sync.service >/dev/null 2>&1 || true

    if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        run systemctl --user restart aura-glass-gdm-sync.service 2>/dev/null || true
    fi
    ok "GDM dynamic wallpaper sync daemon enabled"
}

# Remember which gresource tweaks.sh wrote and its checksum, in sha256sum's own
# format, so bin/aura-glass-gdm-sync can tell at login that a package update
# replaced it (sha256sum -c) and ask for ./install.sh --gdm. The file is found by
# the wallpaper URL patched into its CSS above rather than by redoing WhiteSur's
# choice: the gresource xml compresses nothing, so the CSS sits in it as text.
record_gdm_gresource() {
    remembering || return 0
    local f
    for f in "${GDM_GRESOURCE_CANDIDATES[@]}"; do
        if [ -r "$f" ] && grep -qaF "file:///usr/share/backgrounds/aura-gdm.png" "$f"; then
            mkdir -p "$CONF_DIR"
            sha256sum "$f" > "$CONF_DIR/gdm-gresource"
            return 0
        fi
    done
    rm -f "$CONF_DIR/gdm-gresource"
    warn "could not find the installed GDM theme; a gnome-shell update that reverts it will go unnoticed"
}

uninstall_gdm_sync_unit() {
    for u in aura-glass-gdm-sync.service tahoe-glass-gdm-sync.service; do
        if [ -f "$HOME/.config/systemd/user/$u" ]; then
            run systemctl --user disable --now "$u" >/dev/null 2>&1 || true
            run rm -f "$HOME/.config/systemd/user/$u"
        fi
    done
    run systemctl --user daemon-reload || true
    run rm -f "$HOME/.local/bin/aura-glass-gdm-sync" "$HOME/.local/bin/tahoe-glass-gdm-sync"
}

install_gdm() {
    step "Installing the GDM Login Screen theme (requires sudo)"

    if ! have gdm && ! have gdm3 && [ ! -e /usr/sbin/gdm3 ]; then
        skip "GDM is not installed on this system"
        return 0
    fi

    if ! have glib-compile-resources; then
        warn "glib-compile-resources is required to build the GDM theme"
        return 1
    fi

    # 1. Sync primary monitor layout to GDM if requested
    if [ "${WANT_GDM_MONITORS:-0}" = 1 ] && [ ! -f "$CONF_DIR/gdm-monitors-synced" ]; then
        sync_gdm_monitors
    fi

    # 2. Prepare initial blurred desktop wallpaper in /usr/share/backgrounds/aura-gdm.png
    local target_wall="/usr/share/backgrounds/aura-gdm.png"
    local cur_wall; cur_wall="$(get_desktop_wallpaper)"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: generate $target_wall from $cur_wall and make writable for live wallpaper sync"
    else
        sudo mkdir -p /usr/share/backgrounds
        local tmp_init="/tmp/aura-gdm-init.png"
        if [ -n "$cur_wall" ] && generate_gdm_wallpaper "$cur_wall" "$tmp_init"; then
            sudo cp -f "$tmp_init" "$target_wall"
            rm -f "$tmp_init"
        else
            sudo touch "$target_wall"
        fi
        sudo chmod 666 "$target_wall"
        ok "GDM background configured from desktop wallpaper ($target_wall)"
    fi

    # 3. Compile and install GDM theme patched to link directly to file:///usr/share/backgrounds/aura-gdm.png
    info "Preparing WhiteSur GDM resources..."
    local src="$SRC_CACHE/WhiteSur-gtk-theme"
    clone_pinned "$WHITESUR_REPO" "$WHITESUR_REF" "$src"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: compile GDM theme with background linking to $target_wall"
    else
        # Patch theme css so GDM directly loads file:///usr/share/backgrounds/aura-gdm.png
        sed -i 's|resource:///org/gnome/shell/theme/background.png|file:///usr/share/backgrounds/aura-gdm.png|g' \
            "$src"/other/gdm/theme/gnome-shell-*.css 2>/dev/null || true
        sed -i 's|assets/background.png|file:///usr/share/backgrounds/aura-gdm.png|g' \
            "$src"/src/main/gnome-shell/gnome-shell-*.css 2>/dev/null || true

        # Patch login auth prompt & dialog styles so GDM correctly aligns password entry and submit arrow
        if [ -f "$REPO_ROOT/css/shell-50-dialogs.css" ]; then
            for css_file in "$src"/other/gdm/theme/gnome-shell-*.css; do
                if [ -f "$css_file" ] && ! grep -q "login-dialog-button.next-button" "$css_file"; then
                    cat "$REPO_ROOT/css/shell-50-dialogs.css" >> "$css_file"
                fi
            done
            for scss_file in "$src"/src/main/gnome-shell/_shell-base.scss; do
                if [ -f "$scss_file" ] && ! grep -q "login-dialog-button.next-button" "$scss_file"; then
                    cat "$REPO_ROOT/css/shell-50-dialogs.css" >> "$scss_file"
                fi
            done
        fi

        # Neutralize WhiteSur internal network & system package checks that can freeze/hang
        sed -i 's/prepare_deps/true/g' "$src"/libs/*.sh 2>/dev/null || true
        sed -i 's/get_utc_epoch_time/true/g' "$src"/libs/*.sh 2>/dev/null || true

        info "Compiling and applying GDM theme..."
        sudo -v || { warn "sudo authentication required for GDM installation"; return 1; }

        local gdm_log="/tmp/aura-gdm-install.log"
        if sudo bash "$src/tweaks.sh" -g -b "$target_wall" -nb --silent-mode >"$gdm_log" 2>&1; then
            mkdir -p "$CONF_DIR"
            printf '%s\n' "dynamic" > "$CONF_DIR/gdm-installed"
            record_gdm_gresource
            ok "GDM login screen theme installed (dynamic wallpaper sync)"
        else
            warn "GDM theme installation failed (log: $gdm_log)"
            if [ -f "$gdm_log" ]; then
                grep -E "ERROR|error|failed|fatal" "$gdm_log" | head -n 5 | while read -r err_line; do
                    warn "  $err_line"
                done
            fi
            return 1
        fi
    fi

    # 4. Install and start user daemon for live wallpaper updates
    install_gdm_sync_unit
}

uninstall_gdm() {
    step "Restoring default GDM login screen"

    local src="$SRC_CACHE/WhiteSur-gtk-theme"
    local restored=0

    if [ -f "$src/tweaks.sh" ]; then
        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: sudo bash $src/tweaks.sh -r -g --silent-mode"
            restored=1
        else
            sudo -v 2>/dev/null || true
            sed -i 's/prepare_deps/true/g' "$src"/libs/*.sh 2>/dev/null || true
            sed -i 's/get_utc_epoch_time/true/g' "$src"/libs/*.sh 2>/dev/null || true
            if sudo bash "$src/tweaks.sh" -r -g --silent-mode >/dev/null 2>&1; then
                restored=1
            fi
        fi
    fi

    # Fallback to direct backup file restoration if tweaks.sh didn't run
    if [ "$restored" = 0 ]; then
        local gr_bak="/usr/share/gnome-shell/gnome-shell-theme.gresource.bak"
        local gr_file="/usr/share/gnome-shell/gnome-shell-theme.gresource"
        if [ -f "$gr_bak" ]; then
            if [ "${DRY_RUN:-0}" = 1 ]; then
                info "dry-run: sudo cp -f $gr_bak $gr_file"
            else
                sudo cp -f "$gr_bak" "$gr_file" || true
            fi
            restored=1
        fi
    fi

    # Remove dynamic background file
    for bg_file in "/usr/share/backgrounds/aura-gdm.png" "/usr/share/backgrounds/tahoe-gdm.png"; do
        if [ -f "$bg_file" ]; then
            if [ "${DRY_RUN:-0}" = 1 ]; then
                info "dry-run: sudo rm -f $bg_file"
            else
                sudo rm -f "$bg_file" 2>/dev/null || true
            fi
        fi
    done

    # Disable sync unit
    uninstall_gdm_sync_unit

    rm -f "$CONF_DIR/gdm-installed" "$CONF_DIR/gdm-gresource"
    if [ "$restored" = 1 ]; then
        ok "GDM login screen restored to stock theme"
    else
        skip "GDM theme was not installed or backup not found"
    fi
}
