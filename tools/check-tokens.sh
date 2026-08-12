#!/usr/bin/env bash
# Assert that every value in tokens/tokens.sh still matches every file that
# writes it down. Exits non-zero naming the exact file and line that disagrees.
#
# This exists because the same number lives in a stylesheet and in a dconf key
# with only a comment linking them, and a comment cannot fail. The pairing that
# cost a whole tuning pass to find — .datemenu-popover painted at one radius
# while Blur My Shell rounded it at another — is now a one-line failure here.
#
# Run it after changing a token, after changing any radius or sigma by hand,
# and after moving CSS between files.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../tokens/tokens.sh
. "$REPO_ROOT/tokens/tokens.sh"

export REPO_ROOT
export TOKEN_RADIUS_WINDOW TOKEN_RADIUS_MENU TOKEN_RADIUS_QUICK_SETTINGS
export TOKEN_RADIUS_NOTIFICATION TOKEN_RADIUS_DIALOG TOKEN_RADIUS_POPUP
export TOKEN_RADIUS_OSD
export TOKEN_SIGMA_PANEL TOKEN_SIGMA_APPFOLDER TOKEN_SIGMA_POPUP
export TOKEN_SIGMA_WINDOW_LIST TOKEN_SIGMA_APPLICATIONS TOKEN_SIGMA_DASH_TO_DOCK
export TOKEN_APP_TRANSPARENCY_SHIPPED TOKEN_APP_TINT

python3 - <<'PY'
import os, re, sys

ROOT = os.environ["REPO_ROOT"]

# Each entry is (token name, kind, *args).
#
#   css: (file, regex) — every capture group of every match must equal the
#        token. The regex MUST match at least once; a regex that has stopped
#        matching because a selector was renamed is a silently-passing check,
#        which is worse than no check, so that is a failure too.
#   ini: (file, section, key) — the key's value in that section must equal the
#        token. Section-scoped because corner-radius and sigma both appear
#        under several Blur My Shell components with different values.
#
# The `[^}]*?` in the CSS patterns cannot cross a closing brace, so each one
# stays inside the rule its selector opened.
MANIFEST = [
    ("TOKEN_RADIUS_WINDOW", "css", "css/gtk3-tweaks.css",
     r"^decoration \{[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_WINDOW", "css", "css/gtk3-tweaks.css",
     r"^\.titlebar,\n\.titlebar\.background \{[^}]*?"
     r"border-top-left-radius: (\d+)px;\s*border-top-right-radius: (\d+)px"),
    ("TOKEN_RADIUS_WINDOW", "ini", "dconf/core.ini",
     "blur-my-shell/applications", "corner-radius"),

    ("TOKEN_RADIUS_MENU", "css", "css/shell-20-popup-menus.css",
     r"^\.popup-menu-content \{[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_MENU", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "menu-corner-radius"),

    ("TOKEN_RADIUS_QUICK_SETTINGS", "css", "css/shell-20-popup-menus.css",
     r"^\.datemenu-popover \{[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_QUICK_SETTINGS", "css", "css/shell-20-popup-menus.css",
     r"^\.popup-menu-content\.quick-settings,[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_QUICK_SETTINGS", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "quick-settings-corner-radius"),

    ("TOKEN_RADIUS_NOTIFICATION", "css", "css/shell-30-notifications.css",
     r"^\.message \{[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_NOTIFICATION", "css", "css/shell-30-notifications.css",
     r"^\.notification-banner \{[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_NOTIFICATION", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "notification-corner-radius"),

    ("TOKEN_RADIUS_DIALOG", "css", "css/shell-50-dialogs.css",
     r"^\.modal-dialog,\n\.end-session-dialog \{[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_DIALOG", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "dialog-corner-radius"),

    ("TOKEN_RADIUS_POPUP", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "corner-radius"),
    ("TOKEN_RADIUS_OSD", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "osd-corner-radius"),

    ("TOKEN_SIGMA_PANEL", "ini", "dconf/core.ini",
     "blur-my-shell/panel", "sigma"),
    ("TOKEN_SIGMA_APPFOLDER", "ini", "dconf/core.ini",
     "blur-my-shell/appfolder", "sigma"),
    ("TOKEN_SIGMA_POPUP", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "sigma"),
    ("TOKEN_SIGMA_WINDOW_LIST", "ini", "dconf/core.ini",
     "blur-my-shell/window-list", "sigma"),
    ("TOKEN_SIGMA_APPLICATIONS", "ini", "dconf/core.ini",
     "blur-my-shell/applications", "sigma"),
    ("TOKEN_SIGMA_DASH_TO_DOCK", "ini", "dconf/core.ini",
     "blur-my-shell/dash-to-dock", "sigma"),

    ("TOKEN_APP_TRANSPARENCY_SHIPPED", "css", "css/gtk4-transparency.css",
     r"alpha\(@tg_tint_window, ([0-9.]+)\)"),
    # Both spellings of the tint, and the mix() weight is the complement.
    ("TOKEN_APP_TINT", "css", "css/gtk4-transparency.css",
     r"var\(--window-bg-color\) (\d+)%, #000000"),
    # The prose in the sheet's own header states the baseline too. A stale
    # comment here is how the next person picks the wrong number by hand.
    ("TOKEN_APP_TRANSPARENCY_SHIPPED", "css", "css/gtk4-transparency.css",
     r"the shipped level, ([0-9.]+)\."),
]

failures = []
checks = 0


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def read(rel):
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        failures.append("%s: file does not exist" % rel)
        return None
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def check_css(token, want, rel, pattern):
    global checks
    text = read(rel)
    if text is None:
        return
    matches = list(re.finditer(pattern, text, re.M))
    if not matches:
        failures.append(
            "%s: nothing matched the check for %s — the selector was probably "
            "renamed or moved, so this check was passing without testing "
            "anything.\n    pattern: %s" % (rel, token, pattern))
        return
    for m in matches:
        for got in m.groups():
            checks += 1
            if got != want:
                failures.append(
                    "%s:%d: %s is %s in tokens.sh but %s here"
                    % (rel, line_of(text, m.start()), token, want, got))


def check_ini(token, want, rel, section, key):
    global checks
    text = read(rel)
    if text is None:
        return
    current = None
    found = False
    for n, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            current = stripped[1:-1]
            continue
        if current != section or "=" not in stripped:
            continue
        name, _, got = stripped.partition("=")
        if name.strip() != key:
            continue
        found = True
        checks += 1
        if got.strip() != want:
            failures.append("%s:%d: %s is %s in tokens.sh but %s here"
                            % (rel, n, token, want, got.strip()))
    if not found:
        failures.append("%s: [%s] has no %s key — the check for %s tested "
                        "nothing" % (rel, section, key, token))


for entry in MANIFEST:
    token, kind, rel = entry[0], entry[1], entry[2]
    want = os.environ.get(token)
    if want is None:
        failures.append("tokens/tokens.sh: %s is not defined, but "
                        "check-tokens.sh expects it" % token)
        continue
    if kind == "css":
        check_css(token, want, rel, entry[3])
    else:
        check_ini(token, want, rel, entry[3], entry[4])

if failures:
    print("token check FAILED\n")
    for f in failures:
        print("  " + f)
    print("\n%d problem%s" % (len(failures), "" if len(failures) == 1 else "s"))
    sys.exit(1)

print("token check passed — %d value%s agree with tokens/tokens.sh"
      % (checks, "" if checks == 1 else "s"))
PY
