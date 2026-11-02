#!/usr/bin/env python3
"""Give the shell's dark surfaces a colour, without changing how dark they are.

    apply-shell-tint.py CONF_DIR HEX
    apply-shell-tint.py --surface dock|panel|maximized-panel CONF_DIR HEX

The GTK sheet has one tint colour in one place (see tools/apply-tint-color.py).
The shell sheets do not: a notification ground, a menu ground and a dialog
ground are eight separate rgba() literals, each picked against what sits in
front of it. So there is nothing to swap — what this does instead is take the
hue and the saturation of the chosen colour and leave every ground's own
lightness exactly where it was.

That is the property worth having. The lightness is what the contrast of the
white text on those surfaces was tuned against, and a rewriter that replaced
whole colours would decide legibility on the user's behalf. Keeping it means a
tint can only ever change what colour a surface is, never how readable it is.

Which literals are eligible, and why each rule is there:

  dark        a maximum channel at or under 96. The white overlays — 34 of
              them, every hover and every slider fill — are the other half of
              the shell's palette and are meant to stay white.
  neutral     no more than 12 between the highest and lowest channel. The
              theme's grounds are near-greys with a faint blue cast; anything
              already coloured is coloured on purpose, and -st-accent-color is
              not an rgba() at all.
  not black   pure #000 has no lightness to preserve, so it comes out black
              whatever the tint. That is the right answer rather than an
              exception: the rgba(0, 0, 0, …) literals in these sheets are
              shadows and scrims, and a tinted shadow is a bug.

A tint with no saturation — #000000, which is what ships — leaves every file
untouched, so the default costs nothing and going back to it is exact.

Run against the installed copies in $CONF_DIR. install_css lays those down
fresh from css/ on every run, so this never compounds and css/ stays at the one
state tools/check-tokens.sh checks.

--surface is the other question: one surface wearing exactly the colour picked,
rather than every ground leaning toward a hue. Hue-only is right for eight
grounds whose contrast was tuned one by one; the dock and the top bar are a
single colour the user is looking straight at, and a pick that came out at some
other lightness would read as the picker being wrong. Only the channels move,
so each mode's alpha stands (0.42 over frosted's blur, 0.99 in the solid sheet)
and --maximized-panel-brightness keeps owning the shade's. Runs after the shell
tint, so the surface's own answer is the one left in the sheet.
"""
import colorsys
import glob
import os
import re
import sys

HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
RGBA = re.compile(r"rgba?\((\d+), *(\d+), *(\d+)(?:, *([0-9.]+))?\)")

MAX_CHANNEL = 96      # anything brighter is an overlay, not a ground
MAX_SPREAD = 12       # anything less neutral is already a colour

# The rules a --surface owns, by the selectors they are written with. Dock and
# search are one surface because shell-00-flat.css makes them one: the search
# bar and its results card take the dash's ground so the overview reads as a
# single material. The solid sheet groups the same selectors.
SURFACE_RULES = {
    "dock": ("#dash .dash-background", "#overview .search-entry",
             ".search-section-content"),
    "maximized-panel": ("#panel.aura-glass-maximized",
                        "#panel.transparent-panel.aura-glass-maximized"),
}

COMMENT = re.compile(r"(/\*.*?\*/)", re.S)
RULE = re.compile(r"([^{}]+)\{([^{}]*)\}")
BACKGROUND = re.compile(r"(background-color: *)rgba?\(\d+, *\d+, *\d+(, *[0-9.]+)?\)")

# A top bar over the desktop ships with no colour of its own, so there is no
# literal to recolour and the rule has to be written. The dock's alpha, so a
# bar and a dock given one colour read as one material. Blur My Shell's
# #panel.transparent-panel is in an extension sheet, so aura-glass-apply copies
# that selector's half out to extension-overrides.css; plain #panel is what the
# bar is once the solid preset has turned the panel's blur off. The overview
# gives the bar its own look (the helper lifts the maximized shade for the same
# reason) and the lock and login screens draw it over their own backgrounds, so
# all three stay clear.
PANEL_ALPHA = 0.42
PANEL_RULE = """
#panel,
#panel.transparent-panel {
  background-color: rgba(%d, %d, %d, %s) !important;
}

#panel:overview,
#panel.unlock-screen,
#panel.login-screen,
#panel.lock-screen,
#panel.transparent-panel:overview,
#panel.transparent-panel.unlock-screen,
#panel.transparent-panel.login-screen,
#panel.transparent-panel.lock-screen {
  background-color: transparent !important;
}
"""


def recolour_rules(conf, selectors, red, green, blue):
    """Set the channels of the backgrounds in the rules naming `selectors`."""
    def recolour(match):
        named = {s.strip() for s in match.group(1).split(",")}
        if not named.intersection(selectors):
            return match.group(0)
        def channels(found):
            alpha = found.group(2) or ", 1"
            return "%srgba(%d, %d, %d%s)" % (found.group(1), red, green, blue,
                                             alpha)
        return "%s{%s}" % (match.group(1),
                           BACKGROUND.sub(channels, match.group(2)))

    touched = 0
    for path in sorted(glob.glob(os.path.join(conf, "shell-*.css"))):
        text = open(path, encoding="utf-8").read()
        # Comment by comment: these sheets quote rules in their prose, braces
        # and all, and a quoted rule is not one to rewrite.
        parts = COMMENT.split(text)
        parts[::2] = [RULE.sub(recolour, part) for part in parts[::2]]
        new = "".join(parts)
        if new != text:
            open(path, "w", encoding="utf-8").write(new)
            touched += 1
    return touched


def apply_surface(surface, conf, colour):
    red, green, blue = (int(colour[i:i + 2], 16) for i in (1, 3, 5))
    if surface == "panel":
        path = os.path.join(conf, "shell-00-flat.css")
        with open(path, "a", encoding="utf-8") as sheet:
            sheet.write(PANEL_RULE % (red, green, blue, PANEL_ALPHA))
        touched = 1
    else:
        touched = recolour_rules(conf, SURFACE_RULES[surface], red, green, blue)
    print("%s tinted %s in %d sheet%s"
          % (surface, colour, touched, "" if touched == 1 else "s"))
    return 0


def main():
    args = sys.argv[1:]
    surface = None
    if len(args) == 4 and args[0] == "--surface" \
            and args[1] in ("dock", "panel", "maximized-panel"):
        surface = args[1]
        args = args[2:]
    if len(args) != 2:
        print("usage: apply-shell-tint.py [--surface dock|panel|maximized-panel] "
              "CONF_DIR HEX", file=sys.stderr)
        return 2
    conf, colour = args[0], args[1].strip()

    if not HEX.match(colour):
        print("apply-shell-tint.py: '%s' is not a #rrggbb colour" % colour,
              file=sys.stderr)
        return 2

    if surface is not None:
        return apply_surface(surface, conf, colour)

    red = int(colour[1:3], 16) / 255.0
    green = int(colour[3:5], 16) / 255.0
    blue = int(colour[5:7], 16) / 255.0
    hue, _lightness, saturation = colorsys.rgb_to_hls(red, green, blue)

    if saturation <= 0.001:
        print("shell tint left at the theme's own greys (%s has no colour in "
              "it)" % colour)
        return 0

    def tint_line(line):
        is_bg = "background-color" in line or "background:" in line
        def tint(match):
            channels = [int(match.group(i)) for i in (1, 2, 3)]
            high, low = max(channels), min(channels)
            if high > MAX_CHANNEL or high - low > MAX_SPREAD:
                return match.group(0)
            alpha = match.group(4)
            if high == 0:
                if not is_bg:
                    return match.group(0)
                # Pure black background ground: give it a subtle dark ground lightness
                out = colorsys.hls_to_rgb(hue, 0.08, saturation)
                if alpha is not None:
                    return "rgba(%d, %d, %d, %s)" % (round(out[0] * 255),
                                                     round(out[1] * 255),
                                                     round(out[2] * 255), alpha)
                return "rgb(%d, %d, %d)" % (round(out[0] * 255),
                                            round(out[1] * 255),
                                            round(out[2] * 255))
            # The literal's own lightness, kept exactly; the hue and saturation are
            # the tint's.
            out = colorsys.hls_to_rgb(hue, (high + low) / 2.0 / 255.0, saturation)
            if alpha is not None:
                return "rgba(%d, %d, %d, %s)" % (round(out[0] * 255),
                                                 round(out[1] * 255),
                                                 round(out[2] * 255), alpha)
            return "rgb(%d, %d, %d)" % (round(out[0] * 255),
                                        round(out[1] * 255),
                                        round(out[2] * 255))
        return RGBA.sub(tint, line)

    total, touched = 0, 0
    for path in sorted(glob.glob(os.path.join(conf, "shell-*.css"))):
        lines = open(path, encoding="utf-8").readlines()
        new_lines = [tint_line(line) for line in lines]
        new = "".join(new_lines)
        text = "".join(lines)
        if new != text:
            open(path, "w", encoding="utf-8").write(new)
            touched += 1
        for old_l, new_l in zip(lines, new_lines):
            if old_l != new_l:
                total += 1

    print("shell tint %s applied to %d ground%s in %d sheet%s"
          % (colour, total, "" if total == 1 else "s",
             touched, "" if touched == 1 else "s"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
