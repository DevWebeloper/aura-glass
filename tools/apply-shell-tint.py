#!/usr/bin/env python3
"""Give the shell's dark surfaces a colour, without changing how dark they are.

    apply-shell-tint.py CONF_DIR HEX

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
"""
import colorsys
import glob
import os
import re
import sys

HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
RGBA = re.compile(r"rgba\((\d+), *(\d+), *(\d+), *([0-9.]+)\)")

MAX_CHANNEL = 96      # anything brighter is an overlay, not a ground
MAX_SPREAD = 12       # anything less neutral is already a colour


def main():
    if len(sys.argv) != 3:
        print("usage: apply-shell-tint.py CONF_DIR HEX", file=sys.stderr)
        return 2
    conf, colour = sys.argv[1], sys.argv[2].strip()

    if not HEX.match(colour):
        print("apply-shell-tint.py: '%s' is not a #rrggbb colour" % colour,
              file=sys.stderr)
        return 2

    red = int(colour[1:3], 16) / 255.0
    green = int(colour[3:5], 16) / 255.0
    blue = int(colour[5:7], 16) / 255.0
    hue, _lightness, saturation = colorsys.rgb_to_hls(red, green, blue)

    if saturation <= 0.001:
        print("shell tint left at the theme's own greys (%s has no colour in "
              "it)" % colour)
        return 0

    def tint(match):
        channels = [int(match.group(i)) for i in (1, 2, 3)]
        high, low = max(channels), min(channels)
        if high > MAX_CHANNEL or high - low > MAX_SPREAD or high == 0:
            return match.group(0)
        # The literal's own lightness, kept exactly; the hue and saturation are
        # the tint's.
        out = colorsys.hls_to_rgb(hue, (high + low) / 2.0 / 255.0, saturation)
        return "rgba(%d, %d, %d, %s)" % (round(out[0] * 255),
                                         round(out[1] * 255),
                                         round(out[2] * 255), match.group(4))

    total, touched = 0, 0
    for path in sorted(glob.glob(os.path.join(conf, "shell-*.css"))):
        text = open(path, encoding="utf-8").read()
        new, count = RGBA.subn(tint, text)
        if new != text:
            open(path, "w", encoding="utf-8").write(new)
            touched += 1
        total += sum(1 for m in RGBA.finditer(text) if tint(m) != m.group(0))

    print("shell tint %s applied to %d ground%s in %d sheet%s"
          % (colour, total, "" if total == 1 else "s",
             touched, "" if touched == 1 else "s"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
