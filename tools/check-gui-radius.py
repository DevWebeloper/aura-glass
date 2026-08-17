#!/usr/bin/env python3
"""Assert the settings window's radius numbers agree with tokens/tokens.sh.

The window carries its own copy of the four preset rows and of the per-surface
bounds, because it has to know them before install.sh runs — the spin rows need
their ranges at build time, and the preset buttons have to set seven values
without shelling out on every click.

That is the same arrangement tokens.sh already defends for the stylesheets: the
values live literally where they are used, and a checker makes the duplication
checked rather than trusted. This is that checker for the window's copy. Change
radius_preset_values() or radius_bounds() and run this, and it names every
number the window still disagrees about.

Run from anywhere; needs bash and python3, no display and no network.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "gui"))

# No .pyc beside the window. Python decides a cached one is current from the
# source's mtime and size alone, and two runs of this checker either side of a
# same-length edit inside one second is exactly the case that fools it — which
# is a checker reporting on a file that is no longer there.
sys.dont_write_bytecode = True

# gi is only needed to import the window module at all, and a machine without
# PyGObject is one where the window is not installed either — the same reason
# tools/check-gui-flags.py skips rather than fails.
try:
    import gi  # noqa: F401
except ImportError:
    print("gui radius check skipped — PyGObject is not installed")
    sys.exit(0)

try:
    from aura_glass_settings import RADIUS_PRESET_VALUES, RADIUS_SURFACES
except (ImportError, ValueError):
    print("gui radius check skipped — the GTK4/libadwaita bindings are not here")
    sys.exit(0)


def shell_values(snippet):
    """Source tokens.sh, run a snippet, and read back name=value lines."""
    out = subprocess.run(
        ["bash", "-c", ". %s/tokens/tokens.sh\n%s" % (ROOT, snippet)],
        capture_output=True, text=True)
    if out.returncode != 0:
        print("could not read tokens.sh:\n%s" % out.stderr.strip())
        sys.exit(1)
    values = {}
    for line in out.stdout.splitlines():
        name, _, value = line.partition("=")
        if name:
            values[name] = int(value)
    return values


problems = []

# ---- the four preset rows ----
#
# Asked of tokens.sh one preset at a time, in the same order the window stores
# them, which is tools/token_manifest.py's RADIUS_TOKENS order.
NAMES = ["WINDOW", "MENU", "QUICK_SETTINGS", "NOTIFICATION", "DIALOG", "POPUP",
         "OSD"]

for preset, gui_row in sorted(RADIUS_PRESET_VALUES.items()):
    shell = shell_values(
        "radius_preset_values %s || exit 1\n" % preset
        + "\n".join('echo "%s=$TOKEN_RADIUS_%s"' % (n, n) for n in NAMES))
    shell_row = tuple(shell[n] for n in NAMES)
    if shell_row != tuple(gui_row):
        problems.append(
            "preset %s: tokens.sh says %s, the window says %s"
            % (preset, shell_row, tuple(gui_row)))

# ---- the per-surface bounds ----
bounds = shell_values(
    "radius_bounds\n"
    + "\n".join('echo "MIN_%s=$RADIUS_MIN_%s"\necho "MAX_%s=$RADIUS_MAX_%s"'
                % (n, n, n, n) for n in NAMES))

if len(RADIUS_SURFACES) != len(NAMES):
    problems.append("the window lists %d surfaces, tokens.sh has %d"
                    % (len(RADIUS_SURFACES), len(NAMES)))
else:
    for name, (ident, _title, low, high, _sub) in zip(NAMES, RADIUS_SURFACES):
        if (low, high) != (bounds["MIN_" + name], bounds["MAX_" + name]):
            problems.append(
                "bounds for %s: tokens.sh says %d-%d, the window says %d-%d"
                % (name, bounds["MIN_" + name], bounds["MAX_" + name],
                   low, high))

# Every preset has to fit inside the bounds, or a preset button would set a
# value the spin row beside it refuses to hold.
for preset, row in sorted(RADIUS_PRESET_VALUES.items()):
    for name, value in zip(NAMES, row):
        if not bounds["MIN_" + name] <= value <= bounds["MAX_" + name]:
            problems.append(
                "preset %s puts %s at %d, outside its own bounds %d-%d"
                % (preset, name, value,
                   bounds["MIN_" + name], bounds["MAX_" + name]))

if problems:
    print("gui radius check FAILED\n")
    for problem in problems:
        print("  " + problem)
    print("\n%d problem%s" % (len(problems), "" if len(problems) == 1 else "s"))
    sys.exit(1)

print("gui radius check passed — %d presets and %d bounds agree with tokens.sh"
      % (len(RADIUS_PRESET_VALUES), len(NAMES)))
