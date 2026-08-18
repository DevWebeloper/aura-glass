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
    mkdir -p "$CONF_DIR"
    printf '%s\n' "$want" > "$memo"
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
    mkdir -p "$CONF_DIR"
    printf '%s\n' "$want" > "$memo"
    ok "shell surfaces tinted toward $want (remembered for later runs)"
}

install_transparency_css() {
    local level="${APP_TRANSPARENCY:-0}"

    if [ "$level" = 0 ] || [ "$level" = "0.0" ] || [ "$level" = "0.00" ]; then
        run rm -f "$CONF_DIR/gtk4-transparency.css"
        [ "${DRY_RUN:-0}" = 1 ] || { mkdir -p "$CONF_DIR"; printf '0\n' > "$CONF_DIR/app-transparency"; }
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

    mkdir -p "$CONF_DIR"
    printf '%s\n' "$level" > "$CONF_DIR/app-transparency"
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
# dconf key. It stays in the argument list so that one preset is one argument
# vector everywhere rather than two shapes to keep in step.
apply_radius_css() {
    local preset="${RADIUS_PRESET:-default}"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: rewrite the installed radii to the '$preset' preset"
        return 0
    fi

    python3 "$REPO_ROOT/tools/apply-radius-preset.py" "$CONF_DIR" \
        "$TOKEN_RADIUS_WINDOW" "$TOKEN_RADIUS_MENU" \
        "$TOKEN_RADIUS_QUICK_SETTINGS" "$TOKEN_RADIUS_NOTIFICATION" \
        "$TOKEN_RADIUS_DIALOG" "$TOKEN_RADIUS_POPUP" "$TOKEN_RADIUS_OSD" \
        | sed 's/^/    /'

    mkdir -p "$CONF_DIR"
    printf '%s\n' "$preset" > "$CONF_DIR/radius-preset"
    # The preset name alone is not enough to reconstruct `custom`, so the seven
    # values go beside it. Written from the resolved tokens rather than from the
    # flag, so the memo holds what was actually applied.
    if [ "$preset" = custom ]; then
        printf '%s,%s,%s,%s,%s,%s,%s\n' \
            "$TOKEN_RADIUS_WINDOW" "$TOKEN_RADIUS_MENU" \
            "$TOKEN_RADIUS_QUICK_SETTINGS" "$TOKEN_RADIUS_NOTIFICATION" \
            "$TOKEN_RADIUS_DIALOG" "$TOKEN_RADIUS_POPUP" "$TOKEN_RADIUS_OSD" \
            > "$CONF_DIR/radius-custom"
    fi
    ok "corner radii at the '$preset' preset (remembered for later runs)"
}

install_css() {
    step "Installing the CSS tweaks"

    # The shell and gtk4 sheets are split by concern, and the numeric prefix is
    # the cascade order aura-glass-apply concatenates them in. Copy whatever
    # css/ actually holds rather than naming each one twice.
    local sheet
    for sheet in "$REPO_ROOT"/css/shell-[0-9][0-9]-*.css \
                 "$REPO_ROOT"/css/gtk4-[0-9][0-9]-*.css; do
        run install -Dm644 "$sheet" "$CONF_DIR/$(basename "$sheet")"
    done
    run install -Dm644 "$REPO_ROOT/css/gtk3-tweaks.css"  "$CONF_DIR/gtk3-tweaks.css"
    run install -Dm755 "$REPO_ROOT/bin/aura-glass-apply" "$HOME/.local/bin/aura-glass-apply"
    ln -sf "$HOME/.local/bin/aura-glass-apply" "$HOME/.local/bin/tahoe-glass-apply" 2>/dev/null || true

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

    if [ "${WANT_POPUP_BLUR:-1}" = 1 ]; then
        run install -Dm644 "$REPO_ROOT/css/shell-popup-blur.css" "$CONF_DIR/shell-popup-blur.css"
    else
        run rm -f "$CONF_DIR/shell-popup-blur.css"
    fi
    install_transparency_css
    # Over the shell sheets this step has just laid down, and after the solid
    # and popup ones are decided, so whichever set is installed is the set that
    # gets the colour.
    apply_shell_tint_color
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
