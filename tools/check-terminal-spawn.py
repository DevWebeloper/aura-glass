#!/usr/bin/env python3
"""Assert the settings window builds a runnable command line for each terminal.

Whether a spawned terminal really stays open is a thing only a desktop can
answer, and this does not pretend to. What it does catch is the cheap half:
an argv that is malformed, a builder that drops the command, a wrapper that
does not survive being parsed by the shell it is handed to. Those are the
mistakes that would otherwise only show up as a window that flashes and closes
on a machine nobody testing this happens to have.

Run from anywhere; needs bash and python3, no display and no network. It never
launches a terminal.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "gui"))
sys.dont_write_bytecode = True

try:
    import gi  # noqa: F401
except ImportError:
    print("terminal spawn check skipped — PyGObject is not installed")
    sys.exit(0)

try:
    from aura_glass_settings import TERMINALS, keep_open
except (ImportError, ValueError):
    print("terminal spawn check skipped — the GTK4 bindings are not here")
    sys.exit(0)

problems = []

# A command with the things that actually turn up in one: a path that could
# contain a space, quotes, and the && the update path uses.
COMMAND = "bash '/home/a b/aura-glass/install.sh' --deps-only && echo \"done\""
wrapped = keep_open(COMMAND)

for name, build in TERMINALS:
    argv = build(wrapped)

    if not isinstance(argv, list) or not argv:
        problems.append("%s: builder did not return a non-empty list" % name)
        continue
    if not all(isinstance(a, str) for a in argv):
        problems.append("%s: argv is not all strings: %r" % (name, argv))
        continue
    if os.path.basename(argv[0]) != name:
        problems.append("%s: argv starts with %r" % (name, argv[0]))
    if wrapped not in argv:
        problems.append("%s: the command is not in argv intact" % name)

    # The wrapper is handed to `bash -c` (or to the terminal's own shell), so
    # it has to parse. -n parses without running a single line of it.
    check = subprocess.run(["bash", "-n", "-c", wrapped],
                           capture_output=True, text=True)
    if check.returncode != 0:
        problems.append("%s: the wrapped command is not valid bash: %s"
                        % (name, check.stderr.strip()))

# The wrapper's whole job is holding the window open afterwards, both ways.
if "read -r -p" not in wrapped:
    problems.append("the wrapper does not wait for a keypress at the end")
if "status" not in wrapped:
    problems.append("the wrapper does not report the command's exit status")

# And it must not swallow a failure: bash -e would abort the wrapper before the
# read, leaving exactly the disappearing window this exists to prevent.
#
# Probed with an external command that fails, which is the real shape — a bare
# `exit 3` would end the wrapper's own shell rather than model install.sh dying.
probe = subprocess.run(
    ["bash", "-c", keep_open("bash -c 'exit 3'") + "\n"],
    capture_output=True, text=True, stdin=subprocess.DEVNULL)
if "Exited with status 3" not in probe.stdout:
    problems.append("a failing command does not report its status: %r"
                    % probe.stdout)

probe_ok = subprocess.run(["bash", "-c", keep_open("true") + "\n"],
                          capture_output=True, text=True,
                          stdin=subprocess.DEVNULL)
if "Finished." not in probe_ok.stdout:
    problems.append("a successful command does not say so: %r"
                    % probe_ok.stdout)

if problems:
    print("terminal spawn check FAILED\n")
    for problem in problems:
        print("  " + problem)
    print("\n%d problem%s" % (len(problems), "" if len(problems) == 1 else "s"))
    sys.exit(1)

print("terminal spawn check passed — %d terminals build a runnable command line"
      % len(TERMINALS))
