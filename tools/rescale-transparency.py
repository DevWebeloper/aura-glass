#!/usr/bin/env python3
"""Rewrite an installed gtk4-transparency.css to a different level.

    rescale-transparency.py SHEET WANT SHIPPED

The sheet is written at the shipped level so that it is readable on its own.
--app-transparency N rewrites both spellings of every value in the *installed*
copy, scaling the whole ladder rather than flattening it: the header bar is
meant to stay a little more transparent than the window and the content view a
little less, at any setting.

Used by lib/steps.sh at install time and by tools/preview.sh when rendering a
candidate, so that a preview is the same arithmetic as the real thing rather
than a second implementation of it.

The tint (TOKEN_APP_TINT) is deliberately not touched. It sets how dark the
ground under the alpha is, which is a design decision rather than a per-install
level, and it lives literally in the sheet where check-tokens.sh can see it.
"""
import re
import sys


def main():
    if len(sys.argv) != 4:
        print("usage: rescale-transparency.py SHEET WANT SHIPPED", file=sys.stderr)
        return 2
    path, want, shipped = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])

    def scale(base):
        # Keep each surface's distance from opaque in proportion, so the ladder
        # written into the sheet survives being retuned.
        if want >= 1.0:
            return 1.0
        return max(0.0, min(1.0, 1 - (1 - base) * (1 - want) / (1 - shipped)))

    css = open(path, encoding="utf-8").read()
    css = re.sub(r"alpha\((@[a-z_]+), ([0-9.]+)\)",
                 lambda m: "alpha(%s, %.2f)" % (m.group(1), scale(float(m.group(2)))),
                 css)
    # The tint blocks use `var(--x) N%, #000000`; the transparency rules use
    # `var(--x) N%, transparent`. Only the second is a level, so the trailing
    # colour is matched too rather than just the percentage.
    css = re.sub(r"(var\(--[a-z0-9_-]+\)) ([0-9.]+)%, transparent",
                 lambda m: "%s %g%%, transparent"
                 % (m.group(1), round(scale(float(m.group(2)) / 100) * 100, 1)),
                 css)
    open(path, "w", encoding="utf-8").write(css)
    return 0


if __name__ == "__main__":
    sys.exit(main())
