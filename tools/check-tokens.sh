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

# The shipped values and radius_preset_values()'s `default` row are the same
# seven numbers written twice, so they get the same treatment as every other
# duplicated value here.
if ! radius_preset_matches_shipped; then
    echo "token check FAILED"
    echo
    echo "  tokens/tokens.sh: the TOKEN_RADIUS_* values and the 'default' row of"
    echo "  radius_preset_values() disagree. The default row must be the shipped"
    echo "  values, or --radius-preset default would install something else."
    exit 1
fi

python3 - <<'PY'
import os, re, sys

ROOT = os.environ["REPO_ROOT"]

# The pairing list lives in tools/token_manifest.py, because
# tools/apply-radius-preset.py needs the same one to know which radii to rewrite
# in an installed copy. See that file for the entry format.
sys.path.insert(0, os.path.join(ROOT, "tools"))
from token_manifest import MANIFEST

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
