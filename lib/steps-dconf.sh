# shellcheck shell=bash
# aura-glass — the dconf preset, and the gsettings that go with it.
#
# dconf/core.ini holds the preset so it stays readable in one file. What cannot
# live there is anything whose right value depends on the machine or on a flag,
# because dconf load rewrites the whole section on every run — so a flagless
# re-install would quietly undo a deliberate choice. Those keys are written
# afterwards by the apply_* functions here, several of which remember the answer
# in $CONF_DIR for exactly that reason.
#
# Sourced by install.sh.

# The keys a glass mode owns are exactly the ones dconf/solid.ini sets: every
# Blur My Shell component's blur switch, its hacks level and the OSD alpha.
# A fresh install gets them from loading the preset, but an existing install
# skips the preset to keep the user's own extension settings — so on that path
# a mode switch used to move only the three components an apply_* below owns
# (popup, notification, applications) and leave the panel, overview, folders,
# lock screen, window list, screenshot and dock in the previous mode.
#
# Prints "section/key<TAB>value" for each owned key: solid.ini's value when
# blur is off, core.ini's value for the same key when it is on.
mode_owned_dconf_keys() {
    python3 - "$REPO_ROOT/dconf/solid.ini" "$REPO_ROOT/dconf/core.ini" "$1" <<'PY'
import configparser
import sys


def load(path):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    parser.read(path, encoding="utf-8")
    return parser


solid, core, blur = load(sys.argv[1]), load(sys.argv[2]), sys.argv[3]
for section in solid.sections():
    for key, value in solid.items(section):
        if blur == "1":
            if not core.has_option(section, key):
                continue
            value = core.get(section, key)
        print("%s/%s\t%s" % (section, key, value))
PY
}

# Performance always gets its keys — they are the mode's whole promise of no
# blur cost, and a user's own blur settings have nothing to say while blur is
# off. Frosted gets core.ini's values back only on the way in from another
# mode, so a per-component choice made inside frosted (say, no lock screen
# blur) survives an ordinary retune.
sync_mode_owned_keys() {
    local want="${WANT_BLUR:-1}" previous target key value
    previous="$(cat "$CONF_DIR/glass-mode" 2>/dev/null || true)"
    target="$(glass_mode_from_state)"
    if [ "$want" = 1 ] && [ "${previous:-frosted}" = "$target" ]; then
        return 0
    fi
    while IFS="$(printf '\t')" read -r key value; do
        [ -n "$key" ] || continue
        run dconf write "/org/gnome/shell/extensions/$key" "$value"
    done < <(mode_owned_dconf_keys "$want")
    if [ "$want" = 1 ]; then
        ok "frosted mode's blur components restored from the preset"
    else
        ok "every blur component off for performance mode"
    fi
}

load_dconf() {
    step "Loading the dconf preset"

    local is_update=0
    if [ -f "$CONF_DIR/repo-path" ] || [ -f "$CONF_DIR/accent" ]; then
        if [ ! -f "$CONF_DIR/uninstalled" ]; then
            is_update=1
        fi
    fi

    # Even on update, if core dconf keys are completely missing (e.g. after a
    # minimal uninstall reset), reload the preset so Blur My Shell pipelines exist.
    local has_core_dconf=0
    if [ -n "$(dconf read /org/gnome/shell/extensions/blur-my-shell/pipelines 2>/dev/null || true)" ]; then
        has_core_dconf=1
    fi

    if [ "$is_update" = 1 ] && [ "$has_core_dconf" = 1 ] && [ "${FORCE:-0}" != 1 ]; then
        ok "existing extension settings preserved (theme update)"
        sync_mode_owned_keys
    else
        if [ "${DRY_RUN:-0}" = 1 ]; then
            info "dry-run: dconf load /org/gnome/shell/extensions/ < dconf/core.ini"
        else
            dconf load /org/gnome/shell/extensions/ < "$REPO_ROOT/dconf/core.ini" \
                || die "dconf load failed"
        fi
        ok "core look loaded"

        # Applied over the top rather than as a separate preset, so performance is
        # one overlay to read and to review rather than a second full copy of every
        # key that would then have to be kept in step with core.ini.
        if [ "${WANT_BLUR:-1}" != 1 ]; then
            if [ "${DRY_RUN:-0}" = 1 ]; then
                info "dry-run: dconf load /org/gnome/shell/extensions/ < dconf/solid.ini"
            else
                dconf load /org/gnome/shell/extensions/ < "$REPO_ROOT/dconf/solid.ini" \
                    || die "dconf load of the solid preset failed"
            fi
            ok "performance preset loaded — no blur, opaque surfaces"
        fi

        if [ "${WANT_EXTRAS:-0}" = 1 ]; then
            if [ "${DRY_RUN:-0}" = 1 ]; then
                info "dry-run: dconf load /org/gnome/shell/extensions/ < dconf/extras.ini"
            else
                dconf load /org/gnome/shell/extensions/ < "$REPO_ROOT/dconf/extras.ini" || true
            fi
            ok "optional extension settings loaded"
        fi
    fi

    apply_grain
    apply_blur_strength
    apply_popup_brightness
    apply_window_brightness
    apply_popup_blur
    apply_notification_blur
    apply_app_blur
    apply_app_opacity
    apply_fullscreen_blur
    pin_frosted_hacks_level
    apply_radius_dconf
    apply_glass_style
    sync_osd_profile
    refresh_bms_after_dconf
}

# The seven of the eight corner radii that Blur My Shell rounds its blur
# actors at — TOKEN_RADIUS_BUTTON has no blur actor behind it and is skipped
# here, only ever painted by apply_radius_css. dconf/core.ini
# ships them at the `default` row of radius_preset_values in tokens/tokens.sh,
# and dconf load has just written that row — so like every other apply_* here,
# this runs afterwards to put a flag's or a remembered choice's value back over
# the preset's.
#
# The project rule these exist to keep: a painted radius must equal the blur
# radius behind it. apply_radius_css moved the painted half in $CONF_DIR; this is
# the blur half, and the two read the same TOKEN_RADIUS_* variables from the same
# call to radius_preset_values so they cannot disagree.
#
# Two of these have no painted counterpart at all. `corner-radius` under popup is
# the generic fallback for surfaces the specific keys do not claim, and
# `osd-corner-radius` belongs to a pill Custom OSD draws rather than to any
# stylesheet — see TOKEN_RADIUS_OSD for why that one does not simply scale with
# the rest.
apply_radius_dconf() {
    local base=/org/gnome/shell/extensions/blur-my-shell

    # Nothing here is Blur My Shell's to round when Blur My Shell is not
    # installed. The painted radii still moved: apply_radius_css runs
    # regardless, because in performance the corner is all there is.
    if [ "${WANT_BLUR:-1}" != 1 ]; then
        skip "blur corner radii left alone (--no-blur — no blur to round)"
        return 0
    fi

    run dconf write "$base/applications/corner-radius" "$TOKEN_RADIUS_WINDOW"
    run dconf write "$base/popup/menu-corner-radius" "$TOKEN_RADIUS_MENU"
    run dconf write "$base/popup/quick-settings-corner-radius" "$TOKEN_RADIUS_QUICK_SETTINGS"
    run dconf write "$base/popup/notification-corner-radius" "$TOKEN_RADIUS_NOTIFICATION"
    run dconf write "$base/popup/dialog-corner-radius" "$TOKEN_RADIUS_DIALOG"
    run dconf write "$base/popup/corner-radius" "$TOKEN_RADIUS_POPUP"
    run dconf write "$base/popup/osd-corner-radius" "$TOKEN_RADIUS_OSD"
    apply_pipeline_radius
    ok "blur corner radii follow the '${RADIUS_PRESET:-default}' preset"
}

# The window corner again, in the other place Blur My Shell keeps it.
#
# [applications] names a pipeline, and that pipeline carries a `corner` effect
# with a radius of its own — so the blur behind an app window is rounded twice
# over, by corner-radius above and by the effect here. Only the first moved with
# a preset, which left a `soft` desktop rounding one at 16 and the other at 30:
# the two-stacked-surfaces fault tokens/tokens.sh exists to prevent, inside a
# single component.
#
# Every pipeline lives in one GVariant blob under `pipelines`, so this is a
# read-modify-write of one number inside it rather than a key to set. The
# pattern comes from tools/token_manifest.py — the same list
# tools/check-tokens.sh asserts dconf/core.ini against — so the shipped value
# and the value moved here cannot drift apart. It matches by pipeline name: the
# id beside it is generated per machine and is not a thing to hard-code.
#
# The other three corner effects are left alone deliberately. `panel` and `dock`
# round surfaces that are not among the eight a preset covers, and
# `default rounded` is named by no component at all.
#
# Runs after apply_blur_strength, which rewrites the same key. That one only
# ever touches `unscaled_radius`, so the two do not fight over a value — but it
# also resets the whole blob from the shipped literal in bin/aura-glass-preview,
# so the order is fixed rather than incidental.
apply_pipeline_radius() {
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: round the windows blur pipeline at $TOKEN_RADIUS_WINDOW"
        return 0
    fi
    python3 - "$REPO_ROOT" "$TOKEN_RADIUS_WINDOW" <<'PIPELINE_PY' || { warn "could not round the windows blur pipeline"; return 0; }
import os
import re
import subprocess
import sys

root, want = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(root, "tools"))
from token_manifest import raw_entries

KEY = "/org/gnome/shell/extensions/blur-my-shell/pipelines"
cur = subprocess.run(["dconf", "read", KEY],
                     capture_output=True, text=True).stdout.strip()
if not cur:
    sys.exit(0)

new = cur
for _token, _kind, _rel, pattern in raw_entries({"TOKEN_RADIUS_WINDOW"}):
    matches = list(re.finditer(pattern, new, re.M))
    if not matches:
        # Blur My Shell renamed the pipeline, or this machine never had it.
        # Said out loud rather than passed over: the painted corner has already
        # moved by the time this runs, so a silent miss here is exactly the
        # mismatch this function exists to close.
        print("no `windows` pipeline in %s — its blur corner stays where it is"
              % KEY, file=sys.stderr)
        continue
    # From the end, so an earlier replacement cannot move a later span.
    for m in reversed(matches):
        for i in range(1, (m.lastindex or 0) + 1):
            start, end = m.span(i)
            new = new[:start] + want + new[end:]

# dconf prints a double back in full (0.7 as 0.69999999999999996), so the
# texts differ even when nothing moved. Compared as numbers, an unchanged
# blob is not written again — a pipelines write rebuilds every blur effect.
_num = re.compile(r"-?\d+\.\d+(?:e[-+]?\d+)?")
if (_num.sub(lambda m: repr(float(m.group())), new)
        != _num.sub(lambda m: repr(float(m.group())), cur)):
    subprocess.run(["dconf", "write", KEY, new], check=True)
PIPELINE_PY
}

# The material on the top bar and the dock, and optionally behind app windows:
# frosted (the blur alone), liquid (Blur My Shell's refraction effect after
# the blur: the edge band bends the blurred backdrop like a lens and catches a
# light rim), vibrant (Blur My Shell's luminosity effect after the blur: the
# colours behind the glass come through more saturated and a little brighter,
# as macOS vibrancy does), tinted (Blur My Shell's color effect: the glass
# takes on the accent's hue) or smoked (the luminosity effect again, darker
# and greyer, so white text on it reads more easily).
#
# Only on static blur. Blur My Shell runs a pipeline's extra effects on static
# blur alone: a dynamic surface goes through DummyPipeline, which builds the
# native blur and nothing else from it. Chaining one more shader after a
# dynamic blur does not work either. The shader gets the actor's own texture,
# which is empty, not the blurred backdrop. That is the same reason a dynamic
# popup's corners come out square without gnome-rounded-blur (see
# [blur-my-shell/popup] in dconf/core.ini). So liquid switches the dock to
# static blur, which blurs the wallpaper rather than the windows passing behind
# it. App windows follow only when --liquid-windows asks, for the same trade
# on a much bigger surface: every blurred window then shows the wallpaper
# behind it, not the window under it. Menus and notifications keep their
# dynamic frosted blur. Their pipeline is one for every popup surface, with
# radii from 12 to 33, and one refraction corner radius cannot fit them all.
#
# Static blur is computed once per wallpaper or layout change, so the shader
# costs nothing while the desktop repaints. Measured on the panel with
# tools/gpu-sample.py (amdgpu, 15 s idle): median 20% liquid and frosted alike.
#
# Vibrant reaches one surface more than liquid: pipeline `lock screen`, the
# blurred wallpaper behind the overview and the lock screen. Both are static
# blur already, and the luminosity effect draws no edge, so it has no corner
# radius to match and none of the popup pipeline's trouble. Unlike liquid it
# leaves the dock alone: the dock keeps its dynamic blur of the windows behind
# it, and so stays frosted, because a dynamic surface never runs the effect.
# A colour boost there was not worth the live blur. App windows follow when
# --liquid-windows asks, with the same trade as
# liquid's (the flag and its memo keep liquid's name, which came first). The
# switch is kept under frosted, so going back to either style brings the
# windows back the way they were.
#
# Tinted and smoked reach what vibrant reaches, the top bar and pipeline
# `lock screen`, and leave the dock dynamic for the same reason. They never
# switch app windows to static: --liquid-windows is ignored under them, and
# a switch from liquid or vibrant with windows on puts the windows' dynamic
# blur back. Each already has a dynamic-safe counterpart on windows, owned by
# its own flag and memo and left alone here: smoked is what a lower
# --window-brightness does to the native blur behind a window, and tinted is
# what --app-tint-color does to the window's own ground.
#
# The refraction effect rounds its own edge, so its corner radius must be the
# one the pipeline's corner effect cuts at, or the rim would bend a corner the
# corner effect has already cut away. It is read from that effect at run time
# rather than kept as another copy of the number.
#
# Our effects are told apart by their id prefix and removed before anything is
# added, so a re-run, a switch back to frosted and apply_blur_strength's blob
# rewrites all land in the same state.
VALID_GLASS_STYLES="frosted liquid vibrant tinted smoked"

# The styles that may take app windows (--liquid-windows) along.
glass_style_takes_windows() {   # STYLE
    [ "$1" = liquid ] || [ "$1" = vibrant ]
}

# GNOME's nine accents as RGB, for tinted's color effect. GNOME exposes the
# accent only as a name (org.gnome.desktop.interface accent-color, a
# read-only keyword to St; see tokens/tokens.sh), and Blur My Shell's color
# effect wants numbers, so this is the one place a name becomes a colour for
# the shell. The values are libadwaita's accent backgrounds, the colour every
# GTK app paints that accent in, so the tinted bar matches the apps' buttons.
# gui/aura_glass_setup_wizard.py's ACCENTS swatches are the other copy;
# tools/check-wizard-flags.py asserts the two agree.
accent_hex() {   # NAME
    case "$1" in
        blue)   echo 3584e4 ;;
        teal)   echo 2190a4 ;;
        green)  echo 3a944a ;;
        yellow) echo c88800 ;;
        orange) echo ed5b00 ;;
        red)    echo e62d42 ;;
        pink)   echo d56199 ;;
        slate)  echo 6f8396 ;;
        *)      echo 9141ac ;;   # purple, and ACCENT_DEFAULT
    esac
}

# Puts one static-blur key back to what dconf/core.ini ships, or to Blur My
# Shell's own default where core.ini does not set it ([applications] does not).
restore_static_blur() {   # SECTION
    local value
    value="$(awk -F= -v sec="[blur-my-shell/$1]" '/^\[/{s=($0==sec)} s&&$1=="static-blur"{print $2; exit}' \
        "$REPO_ROOT/dconf/core.ini")"
    if [ -n "$value" ]; then
        run dconf write "/org/gnome/shell/extensions/blur-my-shell/$1/static-blur" "$value"
    else
        run dconf reset "/org/gnome/shell/extensions/blur-my-shell/$1/static-blur"
    fi
}

apply_glass_style() {
    local base=/org/gnome/shell/extensions/blur-my-shell
    local want="${GLASS_STYLE:-}" memo="$CONF_DIR/glass-style" previous
    local windows="${LIQUID_WINDOWS:-}" windows_memo="$CONF_DIR/liquid-windows" previous_windows
    previous="$(cat "$memo" 2>/dev/null || true)"
    previous_windows="$(cat "$windows_memo" 2>/dev/null || true)"
    if [ -z "${GLASS_STYLE_EXPLICIT:-}" ] || [ -z "$want" ]; then
        want="${previous:-frosted}"
    fi
    case " $VALID_GLASS_STYLES " in
        *" $want "*) ;;
        *) warn "unknown glass style '$want' — using frosted"; want=frosted ;;
    esac
    if [ -z "${LIQUID_WINDOWS_EXPLICIT:-}" ] || [ -z "$windows" ]; then
        windows="${previous_windows:-0}"
    fi
    [ "$windows" = 1 ] || windows=0

    # Performance has no blur for a style to shape. The choice is still
    # remembered, so it is there when frosted comes back.
    if [ "${WANT_BLUR:-1}" != 1 ]; then
        if remembering; then
            mkdir -p "$CONF_DIR"
            [ -n "${GLASS_STYLE_EXPLICIT:-}" ] && printf '%s\n' "$want" > "$memo"
            [ -n "${LIQUID_WINDOWS_EXPLICIT:-}" ] && printf '%s\n' "$windows" > "$windows_memo"
        fi
        skip "glass style left alone (no blur to shape)"
        return 0
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: glass style $want on the top bar and the dock (app windows: $windows)"
        return 0
    fi

    # An array: `lock screen` has a space in its name.
    local names=(panel dock)
    # The others drop the dock: on its dynamic blur the effect would never run.
    [ "$want" = liquid ] || names=(panel "lock screen")
    glass_style_takes_windows "$want" && [ "$windows" = 1 ] && names+=(windows)

    # Read where install.sh resolves it (flag, memo, default), so a run that
    # changes the accent tints with the new one. aura-glass-preview has no
    # ACCENT of its own and lands on the memo.
    local accent="${ACCENT:-$(cat "$CONF_DIR/accent" 2>/dev/null || true)}"
    ACCENT_HEX="$(accent_hex "${accent:-${ACCENT_DEFAULT:-purple}}")" \
    python3 - "$want" "${names[@]}" <<'STYLE_PY' || { warn "could not set the glass style"; return 0; }
import os
import re
import subprocess
import sys

want, names = sys.argv[1], sys.argv[2:]
KEY = "/org/gnome/shell/extensions/blur-my-shell/pipelines"
PREFIX = "effect_aura_glass_style_"
cur = subprocess.run(["dconf", "read", KEY],
                     capture_output=True, text=True).stdout.strip()
if not cur:
    sys.exit(0)

# Every effect's params are a flat dict, so [^{}]* cannot run past its end.
OURS = re.compile(r"(, )?<\{'type': <'[a-z_]+'>, 'id': <'%s[a-z_]+'>, "
                  r"'params': <\{[^{}]*\}>\}>(, )?" % PREFIX)


def strip(match):
    # Keep one separator when the effect sat between two others.
    return ", " if match.group(1) and match.group(2) else ""


new = OURS.sub(strip, cur)

# The refraction effect's look is Blur My Shell's own default (strength 0.42,
# bezel 22, falloff 2.4, rim 4.8, gloss 0.55, shadow 0.28). The three
# values that differ only remove cost or a second copy of something:
#   blur_radius 0     the native blur before it has already blurred. Its own
#                     blur would be a second gaussian, run once per pass.
#   rgb_fringing 0    one backdrop read per pixel instead of three. The
#                     colour split also read as a defect on white text.
#   tint 0            the tint is css/'s job (--shell-tint-color). A second
#                     one here would ignore that choice.
LIQUID = ("'strength': <0.42>, 'blur_radius': <0.0>, 'edge_size': <22.0>, "
          "'falloff': <2.4>, 'corner_radius': <%s>, 'rim_width': <4.8>, "
          "'rgb_fringing': <0.0>, 'gloss': <0.55>, 'tint': <0.0>, "
          "'shadow': <0.28>")
BLUR = re.compile(r"<\{'type': <'native_static_gaussian_blur'>, 'id': <'[^']*'>, "
                  r"'params': <\{[^{}]*\}>\}>")
CORNER = re.compile(r"'type': <'corner'>, 'id': <'[^']*'>, "
                    r"'params': <\{'radius': <([0-9.]+)>")


def effects_span(blob, name):
    """Start and end of the named pipeline's effect list, brackets excluded."""
    head = "'name': <'%s'>, 'effects': <[" % name
    start = blob.find(head)
    if start < 0:
        return None
    start += len(head)
    depth, i, quoted = 1, start, False
    while i < len(blob):
        c = blob[i]
        if c == "'":
            quoted = not quoted
        elif not quoted and c == "[":
            depth += 1
        elif not quoted and c == "]":
            depth -= 1
            if depth == 0:
                return start, i
        i += 1
    return None


if want == "liquid":
    for name in names:
        span = effects_span(new, name)
        if span is None:
            print("no `%s` pipeline in %s — it stays frosted" % (name, KEY),
                  file=sys.stderr)
            continue
        effects = new[span[0]:span[1]]
        blur = BLUR.search(effects)
        corner = CORNER.search(effects)
        if blur is None:
            print("the `%s` pipeline has no static blur — it stays frosted"
                  % name, file=sys.stderr)
            continue
        radius = float(corner.group(1)) if corner else 0.0
        effect = ("<{'type': <'refraction'>, 'id': <'%srefraction_%s'>, "
                  "'params': <{%s}>}>" % (PREFIX, name, LIQUID % repr(radius)))
        at = span[0] + blur.end()
        new = new[:at] + ", " + effect + new[at:]

# The luminosity effect converts to HSV and back in its own pass, so it needs
# no rgb_to_hsl / hsl_to_rgb pair around it: one shader, one texture read per
# pixel, run once per static blur.
#   saturation_multiplicator 1.35   in tools/preview.sh on the default
#        wallpaper the frosted top bar averages HSV saturation 0.76, so 1.35
#        already reaches the clamp at 1. 1.6 rendered pixel for pixel the
#        same there, and would only push a muted wallpaper further: at 1.35
#        a greyish 0.3 becomes 0.4, a colour cast rather than a poster.
#   brightness_multiplicator 1.06   a small lift, so the colour reads as light
#        coming through rather than paint on top. In the preview the bar's
#        mean HSV value went from 0.33 to 0.38 and the white clock and icons
#        stayed as legible as on frosted.
#        The lock screen pipeline gets 1.0: its blur is darkened to 0.8 on
#        purpose so the clock reads, and vibrancy should not undo that. The
#        windows pipeline gets 1.0 too: its brightness is the user's own
#        --window-brightness, and a lift here would quietly move it.
VIBRANT = ("'brightness_shift': <0.0>, 'brightness_multiplicator': <%s>, "
           "'contrast': <1.0>, 'contrast_center': <0.5>, "
           "'saturation_multiplicator': <1.35>")

#   tinted: Blur My Shell's color effect, blend_mode 16 (Color). Color keeps
#        the backdrop's own brightness and takes only hue and saturation from
#        the accent, so a tinted bar is exactly as light or dark as the frosted
#        one and white text keeps the contrast the shell tint gave it. Soft
#        light (11) was the other candidate; on a dark blur it mostly darkens
#        two channels, which reads as a dimmer bar more than a coloured one.
#        Alpha 0.3 is the blend amount (color.glsl mixes by it): enough for
#        the accent to name the glass, while 70% of the wallpaper's own hue
#        still shows through, so it stays glass rather than paint.
TINTED = ("'color': <(%s, %s, %s, 0.3)>, 'blend_mode': <16>")
#   smoked: the luminosity effect turned the other way.
#        brightness_multiplicator 0.7   caps the brightest wallpaper patch
#            behind the bar at 70% value, so white text keeps at least the
#            contrast it has against a mid-grey; a bright cloud no longer
#            washes the clock out.
#        saturation_multiplicator 0.8   smoked glass is grey glass: a fifth
#            of the colour drained, the wallpaper still recognisable.
#        contrast 1.0   left alone on purpose. Raising it pivots on 0.5, so
#            it would push bright patches up again, the opposite of what
#            this style is for.
SMOKED = ("'brightness_shift': <0.0>, 'brightness_multiplicator': <0.7>, "
          "'contrast': <1.0>, 'contrast_center': <0.5>, "
          "'saturation_multiplicator': <0.8>")


def style_effect(name):
    """This style's effect for the named pipeline, or None for liquid/frosted."""
    if want == "vibrant":
        lift = "1.0" if name in ("lock screen", "windows") else "1.06"
        kind, params = "luminosity", VIBRANT % lift
    elif want == "smoked":
        kind, params = "luminosity", SMOKED
    elif want == "tinted":
        hexa = os.environ.get("ACCENT_HEX", "9141ac")
        rgb = [round(int(hexa[i:i + 2], 16) / 255.0, 4) for i in (0, 2, 4)]
        kind, params = "color", TINTED % tuple(repr(c) for c in rgb)
    else:
        return None
    return ("<{'type': <'%s'>, 'id': <'%s%s_%s'>, 'params': <{%s}>}>"
            % (kind, PREFIX, want, name.replace(" ", "_"), params))


for name in names if want in ("vibrant", "tinted", "smoked") else []:
    span = effects_span(new, name)
    if span is None:
        print("no `%s` pipeline in %s — it stays frosted" % (name, KEY),
              file=sys.stderr)
        continue
    effects = new[span[0]:span[1]]
    blur = BLUR.search(effects)
    if blur is None:
        print("the `%s` pipeline has no static blur — it stays frosted"
              % name, file=sys.stderr)
        continue
    effect = style_effect(name)
    # Never after a corner effect. The luminosity shader divides hue and
    # saturation, not only the value, by alpha, so on the corner's
    # anti-aliased edge it turns the hue: a magenta rim round the whole top
    # bar in the preview, whose pipeline cuts its corner before the blur.
    # Before that corner the texture is opaque everywhere and the effect
    # still reaches the blur, just ahead of it rather than behind. The color
    # effect does not divide, but goes in the same place so every style
    # shapes the same pixels.
    corner = CORNER.search(effects)
    if corner is not None and corner.start() < blur.start():
        at = span[0] + effects.rfind("<{", 0, corner.start())
        new = new[:at] + effect + ", " + new[at:]
    else:
        at = span[0] + blur.end()
        new = new[:at] + ", " + effect + new[at:]

# Compared as numbers: see the note in apply_pipeline_radius.
_num = re.compile(r"-?\d+\.\d+(?:e[-+]?\d+)?")
if (_num.sub(lambda m: repr(float(m.group())), new)
        != _num.sub(lambda m: repr(float(m.group())), cur)):
    subprocess.run(["dconf", "write", KEY, new], check=True)
STYLE_PY

    # The effects only run on static blur (see above). Leaving liquid puts
    # back the preset's value, but only for a surface liquid had switched: a
    # dock a user made static on their own stays static. Vibrant keeps the
    # dock dynamic, so it counts as leaving liquid here.
    if [ "$want" = liquid ]; then
        run dconf write "$base/dash-to-dock/static-blur" true
    elif [ "$previous" = liquid ]; then
        restore_static_blur dash-to-dock
    fi
    if glass_style_takes_windows "$want" && [ "$windows" = 1 ]; then
        run dconf write "$base/applications/static-blur" true
    elif glass_style_takes_windows "$previous" && [ "$previous_windows" = 1 ]; then
        restore_static_blur applications
    fi

    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
        printf '%s\n' "$windows" > "$windows_memo"
    fi
    if [ "$want" = liquid ] && [ "$windows" = 1 ]; then
        ok "liquid glass on the top bar, the dock and app windows (remembered for later runs)"
    elif [ "$want" = liquid ]; then
        ok "liquid glass on the top bar and the dock (remembered for later runs)"
    elif [ "$want" = vibrant ] && [ "$windows" = 1 ]; then
        ok "vibrant glass on the top bar, the overview and app windows (remembered for later runs)"
    elif [ "$want" = vibrant ]; then
        ok "vibrant glass on the top bar and the overview (remembered for later runs)"
    elif [ "$want" = tinted ]; then
        ok "glass tinted toward the ${accent:-${ACCENT_DEFAULT:-purple}} accent on the top bar and the overview (remembered for later runs)"
    elif [ "$want" = smoked ]; then
        ok "smoked glass on the top bar and the overview (remembered for later runs)"
    else
        ok "frosted glass on the top bar and the dock"
    fi
}

# [applications] opacity controls the compositor-level window actor opacity for
# windows on top of the blur effect. For GTK4 apps, the stylesheet handles inner
# translucency; for Electron/IDE/browser apps, this actor opacity allows the blur
# to show through the window content.
apply_app_opacity() {
    local base=/org/gnome/shell/extensions/blur-my-shell
    local opacity="${APP_OPACITY:-255}" memo="$CONF_DIR/app-opacity"

    if [ "${WANT_BLUR:-1}" != 1 ] || [ "${WANT_WINDOW_BLUR:-1}" != 1 ]; then
        if [ "${GLASS_MODE:-}" = performance ] && [ -n "${APP_OPACITY:-}" ]; then
            if remembering; then
                mkdir -p "$CONF_DIR"
                printf '%s\n' "$opacity" > "$memo"
            fi
        fi
        run dconf write "$base/applications/opacity" 255
        return 0
    fi

    if [ -z "${APP_OPACITY_EXPLICIT:-}" ] && [ -r "$memo" ]; then
        opacity="$(cat "$memo" 2>/dev/null || true)"
        opacity="${opacity:-255}"
    fi

    if remembering; then
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

# Whether a fullscreen window keeps its blur. Off by default: see
# unblur-when-fullscreen in dconf/core.ini for why. Written on every run, not
# only by core.ini, because load_dconf skips core.ini on an existing install
# and a remembered --fullscreen-blur has to survive a flagless re-run.
apply_fullscreen_blur() {
    local base=/org/gnome/shell/extensions/blur-my-shell
    local want="${FULLSCREEN_BLUR:-}" memo="$CONF_DIR/fullscreen-blur"

    if [ -z "${FULLSCREEN_BLUR_EXPLICIT:-}" ] || [ -z "$want" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ "$want" = 1 ] || want=0

    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi

    if [ "$want" = 1 ]; then
        run dconf write "$base/applications/unblur-when-fullscreen" false
        ok "fullscreen windows keep their blur (remembered for later runs)"
    else
        run dconf write "$base/applications/unblur-when-fullscreen" true
        ok "fullscreen windows drop their blur and go opaque"
    fi
}

# Frosted repaints the whole stage every frame: Blur My Shell's hacks-level at
# core.ini's value (2). See hacks-level there for why lower levels were tried and
# dropped. Written on every frosted run, not only on the way in from another
# mode, because a short-lived --blur-refresh (2026-10-22) left installs at 0 and
# load_dconf skips core.ini on an existing install. Its memo goes with it.
# Performance and the adaptive overlay keep solid.ini's 0, so nothing is written
# while blur is off. run skips the write when the level is already in place,
# which matters: every change of level restarts Blur My Shell.
pin_frosted_hacks_level() {
    if remembering; then rm -f "$CONF_DIR/blur-refresh"; fi
    [ "${WANT_BLUR:-1}" = 1 ] || return 0
    local key value
    while IFS="$(printf '\t')" read -r key value; do
        [ "$key" = blur-my-shell/hacks-level ] || continue
        run dconf write "/org/gnome/shell/extensions/$key" "$value"
    done < <(mode_owned_dconf_keys 1)
}

# The popup keys themselves ship in dconf/core.ini so the whole preset stays
# readable in one file. Two things cannot live there:
#
# The on/off choice, because dconf load rewrites the section on every run — a
# flagless re-install would quietly turn popup blur back on over a deliberate
# --no-popup-blur. Same reason --grain and --icons are remembered.
#
# static-blur is kept false: popup and Quick Settings blur is dynamic,
# sampling whatever is behind the menu in real time. Corner rounding is handled
# natively when gnome-rounded-blur is available, or via Blur My Shell's corner
# shader fallback.
# Which windows the applications component treats, as wm_class patterns.
#
# Blur My Shell compiles these and matches a window's wm_class against them
# (components/applications.js, matchesAnyPattern), so `*chrome*` covers every
# spelling Chrome uses. Which list is consulted depends on enable-all: with it
# off only the allow list is blurred, with it on everything except the block
# list is. That is the same choice --app-blur-scope makes, which is why gtk mode
# reads one list and all mode reads the other.
#
# The same test decides the actor opacity in apply_app_opacity — Blur My Shell
# applies both to whatever passes it — so these lists govern which windows go
# translucent as much as which ones get a blur. There is no way to separate the
# two, and no per-app control over the stylesheet's own alpha at all: GTK CSS
# has no selector for "this application".
#
# Shipped as defaults rather than written into dconf/core.ini, because a user's
# edited list has to survive the next install and dconf load rewrites whole
# sections. $CONF_DIR/app-blur-allow and app-blur-block hold the edited copies,
# one pattern per line, and are what the settings window writes.
APP_BLUR_ALLOW_DEFAULT=(
    org.gnome.Nautilus org.gnome.Settings gnome-control-center
    org.gnome.TextEditor org.gnome.SystemMonitor org.gnome.Calculator
    org.gnome.Extensions org.gnome.Tweaks org.gnome.Ptyxis org.gnome.Console
    gnome-terminal org.gnome.DiskUtility org.gnome.Logs org.gnome.Calendar
    org.gnome.Weather org.gnome.Clocks org.gnome.Characters
    org.gnome.FontViewer org.gnome.Loupe org.gnome.Snapshot
    io.bassi.Amberol com.raggesilver.BlackBox
)

# Only consulted in `all` mode. The wildcards are the expensive-to-blur or
# self-compositing apps: browsers and Electron redraw constantly, so a blur
# behind them is rebuilt constantly, and Plank and ding draw their own desktop
# surfaces that a blur actor sits wrongly against.
APP_BLUR_BLOCK_DEFAULT=(
    '*chrome*' '*google-chrome*' '*chromium*' '*discord*' '*vesktop*'
    '*brave*' '*firefox*' '*code*' '*antigravity*' '*steam*' '*spotify*'
    '*electron*' Plank com.desktop.ding Conky
)

# The settings window's own wm_class, which is blurred whenever anything is.
#
# Written out here rather than read from $GUI_APP_ID in lib/steps-gui.sh: that
# file is sourced after this one and the two are separate concerns, so the string
# is duplicated and tools/check-app-blur-lists.sh asserts the two copies agree.
# gui/aura_glass_settings.py holds a third, for the same reason and with the same
# check behind it.
APP_BLUR_SELF="io.github.DevWebeloper.AuraGlassSettings"

# Does one pattern cover the settings window?
#
# wildcardToRegex in the extension's components/applications.js anchors a pattern
# at both ends, turns * into .* and ? into ., and compiles case-insensitively —
# which is what a bash glob under nocasematch does. The one difference is [abc]:
# the extension escapes the brackets and matches them literally. No wm_class has
# brackets in it, and this one certainly does not.
app_blur_covers_self() {
    local pattern="$1" matched=0 restore
    restore="$(shopt -p nocasematch)"
    shopt -s nocasematch
    case "$APP_BLUR_SELF" in
        $pattern) matched=1 ;;
    esac
    eval "$restore"
    [ "$matched" = 1 ]
}

# Lines on stdin -> the same lines with the settings window on them.
#
# The window is the one place the glass is explained, so it is the one window
# that must never be the exception to it: unblurred, it shows an opaque grey
# panel while describing the blur, and the per-app lists it opens are drawn in
# a window that proves the setting does not work. Nothing else here is pinned,
# and this is not a general mechanism — it is one class, named once.
#
# Pinned rather than added to APP_BLUR_ALLOW_DEFAULT, because a default is only
# consulted when there is no memo, and every machine that has run an earlier
# release has one. Skipped when a pattern already covers it, so a user who wrote
# their own wildcard for it does not get a duplicate underneath.
app_blur_pin_allow() {
    local lines pattern
    lines="$(cat)"
    while IFS= read -r pattern; do
        [ -n "${pattern// /}" ] || continue
        if app_blur_covers_self "$pattern"; then
            printf '%s\n' "$lines"
            return 0
        fi
    done <<< "$lines"
    printf '%s\n%s\n' "$APP_BLUR_SELF" "$lines"
}

# Lines on stdin -> the same lines, minus anything that would block the window.
#
# The other half of the pin. In `all` mode the allow list is not read at all, so
# keeping the window blurred there means dropping whatever excludes it — and the
# shipped block list does not name it, but `*aura*` from a user who wanted their
# own theme's windows left alone would.
app_blur_pin_block() {
    local pattern
    while IFS= read -r pattern; do
        [ -n "${pattern// /}" ] || continue
        app_blur_covers_self "$pattern" && continue
        printf '%s\n' "$pattern"
    done
}

# The list to use, one pattern per line: an explicit flag wins, else the user's
# memo, else the shipped default. Same precedence as every other remembered
# choice here, so a flag is a one-run override that then becomes the memory.
app_blur_lines() {
    local given="$1" override="$2" memo="$3"; shift 3
    # `given` rather than a non-empty override, because clearing a list is a
    # thing a user does: --app-blur-allow "" and the settings window removing the
    # last row both mean an empty list, and testing the value alone read that as
    # "no flag" and quietly reinstated the previous one.
    if [ -n "$given" ]; then
        printf '%s\n' "$override" | tr ',' '\n'
    elif [ -r "$memo" ]; then
        cat "$memo"
    else
        printf '%s\n' "$@"
    fi
}

# Lines on stdin -> a GVariant array literal for dconf write.
#
# By the time the settings window has been near it a pattern is arbitrary text,
# and it is about to be spliced into a literal that dconf parses. Two characters
# matter: an apostrophe ends the string early, which dconf rejects outright, and
# a backslash escapes whatever follows it, which dconf accepts as a different
# string than the one meant — 'weird\name' arrives carrying a newline. The first
# is a failed install with a message about GVariant syntax; the second is an
# entry that silently never matches.
#
# Escaped explicitly rather than by leaning on python's repr. repr does in fact
# produce valid GVariant for every pattern anyone would type — it quotes and
# escapes compatibly — but it is a function whose contract is "readable python",
# and relying on the two staying in agreement is a bet with no upside.
# tools/check-app-blur-lists.sh parses the result back with GLib's own parser.
app_blur_literal() {
    python3 -c '
import sys


def gvariant(s):
    return "\x27" + s.replace("\\", "\\\\").replace("\x27", "\\\x27") + "\x27"


lines = [l.strip() for l in sys.stdin]
print("[%s]" % ", ".join(gvariant(l) for l in lines if l))'
}

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
    local scope="${APP_BLUR_SCOPE:-all}" scope_memo="$CONF_DIR/app-blur-scope"
    local allow_memo="$CONF_DIR/app-blur-allow" block_memo="$CONF_DIR/app-blur-block"

    if [ "${WANT_BLUR:-1}" != 1 ]; then
        run dconf write "$base/applications/blur" false
        skip "window blur off with the rest of it (--no-blur)"
        return 0
    fi

    if [ -z "${WINDOW_BLUR_EXPLICIT:-}" ] && [ -r "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
        want="${want:-1}"
    fi

    if [ -z "${APP_BLUR_SCOPE_EXPLICIT:-}" ] && [ -r "$scope_memo" ]; then
        scope="$(cat "$scope_memo" 2>/dev/null || true)"
        scope="${scope:-all}"
    fi

    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
        printf '%s\n' "$scope" > "$scope_memo"
    fi

    if [ "$want" != 1 ]; then
        run dconf write "$base/applications/blur" false
        skip "window blur off — pass --window-blur if you want it"
        return 0
    fi

    # Both lists are written in both modes. Only one is consulted — enable-all
    # decides which — but leaving the other at whatever a previous run or a
    # previous version put there means switching modes later picks up a stale
    # list, which reads as the mode switch having done something else as well.
    local allow_lines block_lines allow block
    allow_lines="$(app_blur_lines "${APP_BLUR_ALLOW_EXPLICIT:-}" "${APP_BLUR_ALLOW:-}" "$allow_memo" "${APP_BLUR_ALLOW_DEFAULT[@]}")"
    block_lines="$(app_blur_lines "${APP_BLUR_BLOCK_EXPLICIT:-}" "${APP_BLUR_BLOCK:-}" "$block_memo" "${APP_BLUR_BLOCK_DEFAULT[@]}")"

    # After the flag/memo/default choice and before anything is written, so the
    # memo the settings window reads back is the list that reached dconf. An
    # empty allow list is still emptied by --app-blur-allow "" — it comes out of
    # this holding the settings window and nothing else, which is a list with
    # nothing of the user's on it rather than a list that ignored them.
    allow_lines="$(printf '%s\n' "$allow_lines" | app_blur_pin_allow)"
    block_lines="$(printf '%s\n' "$block_lines" | app_blur_pin_block)"

    allow="$(printf '%s\n' "$allow_lines" | app_blur_literal)"
    block="$(printf '%s\n' "$block_lines" | app_blur_literal)"

    # Written back every real run, not only when a flag supplied them, so the
    # memo is always what is installed. The settings window reads these files to
    # show the lists, and a missing memo would have it show an empty list for a
    # dconf key that is not empty at all. A preview is not a real run and writes
    # neither — see remembering() in lib/common.sh.
    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$allow_lines" > "$allow_memo"
        printf '%s\n' "$block_lines" > "$block_memo"
    fi

    run dconf write "$base/applications/whitelist" "$allow"
    run dconf write "$base/applications/blacklist" "$block"

    if [ "$scope" = "all" ]; then
        run dconf write "$base/applications/enable-all" true
        run dconf write "$base/applications/blur" true
        ok "window blur on for ALL applications except the block list (enable-all: true)"
    else
        run dconf write "$base/applications/enable-all" false
        run dconf write "$base/applications/blur" true
        ok "window blur on behind the allowed applications only (Nautilus, Settings, Terminal, etc.)"
    fi
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
    # on the second run contradicted it. So performance neither reads nor writes
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

    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi

    if [ "$want" != 1 ]; then
        run dconf write "$base/popup/blur" false
        skip "popup blur off — menus keep the flat translucent look"
        return 0
    fi

    run dconf write "$base/popup/blur" true
    run dconf write "$base/popup/static-blur" false
    ok "popup blur on, dynamic — sampling live surface behind popups"
}

# Notification banners and the history cards in the date menu, gated by the
# patched popup component's own `notification` key — independent of
# popup/blur, the same way this project's --popup-blur and
# --notification-blur flags are independent of each other. static-blur and
# rounded-blur-found stay apply_popup_blur's business: they are settings on
# the popup component as a whole, not on this surface alone, and the popup
# blur switch already decides them whenever it runs.
apply_notification_blur() {
    local base=/org/gnome/shell/extensions/blur-my-shell
    local want="${WANT_NOTIFICATION_BLUR:-1}" memo="$CONF_DIR/notification-blur"

    # Same reasoning as apply_popup_blur: --no-blur turns this off as a
    # consequence of turning everything off, not a real choice to remember,
    # so performance neither reads nor writes the memo.
    if [ "${WANT_BLUR:-1}" != 1 ]; then
        run dconf write "$base/popup/notification" false
        skip "notification blur off with the rest of it (--no-blur)"
        return 0
    fi

    if [ -z "${NOTIFICATION_BLUR_EXPLICIT:-}" ] && [ -r "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
        want="${want:-1}"
    fi

    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi

    if [ "$want" != 1 ]; then
        run dconf write "$base/popup/notification" false
        skip "notification blur off — banners and history cards keep the flat look"
        return 0
    fi

    run dconf write "$base/popup/notification" true
    ok "notification blur on — banners and history cards blur independently"
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
# Compared as numbers: see the note in apply_pipeline_radius.
_num = re.compile(r"-?\d+\.\d+(?:e[-+]?\d+)?")
if (_num.sub(lambda m: repr(float(m.group())), new)
        != _num.sub(lambda m: repr(float(m.group())), cur)):
    subprocess.run(["dconf", "write", KEY, new], check=True)
PY
    run mkdir -p "$CONF_DIR"
    printf '%s\n' "$want" > "$memo"
    ok "blur grain set to $want (remembered for future installs)"
}

# How far the blur reaches, as a percentage of the tuned values.
#
# One number for every blurred surface rather than one per surface. The six
# sigmas in tokens/tokens.sh are not a ladder anybody should have to climb one
# rung at a time — they are already in proportion to each other, chosen against
# what each surface sits in front of, and what people actually want is the
# whole set softer or crisper. Scaling keeps those proportions: the panel stays
# heavier than the dock at every setting.
#
# Both places a blur radius lives are scaled, because Blur My Shell has two.
# The per-component `sigma` keys are what the older releases read. The
# `pipelines` blob is what the current ones read, and it carries the same
# number again as `unscaled_radius` inside each effect. A run that moved one
# and not the other would soften the desktop on one machine and do nothing on
# the next.
#
# Sigmas are written from the tokens rather than read back and multiplied, so
# the value cannot compound over repeated installs. The blob has to be read —
# there is no token for its seven copies — but dconf load has just rewritten it
# from dconf/core.ini a few lines above, which is the same assumption apply_grain
# already makes.
#
# Remembered, like the grain beside it: dconf load puts the shipped sigmas back
# on every run, so an unremembered choice would last until the next install.
# How bright the blur behind menus, Quick Settings and notification banners
# comes out, as a percentage of the backdrop it is blurring. 100% is the
# backdrop's own brightness; under that the blur darkens what is behind it, over
# it the blur lifts it.
#
# One number for every popup surface, and it has to be, because Blur My Shell
# gives the whole popup component one pipeline — settings.popup.PIPELINE in
# components/popup/static_actor.js is read once and handed to every surface the
# component makes. A banner cannot be brightened without the date menu and the
# quick-toggle menus coming with it, and a control that implied otherwise would
# be lying about what it moves.
#
# Both places the number lives are written, for the same reason
# apply_blur_strength writes two: the per-component `brightness` key is what the
# older releases read, and the `pipelines` blob is what the current ones read.
# The pipeline is found by the name the popup component actually points at
# rather than by a hard-coded id, so renaming or repointing it in dconf/core.ini
# does not silently turn this into a no-op.
#
# Runs after apply_blur_strength, which rewrites the same blob. That one only
# touches `unscaled_radius` and this one only touches `brightness`, so the order
# between them is not load-bearing — but keeping them adjacent is, because
# anything that resets the blob wholesale has to come before both.
#
# Remembered, like the strength above it: dconf load puts the shipped brightness
# back on every run.
POPUP_BRIGHTNESS_MIN=50
POPUP_BRIGHTNESS_MAX=150

apply_popup_brightness() {
    local want="${POPUP_BRIGHTNESS:-}" memo="$CONF_DIR/popup-brightness"
    if [ -z "$want" ] && [ -f "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ -n "$want" ] || return 0

    case "$want" in
        ''|*[!0-9]*) warn "--popup-brightness wants a whole percentage, got '$want'"
                     return 0 ;;
    esac
    if [ "$want" -lt "$POPUP_BRIGHTNESS_MIN" ] || [ "$want" -gt "$POPUP_BRIGHTNESS_MAX" ]; then
        warn "--popup-brightness $want is outside ${POPUP_BRIGHTNESS_MIN}-${POPUP_BRIGHTNESS_MAX} — leaving the popup blur alone"
        return 0
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: light the popup blur at ${want}%"
        return 0
    fi

    local base=/org/gnome/shell/extensions/blur-my-shell
    run dconf write "$base/popup/brightness" \
        "$(awk -v p="$want" 'BEGIN { printf "%.2f", p / 100 }')"

    python3 "$REPO_ROOT/tools/apply-popup-brightness.py" "$want" \
        || { warn "could not light the popup blur"; return 0; }

    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi
    ok "popup blur lit at ${want}% (remembered for later runs)"
}

WINDOW_BRIGHTNESS_MIN=50
WINDOW_BRIGHTNESS_MAX=150

apply_window_brightness() {
    local want="${WINDOW_BRIGHTNESS:-}" memo="$CONF_DIR/window-brightness"
    if [ -z "$want" ] && [ -f "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ -n "$want" ] || return 0

    case "$want" in
        ''|*[!0-9]*) warn "--window-brightness wants a whole percentage, got '$want'"
                     return 0 ;;
    esac
    if [ "$want" -lt "$WINDOW_BRIGHTNESS_MIN" ] || [ "$want" -gt "$WINDOW_BRIGHTNESS_MAX" ]; then
        warn "--window-brightness $want is outside ${WINDOW_BRIGHTNESS_MIN}-${WINDOW_BRIGHTNESS_MAX} — leaving the window blur alone"
        return 0
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: light the window blur at ${want}%"
        return 0
    fi

    local base=/org/gnome/shell/extensions/blur-my-shell
    run dconf write "$base/applications/brightness" \
        "$(awk -v p="$want" 'BEGIN { printf "%.2f", p / 100 }')"

    python3 - "$want" <<'PY' || { warn "could not light the window blur"; return 0; }
import re, subprocess, sys
want = int(sys.argv[1]) / 100.0
BASE = "/org/gnome/shell/extensions/blur-my-shell"
pipe_name = subprocess.run(["dconf", "read", BASE + "/applications/pipeline"],
                           capture_output=True, text=True).stdout.strip().strip("'")
blob = subprocess.run(["dconf", "read", BASE + "/pipelines"],
                      capture_output=True, text=True).stdout.strip()
if pipe_name and blob and pipe_name in blob:
    start = blob.index(pipe_name)
    nxt = blob.find("'pipeline_", start + len(pipe_name))
    end = nxt if nxt != -1 else len(blob)
    sliced = re.sub(r"('brightness': <)([0-9.]+)(>)",
                    lambda m: "%s%s%s" % (m.group(1), repr(want), m.group(3)),
                    blob[start:end])
    new = blob[:start] + sliced + blob[end:]
    # Compared as numbers: see the note in apply_pipeline_radius.
    _num = re.compile(r"-?\d+\.\d+(?:e[-+]?\d+)?")
    if (_num.sub(lambda m: repr(float(m.group())), new)
            != _num.sub(lambda m: repr(float(m.group())), blob)):
        subprocess.run(["dconf", "write", BASE + "/pipelines", new], check=True)
PY

    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi
    ok "window blur lit at ${want}% (remembered for later runs)"
}

BLUR_STRENGTH_MIN=25
BLUR_STRENGTH_MAX=200

# This is the one blur-strength resolver for both the normal writer and the
# adaptive transition.  Normal installation leaves an unchosen value empty so
# dconf/core.ini keeps its tuned 100%; the adaptive caller supplies that 100%
# fallback because it has to calculate an actual temporary value from it.
resolve_blur_strength() {
    local fallback="${1-}" want="${BLUR_STRENGTH:-}" memo="$CONF_DIR/blur-strength"
    if [ -z "$want" ] && [ -f "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    printf '%s\n' "${want:-$fallback}"
}

apply_blur_strength() {
    local want memo="$CONF_DIR/blur-strength"
    # --no-blur leaves the rest of the theme intact but deliberately omits
    # Blur My Shell.  A normal call keeps its established behaviour; only the
    # private transient path has to stand down here, before it can recreate or
    # write any of that extension's dconf keys.
    if [ -n "${ADAPTIVE_BLUR:-}" ] && [ "${WANT_BLUR:-1}" != 1 ]; then
        skip "no blur — no transient Blur My Shell strength to apply"
        return 0
    fi
    want="$(resolve_blur_strength)"
    [ -n "$want" ] || return 0

    case "$want" in
        ''|*[!0-9]*) warn "--blur-strength wants a whole percentage, got '$want'"
                     return 0 ;;
    esac
    if [ "$want" -lt "$BLUR_STRENGTH_MIN" ] || [ "$want" -gt "$BLUR_STRENGTH_MAX" ]; then
        warn "--blur-strength $want is outside ${BLUR_STRENGTH_MIN}-${BLUR_STRENGTH_MAX} — leaving the blur alone"
        return 0
    fi

    # Ordinary 100% follows dconf/core.ini already, so it need not rewrite six
    # keys.  A transient restore is different: it follows an earlier adaptive
    # downshift, and has to put those keys back to 100 without changing the
    # user's blur-strength memo.
    if [ "$want" = 100 ] && [ -z "${ADAPTIVE_BLUR:-}" ]; then
        if remembering; then
            mkdir -p "$CONF_DIR"
            printf '%s\n' "$want" > "$memo"
        fi
    fi

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: scale every blur radius to ${want}%"
        return 0
    fi

    local base=/org/gnome/shell/extensions/blur-my-shell
    local pair name token scaled
    for pair in "panel:$TOKEN_SIGMA_PANEL" "appfolder:$TOKEN_SIGMA_APPFOLDER" \
                "popup:$TOKEN_SIGMA_POPUP" "window-list:$TOKEN_SIGMA_WINDOW_LIST" \
                "applications:$TOKEN_SIGMA_APPLICATIONS" \
                "dash-to-dock:$TOKEN_SIGMA_DASH_TO_DOCK"; do
        name="${pair%%:*}"; token="${pair##*:}"
        # Rounded, floored at 1. A sigma of 0 is not a fainter blur, it is the
        # effect switched off, and the switches on the Glass page are where
        # that answer lives.
        scaled=$(( (token * want + 50) / 100 ))
        [ "$scaled" -lt 1 ] && scaled=1
        run dconf write "$base/$name/sigma" "$scaled"
    done

python3 - "$want" "$REPO_ROOT" <<'PY' || { warn "could not scale the blur pipelines"; return 0; }
import os
import re
import subprocess
import sys

want_ratio = int(sys.argv[1]) / 100.0
root = sys.argv[2]
KEY = "/org/gnome/shell/extensions/blur-my-shell/pipelines"

# Read baseline radii from core.ini so scaled values are anchored to the
# canonical preset rather than compounding over successive runs.
core_ini = os.path.join(root, "dconf", "core.ini")
base_blob = ""
if os.path.isfile(core_ini):
    with open(core_ini, "r", encoding="utf-8") as stream:
        for line in stream:
            if line.startswith("pipelines="):
                base_blob = line[len("pipelines="):].strip()
                break

pattern = r"(\{'type': <'native_static_gaussian_blur'>, 'id': <'([^']+)'>, 'params': <\{'unscaled_radius': <)([0-9.]+)(>)"
baseline_radii = {match[1]: float(match[2]) for match in re.findall(pattern, base_blob)}

cur = subprocess.run(["dconf", "read", KEY],
                     capture_output=True, text=True).stdout.strip()
if not cur:
    cur = base_blob
if not cur:
    sys.exit(0)


def scale(match):
    prefix = match.group(1)
    effect_id = match.group(2)
    suffix = match.group(4)
    raw = float(match.group(3))
    base_radius = baseline_radii.get(effect_id, raw)
    target_radius = max(1.0, round(base_radius * want_ratio, 1))
    return "%s%s%s" % (prefix, repr(target_radius), suffix)


new = re.sub(pattern, scale, cur)
# Compared as numbers: see the note in apply_pipeline_radius.
_num = re.compile(r"-?\d+\.\d+(?:e[-+]?\d+)?")
if (_num.sub(lambda m: repr(float(m.group())), new)
        != _num.sub(lambda m: repr(float(m.group())), cur)):
    subprocess.run(["dconf", "write", KEY, new], check=True)
PY

    if [ "$want" = 100 ] && [ -z "${ADAPTIVE_BLUR:-}" ]; then
        ok "blur strength at 100% — the tuned values"
    elif [ -z "${ADAPTIVE_BLUR:-}" ] && remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
        ok "blur strength at ${want}% of the tuned radii (remembered for later runs)"
    else
        ok "blur strength at ${want}% of the tuned radii (transient adaptive value)"
    fi
}

# The adaptive worker's transient overlay: "active" puts the desktop in
# Performance's state, "restore" puts it back to the remembered mode's.
#
# install.sh has already resolved this run as a retune to that mode (see the
# --adaptive-blur block there), so the WANT_*/APP_* values here are exactly the
# ones the app's Glass mode switch would resolve. This function therefore runs
# the same two steps the switch runs, load_dconf and install_css, instead of a
# hand-kept subset of them. The subset is what used to differ from the switch
# (KI-25): the tray sheet was the raw css/ copy rather than the rescaled,
# tinted, radius-matched one, the app tint sheet was dropped instead of
# rewritten, and hacks-level and the OSD alpha stayed on Frosted's values.
#
# What stays specific to a transient is the way back. The switch's own way
# back is the other mode's drawer, but an overlay changes no mode, so
# sync_mode_owned_keys sees "previous == target" on restore and writes nothing.
# The keys a mode owns are therefore saved on the way in and put back on the
# way out, which also keeps a per-component choice made inside Frosted (say,
# no lock screen blur) that a plain core.ini write-back would undo.
apply_adaptive_blur() {
    local action="$1"
    local base=/org/gnome/shell/extensions
    local state_dir="$CONF_DIR/adaptive-performance"
    local state_file="$state_dir/saved-mode-keys"
    # Written by an earlier release: blur-my-shell-relative "component/blur"
    # lines, no hacks-level and no OSD alpha. Read once on restore so an
    # overlay that was active across the update still ends cleanly.
    local legacy_file="$state_dir/saved-bms-blur"

    # The baseline is the remembered mode, not GLASS_MODE: for "active"
    # install.sh has just set that to performance so the run resolves like it.
    # Performance is the no-blur mode. Nothing records
    # a separate "blur" memo — reading one here meant the guard never fired, and
    # a restore in performance mode removed shell-80-solid.css and switched app
    # blur back on.
    local normal_mode=""
    if [ -r "$CONF_DIR/glass-mode" ]; then
        normal_mode="$(cat "$CONF_DIR/glass-mode" 2>/dev/null || true)"
    fi
    normal_mode="${normal_mode:-frosted}"
    case "$normal_mode" in
        performance)
            skip "baseline is already no-blur — skipping adaptive transition"
            return 0
            ;;
    esac

    local key value
    case "$action" in
        active)
            step "Applying adaptive performance no-blur state"
            if [ "${DRY_RUN:-0}" = 1 ]; then
                info "dry-run: put the desktop in Performance's state, transiently"
                return 0
            fi
            # Turning individual blur pipelines off stands every blur shader and
            # background down without unloading the extension, which on GNOME
            # Shell 51 is a fatal Mutter/Clutter actor-metadata segfault. Nothing
            # here, nor in load_dconf's sync_mode_owned_keys, disables it.
            mkdir -p "$state_dir"
            if [ ! -f "$state_file" ]; then
                # What is there now, else core.ini's value for it: a key the
                # user never moved has nothing to read back, and restore still
                # needs an answer for it.
                local core_values; core_values="$(mode_owned_dconf_keys 1)"
                local pending="$state_file.tmp"
                : > "$pending"
                while IFS=$'\t' read -r key _; do
                    [ -n "$key" ] || continue
                    value="$(dconf read "$base/$key" 2>/dev/null || true)"
                    if [ -z "$value" ]; then
                        value="$(printf '%s\n' "$core_values" | awk -F'\t' -v k="$key" '$1 == k { print $2; exit }')"
                    fi
                    [ -n "$value" ] && printf '%s\t%s\n' "$key" "$value" >> "$pending"
                done < <(mode_owned_dconf_keys 0)
                mv -f "$pending" "$state_file"
            fi
            load_dconf
            install_css
            ok "adaptive no-blur state active (transient)"
            ;;
        restore)
            step "Restoring normal blur configuration"
            if [ "${DRY_RUN:-0}" = 1 ]; then
                info "dry-run: put the desktop back in the remembered mode's state"
                return 0
            fi
            local bms_uuid="${BMS_UUID:-blur-my-shell@aunetx}"
            if [ -d "$EXT_DIR/$bms_uuid" ] || [ -d "/usr/share/gnome-shell/extensions/$bms_uuid" ]; then
                if ! (gnome-extensions list --enabled 2>/dev/null | grep -qxF "$bms_uuid"); then
                    dequeue_from_disabled_extensions "$bms_uuid" || true
                    if ! run gnome-extensions enable "$bms_uuid" 2>/dev/null; then
                        enqueue_extension "$bms_uuid" || true
                    fi
                fi
            fi
            if [ -f "$state_file" ]; then
                while IFS=$'\t' read -r key value || [ -n "$key" ]; do
                    [ -n "$key" ] || continue
                    run dconf write "$base/$key" "$value"
                done < "$state_file"
                run rm -f "$state_file"
            else
                # Never saved, or a restore that already ran: the preset's own
                # values for the keys a mode owns.
                while IFS=$'\t' read -r key value; do
                    [ -n "$key" ] || continue
                    run dconf write "$base/$key" "$value"
                done < <(mode_owned_dconf_keys 1)
            fi
            if [ -f "$legacy_file" ]; then
                while IFS='=' read -r key value || [ -n "$key" ]; do
                    [ -n "$key" ] || continue
                    run dconf write "$base/blur-my-shell/$key" "${value:-true}"
                done < "$legacy_file"
                run rm -f "$legacy_file"
            fi
            load_dconf
            install_css
            ok "normal blur configuration restored"
            ;;
        *)
            die "unknown adaptive-blur action '$action' — pick active or restore"
            ;;
    esac
}

# Which of the titlebar buttons a window gets. Two answers rather than the free
# string the key takes: close alone, or all three. The rest of what
# button-layout can express — reordering, moving them to the left, the spacer —
# is not a thing this theme has an opinion about, and a text field that let
# someone type a layout Mutter silently ignores would be worse than no control.
#
# Does nothing at all unless asked, like apply_grain and unlike the theme keys
# in apply_gsettings. This one is shared with GNOME Tweaks and with anyone who
# set it by hand years ago, so a flagless install has no business asserting a
# value over theirs.
apply_window_buttons() {
    local want="${WINDOW_BUTTONS:-}" memo="$CONF_DIR/window-buttons" layout
    if [ -z "$want" ] && [ -f "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ -n "$want" ] || return 0

    # appmenu is a dead token — the shell dropped the app menu in 3.32 — but it
    # is what the shipped default still says, so keeping it means the "all"
    # answer restores byte-for-byte what GNOME had before anyone touched this.
    case "$want" in
        close) layout="appmenu:close" ;;
        all)   layout="appmenu:minimize,maximize,close" ;;
        *)     warn "unknown window button layout '$want' — leaving it alone"
               return 0 ;;
    esac

    run gsettings set org.gnome.desktop.wm.preferences button-layout "$layout"
    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
    fi
}

# Same shape as apply_window_buttons and for the same reason: cursor-size is
# a GNOME preference shared with Tweaks, not this project's styling, so a
# flagless install leaves it exactly where it found it.
apply_cursor_size() {
    local want="${CURSOR_SIZE:-}" memo="$CONF_DIR/cursor-size"
    if [ -z "$want" ] && [ -f "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi
    [ -n "$want" ] || return 0

    case "$want" in
        ''|*[!0-9]*) warn "unknown cursor size '$want' — leaving it alone"
                     return 0 ;;
    esac

    run gsettings set org.gnome.desktop.interface cursor-size "$want"
    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$want" > "$memo"
        if [ -f "$HOME/.config/gtk-3.0/settings.ini" ]; then
            sed -i "/^gtk-cursor-theme-size=/d" "$HOME/.config/gtk-3.0/settings.ini"
            sed -i "/^\[Settings\]/a gtk-cursor-theme-size=$want" "$HOME/.config/gtk-3.0/settings.ini"
        fi
        if [ -f "$HOME/.config/gtk-4.0/settings.ini" ]; then
            sed -i "/^gtk-cursor-theme-size=/d" "$HOME/.config/gtk-4.0/settings.ini"
            sed -i "/^\[Settings\]/a gtk-cursor-theme-size=$want" "$HOME/.config/gtk-4.0/settings.ini"
        fi
    fi
}

apply_accent() {
    # Accent is intentionally separable from the full interface-theme write:
    # it is GNOME's preference and a narrow GUI edit must not reset appearance.
    run gsettings set org.gnome.desktop.interface accent-color "$ACCENT"
    disable_accent_overriders
    if remembering; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "$ACCENT" > "$CONF_DIR/accent"
    fi
}

moga_variant_for_accent() {
    case "${1:-blue}" in
        blue)   printf 'Blue\n' ;;
        teal)   printf 'Cyan\n' ;;
        green)  printf 'Green\n' ;;
        yellow) printf 'Yellow\n' ;;
        orange) printf 'Orange\n' ;;
        red)    printf 'Red\n' ;;
        pink)   printf 'Rose\n' ;;
        purple) printf 'Purple\n' ;;
        slate)  printf 'Sky\n' ;;
        *)      printf 'Blue\n' ;;
    esac
}

moga_cursor_theme() {
    local variant
    variant="$(moga_variant_for_accent "${ACCENT:-blue}")"
    printf 'Aura-Glass-Moga-%s\n' "$variant"
}

sync_cursor_theme_files() {
    local cursor="$1"
    [ -n "$cursor" ] || return 0
    [ "${DRY_RUN:-0}" = 1 ] && return 0

    if [ -d "$HOME/.local/share/icons/$cursor/cursors" ]; then
        ensure_scalable_cursors "$HOME/.local/share/icons/$cursor"
    fi

    mkdir -p "$HOME/.icons/default" "$HOME/.local/share/icons/default"
    printf '[Icon Theme]\nName=Default\nComment=Default Cursor Theme\nInherits=%s\n' "$cursor" > "$HOME/.icons/default/index.theme"
    printf '[Icon Theme]\nName=Default\nComment=Default Cursor Theme\nInherits=%s\n' "$cursor" > "$HOME/.local/share/icons/default/index.theme"

    # Expose custom cursor theme directories directly under ~/.icons for XWayland and legacy apps
    for c in "$HOME/.local/share/icons"/Aura-Glass-Moga-* "$HOME/.local/share/icons"/MacTahoe* "$HOME/.local/share/icons"/aosp*; do
        [ -d "$c" ] || continue
        ln -sfn "$c" "$HOME/.icons/$(basename "$c")"
    done

    if [ -f "$HOME/.config/gtk-3.0/settings.ini" ]; then
        sed -i "/^gtk-cursor-theme-name=/d" "$HOME/.config/gtk-3.0/settings.ini"
        sed -i "/^\[Settings\]/a gtk-cursor-theme-name=$cursor" "$HOME/.config/gtk-3.0/settings.ini"
    fi
    if [ -f "$HOME/.config/gtk-4.0/settings.ini" ]; then
        sed -i "/^gtk-cursor-theme-name=/d" "$HOME/.config/gtk-4.0/settings.ini"
        sed -i "/^\[Settings\]/a gtk-cursor-theme-name=$cursor" "$HOME/.config/gtk-4.0/settings.ini"
    fi
}

apply_cursor_theme() {
    local want="${CURSORS:-adwaita}" memo="$CONF_DIR/cursor-pack" cursor=""
    if [ -z "${CURSORS:-}" ] && [ -r "$memo" ]; then
        want="$(cat "$memo" 2>/dev/null || true)"
    fi

    if [ "${WANT_CURSORS:-1}" != 1 ] || [ "$want" = keep ]; then
        cursor=""
    elif [ "$want" = mactahoe ] \
       && { [ -d "$HOME/.local/share/icons/MacTahoe-dark" ] \
            || [ -d "/usr/share/icons/MacTahoe-dark" ]; }; then
        cursor='MacTahoe-dark'
    elif [ "$want" = aosp ] \
       && { [ -d "$HOME/.local/share/icons/aosp-cursors" ] \
            || [ -d "/usr/share/icons/aosp-cursors" ]; }; then
        cursor='aosp-cursors'
    elif [ "$want" = moga ]; then
        cursor="$(moga_cursor_theme)"
        if [ ! -d "$HOME/.local/share/icons/$cursor/cursors" ]; then
            install_moga_cursors
        fi
    elif [ "$want" = original ]; then
        local o; o="$(gsettings_original cursor-theme)"
        cursor="${o:-Adwaita}"
    elif [ -d "$HOME/.local/share/icons/$want" ] \
         || [ -d "/usr/share/icons/$want" ] \
         || [ -d "$HOME/.icons/$want" ]; then
        cursor="$want"
    else
        cursor='Adwaita'
    fi

    if [ -n "$cursor" ]; then
        if declare -f ensure_scalable_cursors >/dev/null 2>&1 \
           && [ -d "$HOME/.local/share/icons/$cursor" ] \
           && [ ! -d "$HOME/.local/share/icons/$cursor/cursors_scalable" ]; then
            ensure_scalable_cursors "$HOME/.local/share/icons/$cursor"
        fi
        run gsettings set org.gnome.desktop.interface cursor-theme "$cursor"
        sync_cursor_theme_files "$cursor"
        APPLIED_CURSOR="$cursor"
    else
        APPLIED_CURSOR=""
    fi
    apply_wiggly_cursor

    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        if [ "${WANT_CURSORS:-1}" = 1 ] && [ "$want" != keep ]; then
            printf '%s\n' "$want" > "$memo"
        else
            printf '%s\n' keep > "$memo"
        fi
    fi
}

# Wiggly draws its magnified pointer from one SVG. Pointed at the default.svg
# that ensure_scalable_cursors made for the active theme, the shaken cursor is
# the same pointer at a larger size instead of Wiggly's own black arrow. A theme
# with no SVG resets the key, so Wiggly falls back to its bundled icon rather
# than a file from the previous theme. Its tuning keys come from extras.ini on
# a fresh install; an update leaves dconf alone, so a key never set is filled
# here with the same value.
apply_wiggly_cursor() {
    [ "${DRY_RUN:-0}" = 1 ] && return 0
    case " ${EXT_EXTRA[*]:-} " in *" wiggly@mojarch "*) ;; *) return 0 ;; esac
    local base=/org/gnome/shell/extensions/wiggly
    local key val
    while IFS='=' read -r key val; do
        case "$key" in ''|'['*) continue ;; esac
        [ -n "$(dconf read "$base/$key" 2>/dev/null || true)" ] \
            || dconf write "$base/$key" "$val" 2>/dev/null || true
    done < <(sed -n '/^\[wiggly\]/,/^\[/p' "$REPO_ROOT/dconf/extras.ini")

    local theme svg="" d
    theme="$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")"
    for d in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons; do
        if [ -f "$d/$theme/cursors_scalable/default/default.svg" ]; then
            svg="$d/$theme/cursors_scalable/default/default.svg"
            break
        fi
    done
    if [ -n "$svg" ]; then
        # Only when it moved: an identical write still reaches Wiggly as a change.
        [ "$(dconf read "$base/cursor-path" 2>/dev/null || true)" = "'$svg'" ] \
            || dconf write "$base/cursor-path" "'$svg'" 2>/dev/null || true
    else
        dconf reset "$base/cursor-path" 2>/dev/null || true
    fi
}

apply_moga_cursor_theme() {
    CURSORS=moga apply_cursor_theme
}

apply_gsettings() {
    step "Setting themes and accent"

    # prefer-dark is set below, so pick the dark half of the pair here and save
    # the agent a visible swap a moment later.
    #
    # Nothing is resolved at all when the icons are being kept. --no-icons is a
    # promise not to touch the key, and the promise has to hold in this step
    # too: it used to write icon-theme whatever the flag said, so "Default"
    # installed no pack and then pointed the key at one anyway — and every
    # later run, flagless or from the window, put this theme's pack back over
    # whatever GNOME Tweaks or anything else had set since.
    local base icons=""
    if [ "${WANT_ICONS:-1}" = 1 ]; then
        base="$(icon_base)"
        icons="$(icon_variant "$base" Dark || true)"
        [ -n "$icons" ] \
            || { warn "icon theme $base is not installed — falling back to Adwaita"; icons="Adwaita"; }
    fi

    # prefer-dark and the accent are GNOME's own keys and a preference of the
    # user's, not this theme's styling, so they stand in every mode, as do the
    # GTK and shell themes: Performance is the theme with the blur removed.
    #
    # Written on every full run and full retune, not only the first install,
    # and on purpose (KI-16, decided 2026-10-15): the theme is dark-only — every
    # sheet, tint and the frosted ladder are tuned against a dark ground — so a
    # light color-scheme under it is a broken look, not a preference the theme
    # can honour. A retune is the way back to the look as designed.
    run gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    apply_accent
    run gsettings set org.gnome.desktop.interface gtk-theme "$THEME_NAME"
    run dconf write /org/gnome/shell/extensions/user-theme/name "'$THEME_NAME'"
    if [ -n "$icons" ]; then
        run gsettings set org.gnome.desktop.interface icon-theme   "$icons"
    fi

    # Remembered so the next flagless run comes back to this accent rather than
    # to the default. install.sh reads it back before validating. Written here
    # rather than at parse time so that a run which died before this point
    # leaves the previous answer standing.
    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        # "keep" is the memo for --no-icons, and the reason it has to exist:
        # without it the next flagless run reads the last pack out of icon-pack
        # and installs it again, which is the same override by a slower route.
        # remember_icon_pack writes the other answers, from install_icons.
        if [ "${WANT_ICONS:-1}" != 1 ]; then
            printf '%s\n' keep > "$CONF_DIR/icon-pack"
        fi
    fi

    apply_cursor_theme

    # Here rather than in load_dconf: it is a gsettings key like the four above,
    # and this is the step that runs in the --settings-only path with them.
    apply_window_buttons
    apply_cursor_size
    apply_font
    run gsettings set org.gnome.shell disable-extension-version-validation true

    # "left alone" rather than a name, because there is no name to give: the
    # key was not read and not written, and printing what it happens to hold
    # would read like this run had set it.
    local icon_say="${icons:-left alone}" cursor_say="${APPLIED_CURSOR:-left alone}"
    local font_say; font_say="$(font_family)"; font_say="${font_say:-system}"
    ok "gtk-theme=$THEME_NAME  icons=$icon_say  cursor=$cursor_say  accent=$ACCENT  font=$font_say"
}

# The three keys that carry the interface font, and the memo behind them.
#
# Three rather than one because GNOME splits the job: font-name is every label,
# menu and button; document-font-name is what text views and the document
# viewers read; and titlebar-font is Mutter's, under a different schema. Setting
# one and not the others is how a desktop ends up in two typefaces at once, so
# they move together.
#
# monospace-font-name is not here on purpose. None of the three fonts offered
# has a monospaced face, and writing one of them into that key would put a
# proportional font behind every terminal and code view on the machine.
#
# Font size is not this project's to have an opinion about: someone who set
# theirs to 10 or 12 did so about their screen, not about this theme. The size
# already in the key is kept and only the family is replaced, which is also
# what makes --font system able to be a true undo — it puts back exactly what
# gsettings_backup_once recorded, size and all.
apply_font() {
    local family; family="$(font_family)"

    # Recorded before the first write, so that --font system has something to
    # go back to that is the user's rather than GNOME's. Three separate names
    # because gsettings_backup_once keys its file by the name it is given.
    gsettings_backup_once org.gnome.desktop.interface font-name font-name
    gsettings_backup_once org.gnome.desktop.interface document-font-name document-font-name
    gsettings_backup_once org.gnome.desktop.wm.preferences titlebar-font titlebar-font

    if [ -z "$family" ]; then
        # Not `gsettings reset`: what is being restored is the font from before
        # this project first ran, and on a machine where that was already a
        # choice of the user's, reset would throw it away in favour of GNOME's
        # default. Reset is the fallback for a machine with nothing recorded,
        # which is the only case where GNOME's default is the honest answer.
        local key orig
        for key in font-name document-font-name; do
            orig="$(gsettings_original "$key")"
            if [ -n "$orig" ]; then
                run gsettings set org.gnome.desktop.interface "$key" "$orig"
            else
                run gsettings reset org.gnome.desktop.interface "$key"
            fi
        done
        orig="$(gsettings_original titlebar-font)"
        if [ -n "$orig" ]; then
            run gsettings set org.gnome.desktop.wm.preferences titlebar-font "$orig"
        else
            run gsettings reset org.gnome.desktop.wm.preferences titlebar-font
        fi
    else
        run gsettings set org.gnome.desktop.interface font-name \
            "$family $(font_size_now org.gnome.desktop.interface font-name)"
        run gsettings set org.gnome.desktop.interface document-font-name \
            "$family $(font_size_now org.gnome.desktop.interface document-font-name)"
        # Bold, because that is what GNOME's own default titlebar-font is
        # (Cantarell Bold 11) and a window title is the one place the desktop
        # asks for weight.
        run gsettings set org.gnome.desktop.wm.preferences titlebar-font \
            "$family Bold $(font_size_now org.gnome.desktop.wm.preferences titlebar-font)"
    fi

    # Remembered like the accent and the packs: a later flagless run has no
    # other way to know which font was chosen, and would come back to leaving
    # the keys alone over a deliberate --font.
    if [ "${DRY_RUN:-0}" != 1 ]; then
        mkdir -p "$CONF_DIR"
        printf '%s\n' "${FONT:-system}" > "$CONF_DIR/font"
    fi
}

# The size currently in one of the three font keys, or 11 where there is not
# one to read. Read live rather than out of the backup: someone who moved their
# interface font to 10 or 12 after installing did so about their screen, and a
# later run that put the recorded size back would undo it every time.
#
# "Cantarell 11" is a family and a size in one string, and only the trailing
# bare number is the size — "Cantarell Bold" has none, and neither has an empty
# key. gsettings prints strings quoted, so the quotes come off first.
font_size_now() {
    local desc last
    desc="$(gsettings get "$1" "$2" 2>/dev/null || true)"
    desc="${desc#\'}"; desc="${desc%\'}"
    last="${desc##* }"
    case "$last" in
        ''|*[!0-9]*)      printf '11\n' ;;
        "$desc")          printf '11\n' ;;   # no space in it: a family alone
        *)                printf '%s\n' "$last" ;;
    esac
}
