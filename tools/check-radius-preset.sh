#!/usr/bin/env bash
# Assert that tools/apply-radius-preset.py rewrites exactly the radii it is
# meant to and nothing else.
#
# The writer runs a regex substitution over installed stylesheets, which is the
# same shape as the mistake tools/check-tokens.sh exists to catch — except a
# checker that is too broad merely reports noise, while a writer that is too
# broad silently restyles something unrelated. So this exercises the writer
# against throwaway copies and asserts three things:
#
#   1. every radius the manifest names comes out at the preset's value
#   2. every radius it does NOT name is untouched — the 9999px pills, the 10px
#      fields, the 12px menu items
#   3. sharp-then-default returns each file byte-for-byte to what the repo ships
#
# (3) is the one that would have caught a substitution that reformats or drops a
# trailing newline, which no per-value assertion can see.
#
# Run it after changing the writer, the manifest, or a preset table.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../tokens/tokens.sh
. "$REPO_ROOT/tokens/tokens.sh"

# Every preset's seven values, as `name:v,v,v,v,v,v,v`, so the Python below is
# testing the same table install.sh reads rather than a copy of it.
presets=""
for p in $RADIUS_PRESETS; do
    radius_preset_values "$p" || { echo "radius_preset_values rejected '$p'"; exit 1; }
    presets="$presets$p:$TOKEN_RADIUS_WINDOW,$TOKEN_RADIUS_MENU,$TOKEN_RADIUS_QUICK_SETTINGS,$TOKEN_RADIUS_NOTIFICATION,$TOKEN_RADIUS_DIALOG,$TOKEN_RADIUS_POPUP,$TOKEN_RADIUS_OSD
"
done

REPO_ROOT="$REPO_ROOT" PRESETS="$presets" python3 - <<'PY'
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.environ["REPO_ROOT"]
sys.path.insert(0, os.path.join(ROOT, "tools"))
from token_manifest import RADIUS_TOKENS, css_entries  # noqa: E402

WRITER = os.path.join(ROOT, "tools", "apply-radius-preset.py")
RADIUS_CSS = css_entries(set(RADIUS_TOKENS))
SHEETS = sorted({rel for _, _, rel, _ in RADIUS_CSS})

presets = {}
for line in os.environ["PRESETS"].split("\n"):
    if not line.strip():
        continue
    name, _, values = line.partition(":")
    presets[name] = values.split(",")

failures = []


def stage(tmp):
    """Copy the radius-bearing sheets in flat, the way install_css lays out
    $CONF_DIR — the writer is only ever pointed at that directory, never at the
    repo, so the test must not hand it a repo layout it would not see."""
    for rel in SHEETS:
        shutil.copyfile(os.path.join(ROOT, rel),
                        os.path.join(tmp, os.path.basename(rel)))


def apply(tmp, values):
    res = subprocess.run([sys.executable, WRITER, tmp] + list(values),
                         capture_output=True, text=True)
    if res.returncode != 0:
        failures.append("writer exited %d for %s:\n    %s"
                        % (res.returncode, values, res.stderr.strip()))
        return False
    return True


def check_values(tmp, name, values):
    """(1) Every radius the manifest names is at the preset's value."""
    want = dict(zip(RADIUS_TOKENS, values))
    for token, _, rel, pattern in RADIUS_CSS:
        path = os.path.join(tmp, os.path.basename(rel))
        text = open(path, encoding="utf-8").read()
        matches = list(re.finditer(pattern, text, re.M))
        if not matches:
            failures.append("%s: %s pattern matched nothing in the rewritten "
                            "copy — the writer moved or mangled the rule it was "
                            "supposed to edit in place" % (name, token))
            continue
        for m in matches:
            for got in m.groups():
                if got != want[token]:
                    failures.append("%s: %s in %s is %s, want %s"
                                    % (name, token, os.path.basename(rel),
                                       got, want[token]))


# Radii that belong to no token: capsules, and the one-consumer values
# tokens.sh deliberately does not track. Collected from the shipped sheets and
# required to survive every preset unchanged.
def untracked(text, tracked_spans):
    out = []
    for m in re.finditer(r"border-(?:top-left-|top-right-)?radius: (\d+)px", text):
        if not any(s <= m.start(1) < e for s, e in tracked_spans):
            out.append((m.start(1), m.group(1)))
    return out


def tracked_spans_for(rel, text):
    spans = []
    for token, _, r, pattern in RADIUS_CSS:
        if r != rel:
            continue
        for m in re.finditer(pattern, text, re.M):
            spans.extend(m.span(i) for i in range(1, (m.lastindex or 0) + 1))
    return spans


def check_untouched(tmp, name):
    """(2) Every radius the manifest does not name is untouched."""
    for rel in SHEETS:
        base = os.path.basename(rel)
        original = open(os.path.join(ROOT, rel), encoding="utf-8").read()
        before = untracked(original, tracked_spans_for(rel, original))
        after_text = open(os.path.join(tmp, base), encoding="utf-8").read()
        after = [v for _, v in untracked(after_text,
                                         tracked_spans_for(rel, after_text))]
        if [v for _, v in before] != after:
            failures.append("%s: %s — untracked radii changed: %s -> %s"
                            % (name, base, [v for _, v in before], after))


for name, values in presets.items():
    with tempfile.TemporaryDirectory() as tmp:
        stage(tmp)
        if not apply(tmp, values):
            continue
        check_values(tmp, name, values)
        check_untouched(tmp, name)

        # Applying the same preset twice must be a no-op the second time.
        again = {b: open(os.path.join(tmp, b), encoding="utf-8").read()
                 for b in (os.path.basename(r) for r in SHEETS)}
        apply(tmp, values)
        for base, text in again.items():
            if open(os.path.join(tmp, base), encoding="utf-8").read() != text:
                failures.append("%s: %s is not idempotent — a second apply "
                                "changed it again" % (name, base))

# (3) sharp -> default returns every byte. Run against whichever preset is
# furthest from the shipped values rather than hardcoding a name.
with tempfile.TemporaryDirectory() as tmp:
    stage(tmp)
    other = next((n for n in presets if n != "default"), None)
    if other is None:
        failures.append("no preset other than 'default' to round-trip against")
    elif apply(tmp, presets[other]) and apply(tmp, presets["default"]):
        for rel in SHEETS:
            base = os.path.basename(rel)
            if (open(os.path.join(tmp, base), encoding="utf-8").read()
                    != open(os.path.join(ROOT, rel), encoding="utf-8").read()):
                failures.append(
                    "%s: round trip via '%s' did not restore the shipped file "
                    "byte-for-byte" % (base, other))

if failures:
    print("radius preset check FAILED\n")
    for f in failures:
        print("  " + f)
    print("\n%d problem%s" % (len(failures), "" if len(failures) == 1 else "s"))
    sys.exit(1)

print("radius preset check passed — %d preset%s rewrite %d site%s in %d sheet%s"
      % (len(presets), "" if len(presets) == 1 else "s",
         len(RADIUS_CSS), "" if len(RADIUS_CSS) == 1 else "s",
         len(SHEETS), "" if len(SHEETS) == 1 else "s"))
PY
