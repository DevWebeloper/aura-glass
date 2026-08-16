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
from PIL import Image, ImageFilter, ImageEnhance

src = sys.argv[1]
dst = sys.argv[2]

if not os.path.exists(src):
    sys.exit(1)

if src.lower().endswith(('.svg', '.svgz')):
    try:
        subprocess.run([
            "magick", "-density", "150", src,
            "-resize", "2560x1440^", "-gravity", "center", "-extent", "2560x1440",
            "-blur", "0x30", "-fill", "black", "-colorize", "40%", dst
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        sys.exit(0)
    except Exception:
        pass

try:
    im = Image.open(src).convert('RGB')
    im.thumbnail((2560, 1440), Image.Resampling.LANCZOS)
    im = im.filter(ImageFilter.GaussianBlur(radius=30))
    enhancer = ImageEnhance.Brightness(im)
    im = enhancer.enhance(0.55)
    im.save(dst, format="PNG")
    sys.exit(0)
except Exception:
    try:
        subprocess.run([
            "magick", src,
            "-resize", "2560x1440^", "-gravity", "center", "-extent", "2560x1440",
            "-blur", "0x30", "-fill", "black", "-colorize", "40%", dst
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        sys.exit(0)
    except Exception:
        sys.exit(1)
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

                # If seat0 exists (GNOME 46+ dynamic seat sessions), also populate seat config dirs
                if [ -d "$gdm_dir/seat0" ]; then
                    sudo mkdir -p "$gdm_dir/seat0/config" "$gdm_dir/seat0/.config" 2>/dev/null || true
                    sudo cp -f "$user_monitors" "$gdm_dir/seat0/config/monitors.xml" 2>/dev/null || true
                    sudo cp -f "$user_monitors" "$gdm_dir/seat0/.config/monitors.xml" 2>/dev/null || true
                    sudo chmod 666 "$gdm_dir/seat0/config/monitors.xml" "$gdm_dir/seat0/.config/monitors.xml" 2>/dev/null || true
                fi
                synced=1
            fi
        fi
    done

    if [ "$synced" = 1 ]; then
        if [ "${DRY_RUN:-0}" != 1 ]; then
            mkdir -p "$CONF_DIR"
            touch "$CONF_DIR/gdm-monitors-synced"
        fi
        ok "primary monitor synced to GDM login screen (good for multi-monitor setups)"
    fi
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
    ln -sf "$HOME/.local/bin/aura-glass-gdm-sync" "$HOME/.local/bin/tahoe-glass-gdm-sync" 2>/dev/null || true
    run install -Dm644 "$REPO_ROOT/systemd/aura-glass-gdm-sync.service" \
        "$HOME/.config/systemd/user/aura-glass-gdm-sync.service"
    run systemctl --user daemon-reload
    run systemctl --user enable aura-glass-gdm-sync.service >/dev/null 2>&1 || true

    if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        run systemctl --user restart aura-glass-gdm-sync.service 2>/dev/null || true
    fi
    ok "GDM dynamic wallpaper sync daemon enabled"
}

uninstall_gdm_sync_unit() {
    for u in aura-glass-gdm-sync.service tahoe-glass-gdm-sync.service; do
        if [ -f "$HOME/.config/systemd/user/$u" ]; then
            run systemctl --user disable --now "$u" >/dev/null 2>&1 || true
            run rm -f "$HOME/.config/systemd/user/$u"
        fi
    done
    run systemctl --user daemon-reload
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

        # Neutralize WhiteSur internal network & system package checks that can freeze/hang
        sed -i 's/prepare_deps/true/g' "$src"/libs/*.sh 2>/dev/null || true
        sed -i 's/get_utc_epoch_time/true/g' "$src"/libs/*.sh 2>/dev/null || true

        info "Compiling and applying GDM theme..."
        sudo -v || { warn "sudo authentication required for GDM installation"; return 1; }

        local gdm_log="/tmp/aura-gdm-install.log"
        if sudo bash "$src/tweaks.sh" -g -b "$target_wall" -nb --silent-mode >"$gdm_log" 2>&1; then
            mkdir -p "$CONF_DIR"
            printf '%s\n' "dynamic" > "$CONF_DIR/gdm-installed"
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

    rm -f "$CONF_DIR/gdm-installed"
    if [ "$restored" = 1 ]; then
        ok "GDM login screen restored to stock theme"
    else
        skip "GDM theme was not installed or backup not found"
    fi
}
