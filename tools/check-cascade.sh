#!/usr/bin/env bash
# Assert that every stylesheet in css/ is installed, applied and previewed, and
# that the cascade runs in the order the numeric prefixes ask for.
#
# This exists because three separate places decide the fate of a sheet and only
# one of them is a glob:
#
#   lib/steps*.sh     install_css copies css/shell-NN-*.css and css/gtk4-NN-*.css
#                     by glob, plus four sheets named explicitly
#   tools/preview.sh  build_profile copies the same set into the preview profile
#   bin/aura-glass-apply
#                     concatenates SHELL_SNIPPETS and GTK4_SNIPPETS, which are
#                     hand-written arrays naming every file
#
# So adding css/shell-25-whatever.css gets it installed into $CONF_DIR by the
# glob and rendered in a preview, and then silently never applied, because the
# array in aura-glass-apply was not updated. Nothing errors. The sheet is on
# disk, in the right place, with the right contents, and does nothing — which is
# the same "half-applied look with no error to explain it" this project pins its
# upstreams to avoid.
#
# The arrays cannot simply be replaced by a sorted glob: shell-popup-blur.css
# has to land after shell-90-density.css, and '9' sorts before 'p'. So the order
# stays hand-written and this checks it instead.
#
# Run it after adding, removing or renaming a sheet. Exits non-zero naming the
# file and the list that disagrees.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

python3 - <<'PY'
import fnmatch
import glob
import os
import re
import sys

ROOT = os.environ["REPO_ROOT"]

APPLY = "bin/aura-glass-apply"
PREVIEW = "tools/preview.sh"
# Every steps file, not lib/steps-css.sh by name: install_css has moved between
# files once already, when the steps were split by concern, and naming the file
# it happened to be in that day is how this check would go quietly blind.
# STEPS is the same string used as a label in the failure messages.
STEPS_GLOB = "lib/steps*.sh"
STEPS = "lib/steps*.sh"

# Sheets that aura-glass-apply names but css/ does not hold, because they are
# written at install time rather than kept in the tree. install_css generates
# this one from the measured display density; it gets prefix 90 so it lands
# after every hand-written shell sheet.
GENERATED = {"shell-90-density.css"}

failures = []


def read(rel):
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        failures.append("%s: file does not exist" % rel)
        return None
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def array_entries(text, name, rel):
    """The .css basenames listed in a `NAME=( ... )` bash array, in order."""
    m = re.search(r"^%s=\(\n(.*?)^\)" % re.escape(name), text, re.M | re.S)
    if not m:
        failures.append("%s: no %s=( ... ) array found — it was renamed or "
                        "reformatted, and this check tested nothing" % (rel, name))
        return []
    return re.findall(r'"\$DIR/([^"]+\.css)"', m.group(1))


def prefix_of(basename):
    """The cascade position in a NN-prefixed name, or None if it has none."""
    m = re.match(r"^(?:shell|gtk4)-(\d\d)-", basename)
    return int(m.group(1)) if m else None


# ------------------------------------------------------------- the sources --

apply_text = read(APPLY)
preview_text = read(PREVIEW)

steps_files = sorted(glob.glob(os.path.join(ROOT, STEPS_GLOB)))
if not steps_files:
    failures.append("%s: matched no files — the steps were renamed, and this "
                    "check tested nothing" % STEPS_GLOB)
steps_text = "\n".join(
    open(p, encoding="utf-8").read() for p in steps_files)

if apply_text is None or not steps_files or preview_text is None:
    print("cascade check FAILED\n")
    for f in failures:
        print("  " + f)
    sys.exit(1)

css_dir = os.path.join(ROOT, "css")
on_disk = sorted(f for f in os.listdir(css_dir) if f.endswith(".css"))

shell_list = array_entries(apply_text, "SHELL_SNIPPETS", APPLY)
gtk4_list = array_entries(apply_text, "GTK4_SNIPPETS", APPLY)
# gtk3 is applied on its own line rather than through an array, being one file.
gtk3_list = re.findall(r'apply "\$GTK3_CSS"\s+\d+\s+"\$DIR/([^"]+\.css)"', apply_text)

applied = set(shell_list) | set(gtk4_list) | set(gtk3_list)


def reachable(text):
    """Basenames a script can put into $CONF_DIR, by literal name or by glob."""
    names = set(re.findall(r'css/([A-Za-z0-9_.-]+\.css)', text))
    globs = re.findall(r'css/((?:shell|gtk4)-\[0-9\]\[0-9\]-\*\.css)', text)
    for g in globs:
        pattern = g.replace("[0-9][0-9]", "[0-9][0-9]")
        for f in on_disk:
            if fnmatch.fnmatch(f, pattern):
                names.add(f)
    return names


installed = reachable(steps_text)
previewed = reachable(preview_text)

checks = 0

# ---- every sheet in css/ is installed, applied and previewed ---------------

for f in on_disk:
    checks += 1
    if f not in installed:
        failures.append(
            "css/%s: nothing in %s installs it — it would never reach "
            "$CONF_DIR" % (f, STEPS))
    if f not in applied:
        target = "SHELL_SNIPPETS" if f.startswith("shell-") else (
            "GTK4_SNIPPETS" if f.startswith("gtk4-") else "the gtk3 apply line")
        failures.append(
            "css/%s: not listed in %s's %s — it would be installed and then "
            "silently never applied" % (f, APPLY, target))
    if f not in previewed:
        failures.append(
            "css/%s: not copied by %s — a preview would not show it" % (f, PREVIEW))

# ---- every applied sheet exists, or is generated --------------------------

for f in sorted(applied):
    checks += 1
    if f not in on_disk and f not in GENERATED:
        failures.append(
            "%s lists %s, but css/ does not hold it and it is not a known "
            "generated sheet — it is either a typo or a leftover rename"
            % (APPLY, f))

# ---- the arrays run in cascade order --------------------------------------

for name, entries in (("SHELL_SNIPPETS", shell_list), ("GTK4_SNIPPETS", gtk4_list)):
    seen_unnumbered = None
    last = None
    for f in entries:
        checks += 1
        p = prefix_of(f)
        if p is None:
            seen_unnumbered = f
            continue
        if seen_unnumbered is not None:
            failures.append(
                "%s: %s carries a cascade prefix but is listed after %s, which "
                "carries none. Un-prefixed sheets are overrides and go last."
                % (name, f, seen_unnumbered))
        if last is not None and p <= last[0]:
            how = "duplicates" if p == last[0] else "goes backwards from"
            failures.append(
                "%s: %s %s %s — the prefix is the cascade position, so the "
                "order in this array has to be ascending and unique"
                % (name, f, how, last[1]))
        last = (p, f)

# ---- every literal css/ path in the scripts points at a real sheet --------
#
# The checks above ask whether a sheet is reachable, and a sheet can be reachable
# through the NN glob while an explicit path to it is misspelled — which is
# exactly the case for the optional sheets, each of which is both swept up by the
# glob and named again in its own conditional. A rename that updates the glob's
# world but misses one of those literals would install nothing, remove nothing,
# and report nothing, so the literals are checked on their own terms.

def code_only(text):
    """The script with its comments removed.

    This check is about install paths, so it reads the code and not the prose
    around it. A comment naming a sheet that no longer exists is worth fixing —
    and one was, when this check was written — but it installs nothing, and
    failing a commit over a sentence is how a check gets bypassed by habit.
    """
    return "\n".join(re.sub(r"(^|\s)#.*$", "", l) for l in text.split("\n"))


for rel, text in ((STEPS, code_only(steps_text)),
                  (PREVIEW, code_only(preview_text))):
    for name in sorted(set(re.findall(r'css/([A-Za-z0-9_.-]+\.css)', text))):
        checks += 1
        if name not in on_disk:
            failures.append(
                "%s names css/%s, which is not in css/ — a rename that missed "
                "one of its references, and nothing would have said so"
                % (rel, name))

# ---- prefixes are unique on disk too --------------------------------------

for family in ("shell", "gtk4"):
    seen = {}
    for f in on_disk:
        if not f.startswith(family + "-"):
            continue
        p = prefix_of(f)
        if p is None:
            continue
        checks += 1
        if p in seen:
            failures.append(
                "css/%s and css/%s share cascade position %02d — which of the "
                "two wins on equal specificity is then decided by the array "
                "order alone, invisibly" % (seen[p], f, p))
        seen[p] = f

if failures:
    print("cascade check FAILED\n")
    for f in failures:
        print("  " + f)
    print("\n%d problem%s" % (len(failures), "" if len(failures) == 1 else "s"))
    sys.exit(1)

print("cascade check passed — %d sheet%s installed, applied, previewed and in "
      "order (%d assertion%s)"
      % (len(on_disk), "" if len(on_disk) == 1 else "s",
         checks, "" if checks == 1 else "s"))
PY
