#!/usr/bin/env python3
"""Rewrite the installed stylesheets to a different set of corner radii.

    apply-radius-preset.py CONF_DIR WINDOW MENU QUICK_SETTINGS \\
                           NOTIFICATION DIALOG POPUP OSD

The seven values are positional, in tools/token_manifest.py's RADIUS_TOKENS
order — the same order tokens/tokens.sh's radius_preset_values() sets them in.
OSD is accepted and ignored here: no stylesheet paints it, Custom OSD draws the
pill and Blur My Shell rounds the blur, so it is applied as a dconf key by
apply_radius_dconf() in lib/steps-dconf.sh. It stays in the argument list so
that one preset is one argument vector everywhere rather than two shapes that
have to be kept in step.

CONF_DIR is ~/.config/aura-glass — the flat copies install_css puts there, never
the repo. css/ and dconf/core.ini stay at the shipped `default` values so
tools/check-tokens.sh keeps checking one known state; this rewrites what is
actually loaded. bin/aura-glass-apply then splices the result into the theme,
exactly as it does after install_transparency_css rescales the alphas.

Which sites get rewritten is tools/token_manifest.py's answer, not this file's:
every capture group of every radius entry's regex is a number to replace. That
is the same list tools/check-tokens.sh asserts against, so a site this misses is
a site the checker was not watching either — and tools/check-radius-preset.sh
fails if either of those is true.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from token_manifest import OPTIONAL_SHEETS, RADIUS_TOKENS, css_entries  # noqa: E402

import re  # noqa: E402


def main():
    if len(sys.argv) != 2 + len(RADIUS_TOKENS):
        print("usage: apply-radius-preset.py CONF_DIR %s"
              % " ".join(t.replace("TOKEN_RADIUS_", "") for t in RADIUS_TOKENS),
              file=sys.stderr)
        return 2

    conf_dir = sys.argv[1]
    values = dict(zip(RADIUS_TOKENS, sys.argv[2:]))
    for token, value in values.items():
        if not re.fullmatch(r"\d+", value):
            print("apply-radius-preset: %s is %r, want a whole number of pixels"
                  % (token, value), file=sys.stderr)
            return 2

    entries = css_entries(set(RADIUS_TOKENS))
    problems = []
    skipped = []
    edits = 0

    # Grouped by sheet so each file is read and written once, and so a sheet
    # with two tokens in it (shell-20-popup-menus.css has the menu radius and
    # the Quick Settings one) cannot have the second pass read a stale copy.
    by_sheet = {}
    for token, _, rel, pattern in entries:
        by_sheet.setdefault(os.path.basename(rel), []).append((token, pattern))

    for base, patterns in sorted(by_sheet.items()):
        path = os.path.join(conf_dir, base)
        if not os.path.exists(path):
            # The two optional sheets are installed and removed by install_css
            # rather than switched on at read time, so an absent one is this
            # install having said no to that mode — not a fault. Anything else
            # missing is an incomplete install, and silently leaving its radii
            # at the shipped value is the failure this reports rather than hides.
            if base in OPTIONAL_SHEETS:
                skipped.append(base)
                continue
            problems.append("%s: not in %s — every sheet the manifest names "
                            "apart from %s is installed unconditionally by "
                            "install_css, so a missing one means the install is "
                            "incomplete"
                            % (base, conf_dir, ", ".join(sorted(OPTIONAL_SHEETS))))
            continue

        text = open(path, encoding="utf-8").read()

        # Collect every (span, replacement) first, then splice from the end, so
        # each match is located in the text the manifest's regexes were written
        # against rather than in a partly-rewritten copy whose offsets have
        # already moved.
        spans = []
        for token, pattern in patterns:
            matches = list(re.finditer(pattern, text, re.M))
            if not matches:
                problems.append(
                    "%s: nothing matched the %s pattern — the selector was "
                    "probably renamed or moved, so this radius would have been "
                    "left at the shipped value while every other corner "
                    "moved.\n    pattern: %s" % (base, token, pattern))
                continue
            for m in matches:
                for i in range(1, (m.lastindex or 0) + 1):
                    spans.append((m.span(i), values[token]))

        for (start, end), value in sorted(spans, reverse=True):
            if text[start:end] != value:
                edits += 1
            text = text[:start] + value + text[end:]

        open(path, "w", encoding="utf-8").write(text)

    if problems:
        print("apply-radius-preset FAILED\n", file=sys.stderr)
        for p in problems:
            print("  " + p, file=sys.stderr)
        return 1

    written = len(by_sheet) - len(skipped)
    print("radii rewritten in %s — %d value%s in %d sheet%s%s"
          % (conf_dir, edits, "" if edits == 1 else "s",
             written, "" if written == 1 else "s",
             " (%s not installed)" % ", ".join(sorted(skipped)) if skipped else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
