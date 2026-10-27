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
    measure_primary_display ppi
}

# Scale of the primary logical monitor, or nothing if mutter cannot be asked.
measure_primary_scale() {
    measure_primary_display scale
}

measure_primary_display() {
    python3 - "$1" <<'PY' 2>/dev/null
import glob, math, os, re, subprocess, sys

def primary_and_scale():
    """Connector name and scale of the primary logical monitor, per mutter."""
    try:
        out = subprocess.run(
            ["gdbus", "call", "--session", "--dest", "org.gnome.Mutter.DisplayConfig",
             "--object-path", "/org/gnome/Mutter/DisplayConfig",
             "--method", "org.gnome.Mutter.DisplayConfig.GetCurrentState"],
            capture_output=True, text=True, timeout=5).stdout
        # Match logical monitors: (x, y, scale, transform, is_primary, [('conn'...)])
        # Allow negative coordinates (-?\d+), integer/float scales, optional uint32,
        # and both true/false primary flags so single-monitor Wayland or offset layouts
        # don't fail to parse and default to 1.0 scale (which causes oversized panel icons).
        pattern = r"\(-?\d+,\s*-?\d+,\s*(?:@d\s+)?([0-9.]+),\s*(?:uint32\s+|@u\s+)?\d+,\s*(true|false),\s*\[\s*\(\s*'([^']+)'"
        matches = re.findall(pattern, out)
        if matches:
            for scale_s, is_pri, conn_name in matches:
                if is_pri == "true":
                    return conn_name, float(scale_s)
            return matches[0][2], float(matches[0][0])
    except Exception:
        pass
    return None, 1.0

conn, scale = primary_and_scale()

if sys.argv[1] == "scale":
    if conn:
        print(scale)
    sys.exit(0)

def ppi_of(path):
    try:
        w, h = (int(x) for x in open(path + "modes").read().split()[0].split("x"))
        edid = open(path + "edid", "rb").read()
        wcm, hcm = edid[21], edid[22]        # EDID basic params: image size in cm
        if not (wcm and hcm) and len(edid) >= 128:
            for offset in (54, 72, 90, 108):
                if offset + 18 <= len(edid):
                    if edid[offset] != 0 or edid[offset + 1] != 0:
                        h_mm = edid[offset + 12] | ((edid[offset + 14] & 0xF0) << 4)
                        v_mm = edid[offset + 13] | ((edid[offset + 14] & 0x0F) << 8)
                        if h_mm > 0 and v_mm > 0:
                            wcm, hcm = h_mm / 10.0, v_mm / 10.0
                            break
        if not (wcm and hcm):
            return None
        return math.hypot(w, h) / (math.hypot(wcm, hcm) / 2.54)
    except Exception:
        return None

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
        if conn and (name == conn or name.replace("-A-", "-") == conn.replace("-A-", "-")):
            best = ppi
            break
        if best is None:
            best = ppi
    except Exception:
        continue

if best and scale and scale > 0:
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

# How tall the top bar is, in logical pixels. The theme draws it at 40
# (`height: 40px` in the upstream sheet); --panel-height moves it anywhere from
# 24, about the shortest that still fits the panel's icons and clock, to 48.
# GNOME's own bar is `height: 2.2em` of the interface font, 32 px at its default
# Cantarell 11 (2.2 × 14.67 px), which is the height the settings window's
# reset button goes back to — a number rather than the em rule, so the seam
# snapping below applies to it as to any other.
#
# Remembered like the tints beside it: install_css rebuilds the generated sheet
# on every run, so an unremembered choice would last until the next install.
PANEL_HEIGHT_MIN=24
PANEL_HEIGHT_MAX=48
PANEL_HEIGHT_THEME=40
PANEL_HEIGHT_GNOME=32

# The height this run asks for: the flag, then the memo, then the theme's 40.
resolve_panel_height() {
    local want="${PANEL_HEIGHT:-}"
    [ -n "$want" ] || want="$(cat "$CONF_DIR/panel-height" 2>/dev/null || true)"
    case "$want" in
        '') want="$PANEL_HEIGHT_THEME" ;;
        *[!0-9]*) warn "--panel-height '$want' is not a whole number of pixels — using ${PANEL_HEIGHT_THEME}" >&2
                  want="$PANEL_HEIGHT_THEME" ;;
        *) if [ "$want" -lt "$PANEL_HEIGHT_MIN" ] || [ "$want" -gt "$PANEL_HEIGHT_MAX" ]; then
               warn "--panel-height $want is outside ${PANEL_HEIGHT_MIN}-${PANEL_HEIGHT_MAX} — using ${PANEL_HEIGHT_THEME}" >&2
               want="$PANEL_HEIGHT_THEME"
           fi ;;
    esac
    printf '%s
' "$want"
}

# Mutter's work area starts where the bar ends, so a maximized window's top
# edge lands exactly on the bar's height. At a scale where that height is not
# whole device pixels, both edges fall mid-pixel: the theme's 40 at 1.33 is
# 53.33 device px down, and device row 53 is under neither the bar's fill nor
# the window. It shows the blur behind them, unshaded, as a 1px light line
# between the bar and the window (seen on DP-1 at 1.33, 2026-10-27). Thirds
# scales (1.33, 1.67) are the ones 40 misses; 1.25, 1.5, 1.75 and 2 land whole.
#
# So the asked-for height is snapped to the nearest one that is whole device
# pixels at the primary scale (39 for 40 at thirds: 52 and 65 px), and the bar's
# fill and the window meet on a pixel edge. Ties go to the shorter bar. Nothing
# is written when that comes out at the theme's own 40. Like the density block
# it is measured once per run, so a later scale or primary change needs a
# retune. SCALE is 1 when mutter could not be asked, which snaps nothing.
panel_height_css() {   # SCALE HEIGHT
    python3 - "$1" "$2" "$PANEL_HEIGHT_THEME" <<'PY'
import sys
scale, want, theme = float(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
for h in sorted(range(want - 4, want + 5), key=lambda h: (abs(h - want), h)):
    if abs(h * scale - round(h * scale)) < 1e-3:
        break
else:
    h = want
if h == theme:
    sys.exit(0)
why = ("asked for at %dpx" % want) if want != theme else ("the theme's %dpx" % theme)
print(f"""
/* ---------- Top bar height for this scale -----------------------------
 * The top bar, {why}, is {h}px: {round(h * scale)} whole device pixels at
 * scale {scale:.2f}, so a maximized window meets it on a pixel edge rather than
 * mid-pixel over a 1px seam of unshaded blur. Generated at install time by
 * install.sh. */
#panel {{
  height: {h}px !important;
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

    if [ "$want" != "#000000" ] && [ -f "$CONF_DIR/gtk4-transparency.css" ]; then
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
    # If shell tint is not explicitly set, inherit app tint color
    if [ -z "$want" ]; then
        if [ -n "${APP_TINT_COLOR:-}" ]; then
            want="$APP_TINT_COLOR"
        elif [ -r "$CONF_DIR/app-tint-color" ]; then
            want="$(cat "$CONF_DIR/app-tint-color" 2>/dev/null || true)"
        fi
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

# How opaque popups, menus and notification banners are.
#
# One number for all of them, and by default the app windows' own: a desktop
# whose windows are made more see-through wants its menus to go with them, so
# without an answer of their own they follow --app-transparency. --popup-opacity
# is that answer, in the same unit ("as if the windows were at P"), and `main`
# hands them back to the windows. Opaque windows (level 0) count as 100.
#
# Both sheets were tuned with the windows at 90%, so every literal is scaled by
# P/90 rather than set: the popup ladder keeps its proportions and the banner's
# hover and pressed steps keep theirs (tools/apply-notification-opacity.py).
#
# Performance has no override: its solid sheet follows the level alone, as it
# always has, and a frosted choice in the memo does not reach it.
#
# Remembered like the tints beside it: install_css copies the sheets back from
# css/ on every run, so an unremembered choice would last until the next
# install and no longer.
POPUP_OPACITY_MIN=70
POPUP_OPACITY_MAX=100
POPUP_OPACITY_TUNED=90
# css/shell-notification-blur.css paints an arriving banner at 0.40.
NOTIFICATION_GROUND_TUNED=40
# Under 10% there is no ground left to read white text against, and over 85%
# the blur it sits on stops being visible at all.
NOTIFICATION_GROUND_MIN=10
NOTIFICATION_GROUND_MAX=85

# The override as remembered: a percentage inside the bounds, or `main`.
resolve_popup_opacity_choice() {
    local want="${POPUP_OPACITY:-}"
    if [ -z "$want" ]; then
        want="$(cat "$CONF_DIR/popup-opacity" 2>/dev/null || true)"
    fi
    surface_value_checked --popup-opacity "${want:-main}" \
        "$POPUP_OPACITY_MIN" "$POPUP_OPACITY_MAX"
}

# The percentage the popup sheets are painted at this run.
resolve_popup_opacity() {
    local choice level="${APP_TRANSPARENCY:-0}"
    choice="$(resolve_popup_opacity_choice)"
    if [ "${WANT_BLUR:-1}" = 1 ] && [ "$choice" != main ]; then
        printf '%s\n' "$choice"
        return 0
    fi
    case "$level" in
        0|0.0|0.00) printf '100\n' ;;
        *) python3 -c "print(round(float('$level') * 100))" 2>/dev/null || printf '%s\n' "$POPUP_OPACITY_TUNED" ;;
    esac
}

apply_notification_opacity() {
    local percent ground
    percent="$(resolve_popup_opacity)"
    ground=$(( (NOTIFICATION_GROUND_TUNED * percent + POPUP_OPACITY_TUNED / 2) / POPUP_OPACITY_TUNED ))
    [ "$ground" -lt "$NOTIFICATION_GROUND_MIN" ] && ground="$NOTIFICATION_GROUND_MIN"
    [ "$ground" -gt "$NOTIFICATION_GROUND_MAX" ] && ground="$NOTIFICATION_GROUND_MAX"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: paint the arriving banner at ${ground}%"
        return 0
    fi

    python3 "$REPO_ROOT/tools/apply-notification-opacity.py" "$CONF_DIR" "$ground" \
        | sed 's/^/    /' \
        || { warn "could not set the notification ground"; return 0; }
    ok "arriving banners at ${ground}% ground"
}

apply_popup_transparency() {
    local level="${APP_TRANSPARENCY:-0}" percent choice
    local sheet="$CONF_DIR/shell-popup-blur.css"
    local solid_sheet="$CONF_DIR/shell-80-solid.css"
    choice="$(resolve_popup_opacity_choice)"
    # Written whether or not a sheet is here to rewrite: it is the user's
    # answer, and the next frosted run reads it back.
    if [ "${WANT_BLUR:-1}" = 1 ] && remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$choice" > "$CONF_DIR/popup-opacity"
    fi
    [ -f "$sheet" ] || [ -f "$solid_sheet" ] || return 0
    percent="$(resolve_popup_opacity)"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: scale popup background alpha to ${percent}% of the windows' tuned 90%"
        return 0
    fi

    if [ -f "$sheet" ]; then
        python3 - "$sheet" "$(python3 -c "print('%.2f' % ($percent / 100))")" 0.90 0.85 <<'PY' || true
import sys, re
sheet, level_s, base_s, max_s = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    level = float(level_s)
    base = float(base_s)
    max_a = float(max_s)
except Exception:
    sys.exit(0)
if level <= 0 or level >= 1.5:
    sys.exit(0)

ratio = level / base
def repl(m):
    r, g, b, a = m.group(1), m.group(2), m.group(3), float(m.group(4))
    new_a = max(0.10, min(max_a, round(a * ratio, 2)))
    return f"rgba({r}, {g}, {b}, {new_a:.2f})"

with open(sheet, "r", encoding="utf-8") as f:
    content = f.read()
new_content = re.sub(r"rgba\((\d+),\s*(\d+),\s*(\d+),\s*(0\.\d+)\)", repl, content)
with open(sheet, "w", encoding="utf-8") as f:
    f.write(new_content)
PY
    fi

    if [ -f "$solid_sheet" ]; then
        python3 - "$solid_sheet" "$level" 0.99 1.00 <<'PY' || true
import sys, re
sheet, level_s, base_s, max_s = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    level = float(level_s)
    base = float(base_s)
    max_a = float(max_s)
except Exception:
    sys.exit(0)
if level <= 0 or level >= 1.5:
    sys.exit(0)

ratio = level / base
def repl(m):
    r, g, b, a = m.group(1), m.group(2), m.group(3), float(m.group(4))
    new_a = max(0.10, min(max_a, round(a * ratio, 2)))
    return f"rgba({r}, {g}, {b}, {new_a:.2f})"

with open(sheet, "r", encoding="utf-8") as f:
    content = f.read()
new_content = re.sub(r"rgba\((\d+),\s*(\d+),\s*(\d+),\s*(0\.\d+)\)", repl, content)
with open(sheet, "w", encoding="utf-8") as f:
    f.write(new_content)
PY
    fi
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

    # Every sheet is copied into $CONF_DIR, used by this mode or not: they cost
    # nothing while nothing splices them, and having them there is what makes
    # switching mode one run.

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
        run ln -sf "$HOME/.local/bin/aura-glass-apply" \
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

    if [ "${WANT_POPUP_BLUR:-1}" = 1 ]; then
        run install -Dm644 "$REPO_ROOT/css/shell-popup-blur.css" "$CONF_DIR/shell-popup-blur.css"
    else
        run rm -f "$CONF_DIR/shell-popup-blur.css"
    fi
    # The banners' sheet goes with the popups' since Blur My Shell v76, which
    # blurs a banner through the popup component's own pipeline and switch.
    if [ "${WANT_POPUP_BLUR:-1}" = 1 ]; then
        run install -Dm644 "$REPO_ROOT/css/shell-notification-blur.css" "$CONF_DIR/shell-notification-blur.css"
    else
        run rm -f "$CONF_DIR/shell-notification-blur.css"
    fi
    install_transparency_css
    install_window_control_style
    # Over the shell sheets this step has just laid down, and after the solid
    # and popup ones are decided, so whichever set is installed is the set that
    # gets the colour.
    apply_shell_tint_color
    apply_popup_transparency
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

    # Same sheet, appended after the density rules: both are per-screen and
    # both go when the sheet is removed above.
    local scale height
    height="$(resolve_panel_height)"
    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$height" > "$CONF_DIR/panel-height"
    fi
    scale="$(measure_primary_scale || true)"
    extra="$(panel_height_css "${scale:-1}" "$height")"
    if [ -z "$extra" ]; then
        :
    elif [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: top bar at ${height}px, snapped to whole pixels at scale ${scale:-1}"
    else
        printf '%s\n' "$extra" >> "$CONF_DIR/shell-90-density.css"
        ok "top bar at $(printf '%s' "$extra" | sed -n 's/^  height: \([0-9]*\)px.*/\1/p')px for ${height}px at scale ${scale:-1} (remembered for later runs)"
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: aura-glass-apply"
    else
        "$HOME/.local/bin/aura-glass-apply" --reload-gtk | sed 's/^/    /'
    fi
}
