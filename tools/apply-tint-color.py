#!/usr/bin/env python3
"""Recolour the tint an installed gtk4-transparency.css darkens toward.

    apply-tint-color.py SHEET HEX

The sheet mixes every translucent ground toward a colour before the alpha is
applied — see the "Darkened grounds" block in css/gtk4-transparency.css. That
colour ships as #000000, which is what makes a translucent window read as
smoked glass. This swaps it for another, so the same window reads as tinted
glass instead.

Only the colour moves. TOKEN_APP_TINT decides *how much* of the theme's own
colour survives the mix and is left alone here, exactly as
tools/rescale-transparency.py leaves it alone: how dark the ground is is a
design decision, and how coloured it is is the user's.

Both spellings are rewritten, because the sheet carries both — the
named-colour mix() for the libadwaita back-compat shim, and the color-mix()
form for when that shim goes. A run that moved one and not the other would
recolour a window on one libadwaita and not on the next.

Run against the installed copy in $CONF_DIR, never against css/, for the same
reason every other rewriter here is: css/ stays at one known state that
tools/check-tokens.sh keeps checking.
"""
import re
import sys

HEX = re.compile(r"^#[0-9a-fA-F]{6}$")

# mix(@window_bg_color, #000000, 0.55) — the named-colour spelling.
NAMED = re.compile(r"(mix\(@[a-z_]+, )#[0-9a-fA-F]{6}(, [0-9.]+\))")

# color-mix(in srgb, var(--window-bg-color) 45%, #000000) — the standard one.
# The trailing colour is matched rather than assumed: the same shape with
# `transparent` at the end is a transparency level, and rewriting one of those
# would make every window opaque.
MODERN = re.compile(r"(color-mix\(in srgb, var\(--[a-z0-9-]+\) [0-9.]+%, )"
                    r"#[0-9a-fA-F]{6}(\))")


def main():
    if len(sys.argv) != 3:
        print("usage: apply-tint-color.py SHEET HEX", file=sys.stderr)
        return 2
    path, colour = sys.argv[1], sys.argv[2].strip()

    if not HEX.match(colour):
        print("apply-tint-color.py: '%s' is not a #rrggbb colour" % colour,
              file=sys.stderr)
        return 2
    colour = colour.lower()

    css = open(path, encoding="utf-8").read()
    css, named = NAMED.subn(lambda m: m.group(1) + colour + m.group(2), css)
    css, modern = MODERN.subn(lambda m: m.group(1) + colour + m.group(2), css)

    if not named or not modern:
        # Both spellings or neither. One of them missing means the sheet is not
        # the one this was written against, and half a recolour is worse than
        # none — it would tint a window under one libadwaita and not the next.
        print("apply-tint-color.py: %s has %d named and %d color-mix tint "
              "sites — expected both" % (path, named, modern), file=sys.stderr)
        return 1

    open(path, "w", encoding="utf-8").write(css)
    print("tinted %d ground%s toward %s"
          % (named, "" if named == 1 else "s", colour))
    return 0


if __name__ == "__main__":
    sys.exit(main())
