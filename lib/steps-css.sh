# shellcheck shell=bash
# aura-glass — the CSS tweaks, and the display-density correction.
#
# install_css copies whatever css/ holds into $CONF_DIR and then runs
# bin/aura-glass-apply, which concatenates the sheets in cascade order into one
# marked block. The numeric prefix on a sheet is its cascade position, not
# decoration; tools/check-cascade.sh asserts the two agree.
#
# The density block is generated here rather than kept in css/, because it is
# written for whatever screen the installer is actually run on.
#
# Sourced by install.sh.

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
# The colour a translucent app window is darkened toward, which ships as black.
#
# Remembered, like the level it sits beside: the sheet is copied fresh from
# css/ on every run, so an unremembered colour would last exactly until the
# next install and then silently go back to smoked grey.
#
# Black is not written back through the rewriter, it is simply the shipped
# state — so the default costs no work, and choosing black again restores the
# sheet byte-for-byte rather than approximately.
apply_app_tint_color() {
    local want="${APP_TINT_COLOR:-}" memo="$CONF_DIR/app-tint-color"
    if [ -z "$want" ] && [ -r "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ -n "$want" ] || return 0

    case "$want" in
        \#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
        *) warn "--app-tint-color wants a #rrggbb colour, got '$want'"
           return 0 ;;
    esac

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: tint the translucent grounds toward $want"
        return 0
    fi

    if [ "$want" != "#000000" ]; then
        python3 "$REPO_ROOT/tools/apply-tint-color.py" \
            "$CONF_DIR/gtk4-transparency.css" "$want" | sed 's/^/    /' \
            || { warn "could not tint the app windows"; return 0; }
    fi
    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi
    ok "app windows tinted toward $want (remembered for later runs)"
}

# The same question for the shell's own surfaces, and a different answer,
# because they have no single tint to swap — tools/apply-shell-tint.py explains
# what it does instead and why it only ever moves the colour of a ground and
# never its lightness.
#
# Runs over what install_css has just copied into $CONF_DIR, so like the app
# tint it never compounds and never touches css/.
apply_shell_tint_color() {
    local want="${SHELL_TINT_COLOR:-}" memo="$CONF_DIR/shell-tint-color"
    if [ -z "$want" ] && [ -r "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ -n "$want" ] || return 0

    case "$want" in
        \#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
        *) warn "--shell-tint-color wants a #rrggbb colour, got '$want'"
           return 0 ;;
    esac

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: tint the shell's dark surfaces toward $want"
        return 0
    fi

    if [ "$want" != "#000000" ]; then
        python3 "$REPO_ROOT/tools/apply-shell-tint.py" "$CONF_DIR" "$want" \
            | sed 's/^/    /' \
            || { warn "could not tint the shell surfaces"; return 0; }
    fi
    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi
    ok "shell surfaces tinted toward $want (remembered for later runs)"
}

# How much ground an arriving notification paints over its own blur.
#
# Its own number rather than a share of the app windows' opacity, because the
# two are not the same question. A window's level says how much of the desktop
# shows through a surface you are working in; this says how readable a banner
# that arrived unasked has to be over whatever happened to be behind it, and a
# desktop tuned for one is regularly wrong for the other.
#
# Bounds rather than the full range. Under 10% there is no ground left to read
# white text against, and over 85% the blur it sits on stops being visible at
# all — at which point the notification blur switch is the control being asked
# for, not this one.
#
# Remembered like the tints beside it: install_css copies the sheet back from
# css/ on every run, so an unremembered choice would last until the next
# install and no longer.
NOTIFICATION_OPACITY_MIN=10
NOTIFICATION_OPACITY_MAX=85

apply_notification_opacity() {
    local want="${NOTIFICATION_OPACITY:-}" memo="$CONF_DIR/notification-opacity"
    if [ -z "$want" ] && [ -r "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ -n "$want" ] || return 0

    case "$want" in
        ''|*[!0-9]*) warn "--notification-opacity wants a whole percentage, got '$want'"
                     return 0 ;;
    esac
    if [ "$want" -lt "$NOTIFICATION_OPACITY_MIN" ] || [ "$want" -gt "$NOTIFICATION_OPACITY_MAX" ]; then
        warn "--notification-opacity $want is outside ${NOTIFICATION_OPACITY_MIN}-${NOTIFICATION_OPACITY_MAX} — leaving the banner ground alone"
        return 0
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: paint the arriving banner at ${want}%"
        return 0
    fi

    python3 "$REPO_ROOT/tools/apply-notification-opacity.py" "$CONF_DIR" "$want" \
        | sed 's/^/    /' \
        || { warn "could not set the notification ground"; return 0; }
    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi
    ok "arriving banners at ${want}% ground (remembered for later runs)"
}

install_transparency_css() {
    local level="${APP_TRANSPARENCY:-0}"

    if [ "$level" = 0 ] || [ "$level" = "0.0" ] || [ "$level" = "0.00" ]; then
        run rm -f "$CONF_DIR/gtk4-transparency.css"
        if remembering; then mkdir -p "$CONF_DIR"; printf '0\n' > "$CONF_DIR/app-transparency"; fi
        return 0
    fi

    run install -Dm644 "$REPO_ROOT/css/gtk4-transparency.css" "$CONF_DIR/gtk4-transparency.css"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: rewrite the transparency sheet to $level"
        # Said here too, because this return is above the real call below and a
        # dry run that listed the rescale but not the recolour would be
        # describing half of what the run does.
        apply_app_tint_color
        return 0
    fi

    # One implementation, shared with tools/preview.sh, so a preview is the
    # same arithmetic as the install rather than a second copy of it that can
    # drift. It also has to know the tint blocks from the level rules: both are
    # written as `var(--x) N%`, and an earlier regex here matched either, which
    # would have rescaled the tint itself at any level but the default.
    run python3 "$REPO_ROOT/tools/rescale-transparency.py" \
        "$CONF_DIR/gtk4-transparency.css" "$level" \
        "$TOKEN_APP_TRANSPARENCY_SHIPPED"

    # After the rescale, and on the same installed copy. The two rewriters do
    # not overlap — one moves the alphas, the other the colour they are applied
    # over — but the order is fixed anyway so that what a preview renders is
    # what an install produces.
    apply_app_tint_color

    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$level" > "$CONF_DIR/app-transparency"
    fi
    local pct
    pct="$(python3 -c "print(round(float('$level')*100))" 2>/dev/null || echo "$level")"
    ok "app windows translucent at $level (${pct}% opacity, remembered for later runs)"
}

# The sheets in css/ are written at the `default` row of radius_preset_values in
# tokens/tokens.sh, and install_css has just copied them into $CONF_DIR at that
# value. A different preset is applied to those copies rather than to css/, for
# the same reason install_transparency_css rescales the installed
# gtk4-transparency.css instead of the repo's: css/ stays at one known state
# that tools/check-tokens.sh can keep checking, and what gets rewritten is only
# ever what is actually loaded.
#
# Which sites move is tools/token_manifest.py's answer — the same list the
# checker asserts against — so a radius the checker watches is a radius a preset
# can move, and neither can quietly fall out of step with the other.
#
# The OSD radius is passed but has no stylesheet to rewrite: Custom OSD draws the
# pill and Blur My Shell rounds the blur, so apply_radius_dconf writes it as a
# dconf key. BUTTON is the opposite case — a stylesheet site and no dconf key —
# so it moves here and apply_radius_dconf skips it. Both stay in the argument
# vector so that one preset is one argument vector everywhere rather than two
# shapes to keep in step.
apply_radius_css() {
    # The row, not the name that was typed for it: a memo written at a retired
    # name would keep that name for good, and every later reader would have to
    # go on knowing it. radius_preset_canonical in tokens/tokens.sh is the one
    # place that maps one to the other.
    local preset
    preset="$(radius_preset_canonical "${RADIUS_PRESET:-default}")"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: rewrite the installed radii to the '$preset' preset"
        return 0
    fi

    python3 "$REPO_ROOT/tools/apply-radius-preset.py" "$CONF_DIR" \
        "$TOKEN_RADIUS_WINDOW" "$TOKEN_RADIUS_MENU" \
        "$TOKEN_RADIUS_QUICK_SETTINGS" "$TOKEN_RADIUS_NOTIFICATION" \
        "$TOKEN_RADIUS_DIALOG" "$TOKEN_RADIUS_POPUP" "$TOKEN_RADIUS_OSD" \
        "$TOKEN_RADIUS_BUTTON" \
        | sed 's/^/    /'

    # The rewrite above happens in a preview too — that is the whole point of
    # one — but the memo below must not: see remembering() in lib/common.sh.
    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$preset" > "$CONF_DIR/radius-preset"
        # The preset name alone is not enough to reconstruct `custom`, so the
        # eight values go beside it. Written from the resolved tokens rather
        # than from the flag, so the memo holds what was actually applied.
        #
        # Removed again on the way to a named row, rather than left to go stale.
        # install.sh only reads it while the preset is `custom` — so a stale one
        # sat there unread until some later --radius-preset custom with no
        # --radius-custom beside it, which then came up wearing eight values
        # from months earlier instead of failing with "needs eight values".
        if [ "$preset" = custom ]; then
            printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
                "$TOKEN_RADIUS_WINDOW" "$TOKEN_RADIUS_MENU" \
                "$TOKEN_RADIUS_QUICK_SETTINGS" "$TOKEN_RADIUS_NOTIFICATION" \
                "$TOKEN_RADIUS_DIALOG" "$TOKEN_RADIUS_POPUP" \
                "$TOKEN_RADIUS_OSD" "$TOKEN_RADIUS_BUTTON" \
                > "$CONF_DIR/radius-custom"
        else
            rm -f "$CONF_DIR/radius-custom"
        fi
    fi
    ok "corner radii at the '$preset' preset (remembered for later runs)"
}

# Which titlebar-button look ships, on top of the size/colour base every look
# shares (gtk4-50-window-controls.css / gtk3-tweaks.css). Un-prefixed sheets,
# same as gtk4-transparency.css: installed or removed rather than switched on
# at read time, since aura-glass-apply concatenates whatever it finds in
# $CONF_DIR and cannot know which style this install was given. At most one of
# the three is ever present — "minimal" is the base sheets' own look and adds
# nothing on top.
install_window_control_style() {
    local want="${TITLEBUTTON_STYLE:-}" memo="$CONF_DIR/titlebutton-style"
    if [ -z "$want" ] && [ -f "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ -n "$want" ] || want="minimal"

    run rm -f "$CONF_DIR/gtk4-window-controls-adwaita.css" \
              "$CONF_DIR/gtk3-window-controls-adwaita.css" \
              "$CONF_DIR/gtk4-window-controls-material.css" \
              "$CONF_DIR/gtk3-window-controls-material.css" \
              "$CONF_DIR/gtk4-window-controls-flat.css" \
              "$CONF_DIR/gtk3-window-controls-flat.css"
    case "$want" in
        adwaita)
            run install -Dm644 "$REPO_ROOT/css/gtk4-window-controls-adwaita.css" \
                               "$CONF_DIR/gtk4-window-controls-adwaita.css"
            run install -Dm644 "$REPO_ROOT/css/gtk3-window-controls-adwaita.css" \
                               "$CONF_DIR/gtk3-window-controls-adwaita.css"
            ;;
        material)
            run install -Dm644 "$REPO_ROOT/css/gtk4-window-controls-material.css" \
                               "$CONF_DIR/gtk4-window-controls-material.css"
            run install -Dm644 "$REPO_ROOT/css/gtk3-window-controls-material.css" \
                               "$CONF_DIR/gtk3-window-controls-material.css"
            ;;
        flat)
            run install -Dm644 "$REPO_ROOT/css/gtk4-window-controls-flat.css" \
                               "$CONF_DIR/gtk4-window-controls-flat.css"
            run install -Dm644 "$REPO_ROOT/css/gtk3-window-controls-flat.css" \
                               "$CONF_DIR/gtk3-window-controls-flat.css"
            ;;
        minimal) ;;
        *) warn "unknown --titlebar-button-style '$want' — leaving it at minimal"
           want="minimal" ;;
    esac

    if [ "${DRY_RUN:-0}" != 1 ] && [ -n "${TITLEBUTTON_STYLE:-}" ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi
}

install_css() {
    step "Installing the CSS tweaks"

    # The marker goes down before aura-glass-apply runs at the end of this
    # function, because that is what reads it. The sheets are copied into
    # $CONF_DIR either way: they cost nothing while nothing splices them, and
    # having them there is what makes coming back out of solid mode one run.
    [ "${DRY_RUN:-0}" = 1 ] || sync_styling_marker

    # The shell and gtk4 sheets are split by concern, and the numeric prefix is
    # the cascade order aura-glass-apply concatenates them in. Copy whatever
    # css/ actually holds rather than naming each one twice.
    local sheet
    for sheet in "$REPO_ROOT"/css/shell-[0-9][0-9]-*.css \
                 "$REPO_ROOT"/css/gtk4-[0-9][0-9]-*.css; do
        run install -Dm644 "$sheet" "$CONF_DIR/$(basename "$sheet")"
    done
    run install -Dm644 "$REPO_ROOT/css/gtk3-tweaks.css"  "$CONF_DIR/gtk3-tweaks.css"
    # Standalone apply and preview use this installed stdlib helper after the
    # checkout is gone, so keep it with their durable user-level assets. A
    # preview already runs through that helper; refreshing it on each slider
    # tick would turn a candidate render into artifact reconciliation.
    if [ "${PREVIEW_MODE:-0}" != 1 ]; then
        install_if_changed "$REPO_ROOT/tools/aura_glass_operation.py" \
            "$HOME/.local/share/aura-glass/aura_glass_operation.py" 755
        install_if_changed "$REPO_ROOT/bin/aura-glass-operation" \
            "$HOME/.local/bin/aura-glass-operation" 755
        install_if_changed "$REPO_ROOT/bin/aura-glass-apply" \
            "$HOME/.local/bin/aura-glass-apply" 755
        ln -sf "$HOME/.local/bin/aura-glass-apply" \
            "$HOME/.local/bin/tahoe-glass-apply" 2>/dev/null || true
    fi

    # Upgrading from a version that shipped one sheet per target. Both names are
    # gone from aura-glass-apply's lists, so leaving them would only be dead
    # weight — but they were also the file the density block used to be appended
    # to, and that copy would still be found by an older apply script.
    run rm -f "$CONF_DIR/shell-tweaks.css" "$CONF_DIR/gtk4-tweaks.css"

    # Installed or removed rather than switched on at read time: aura-glass-apply
    # concatenates whatever it finds in $CONF_DIR and has no way to know which
    # options this install was given.
    # --no-blur swaps the translucent ladder for opaque surfaces. Installed or
    # removed rather than switched on at read time, for the same reason as the
    # sheets below: aura-glass-apply concatenates what it finds and cannot know
    # which options this install was given.
    if [ "${WANT_BLUR:-1}" = 1 ]; then
        run rm -f "$CONF_DIR/shell-80-solid.css"
    else
        run install -Dm644 "$REPO_ROOT/css/shell-80-solid.css" "$CONF_DIR/shell-80-solid.css"
    fi

    if [ "${WANT_POPUP_BLUR:-1}" = 1 ] && [ "${LIQUID_GLASS_EFFECTIVE:-0}" != 1 ]; then
        run install -Dm644 "$REPO_ROOT/css/shell-popup-blur.css" "$CONF_DIR/shell-popup-blur.css"
    else
        run rm -f "$CONF_DIR/shell-popup-blur.css"
    fi
    if [ "${WANT_NOTIFICATION_BLUR:-1}" = 1 ] && [ "${LIQUID_GLASS_EFFECTIVE:-0}" != 1 ]; then
        run install -Dm644 "$REPO_ROOT/css/shell-notification-blur.css" "$CONF_DIR/shell-notification-blur.css"
    else
        run rm -f "$CONF_DIR/shell-notification-blur.css"
    fi
    if [ "${LIQUID_GLASS_EFFECTIVE:-0}" = 1 ]; then
        run install -Dm644 "$REPO_ROOT/css/shell-liquid-glass.css" "$CONF_DIR/shell-liquid-glass.css"
    else
        run rm -f "$CONF_DIR/shell-liquid-glass.css"
    fi
    install_transparency_css
    install_window_control_style
    # Over the shell sheets this step has just laid down, and after the solid
    # and popup ones are decided, so whichever set is installed is the set that
    # gets the colour.
    apply_shell_tint_color
    # The other rewriter over that same sheet, and independent of the tint above
    # it: that one owns a literal's colour channels, this one owns its alpha, so
    # the order between the two does not matter and neither undoes the other.
    apply_notification_opacity
    # After the copies are all in place, and before aura-glass-apply splices
    # them: both rewriters edit what install_css just laid down, so neither can
    # run before the file it edits exists.
    apply_radius_css
    ok "css -> $CONF_DIR"
    ok "re-apply command -> ~/.local/bin/aura-glass-apply"

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
        info "dry-run: aura-glass-apply"
    else
        "$HOME/.local/bin/aura-glass-apply" | sed 's/^/    /'
    fi
}
