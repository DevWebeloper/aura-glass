# shellcheck shell=bash
# aura-glass — the pieces that wire the desktop up.
#
# None of these change how anything looks. They exist because GNOME will
# otherwise undo, sandbox away, or mis-clip something the rest of the install
# just set: the icon key has no notion of a light/dark pair, a Flatpak app is
# sandboxed away from the GTK config, and Blur My Shell clips its panel actor to
# a geometry that is not settled at login.
#
# Sourced by install.sh.

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

    # Clean legacy units if present
    if [ -f "$HOME/.config/systemd/user/tahoe-glass-icon-sync.service" ]; then
        run systemctl --user disable --now tahoe-glass-icon-sync.service >/dev/null 2>&1 || true
        run rm -f "$HOME/.config/systemd/user/tahoe-glass-icon-sync.service"
    fi

    run install -Dm755 "$REPO_ROOT/bin/aura-glass-icon-sync" \
        "$HOME/.local/bin/aura-glass-icon-sync"
    ln -sf "$HOME/.local/bin/aura-glass-icon-sync" "$HOME/.local/bin/tahoe-glass-icon-sync" 2>/dev/null || true

    # The two memos this used to write live in remember_icon_pack now, called
    # from install_icons — this step does not run in the --settings-only path,
    # so a pack chosen from the window was never getting recorded here.

    run install -Dm644 "$REPO_ROOT/systemd/aura-glass-icon-sync.service" \
        "$HOME/.config/systemd/user/aura-glass-icon-sync.service"
    run systemctl --user daemon-reload
    run systemctl --user enable aura-glass-icon-sync.service >/dev/null 2>&1 || true

    # enable alone only arms it for the next login, and there is no reason to
    # make the user log out to see their icons follow the theme.
    if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        run systemctl --user restart aura-glass-icon-sync.service 2>/dev/null || true
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
        # Clean up any previously installed panel blur units
        local found=0 u
        for u in aura-glass-panel-blur.service tahoe-glass-panel-blur.service bms-panel-blur-rebuild.service; do
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

    for u in tahoe-glass-panel-blur.service bms-panel-blur-rebuild.service; do
        if [ -f "$HOME/.config/systemd/user/$u" ]; then
            run systemctl --user disable --now "$u" >/dev/null 2>&1 || true
            run rm -f "$HOME/.config/systemd/user/$u"
        fi
    done

    run install -Dm755 "$REPO_ROOT/bin/aura-glass-panel-blur" \
        "$HOME/.local/bin/aura-glass-panel-blur"
    ln -sf "$HOME/.local/bin/aura-glass-panel-blur" "$HOME/.local/bin/tahoe-glass-panel-blur" 2>/dev/null || true
    run install -Dm644 "$REPO_ROOT/systemd/aura-glass-panel-blur.service" \
        "$HOME/.config/systemd/user/aura-glass-panel-blur.service"
    run systemctl --user daemon-reload
    run systemctl --user enable aura-glass-panel-blur.service >/dev/null 2>&1 || true

    # enable only arms it for the next login, and the strip is on screen now.
    if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        run systemctl --user restart aura-glass-panel-blur.service 2>/dev/null || true
    fi
    ok "panel blur rebuilds on every monitor change, and once at login"
}
