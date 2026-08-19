#!/usr/bin/env python3
"""Assert the setup wizard builds install.sh arguments install.sh accepts.

gui/aura_glass_setup_wizard.py is a front end for install.sh's flags: it asks
the opening questions in a window, prints a command line, and install.sh parses
it with the same code that parses a hand-typed one. Everything downstream is
therefore only as correct as that command line, and a wizard that composes a
list install.sh rejects has turned a working install into an error message
before a single file was written.

So this checks four things:

  composition — the exact argument list for a set of answers. Reading these
      cases is the fastest way to see what pressing Install will do.

  acceptance — every one of those lists is then fed to install.sh
      --settings-only --dry-run, which parses and resolves it against the real
      rules and changes nothing.

  wiring — the page list, the per-page Skip fields and the page builders are
      three hand-written tables that name each other by string. A typo in any
      of them is a Skip button that silently does nothing, or a Next that
      raises. Nothing else would catch that until someone clicked it.

  links — the icon and pointer pack URLs, against lib/steps.sh's clone pins.
      The window offers to open somebody else's project; it should be the one
      the installer is about to clone.

Run it after changing Answers.to_argv, after changing the pages, and after
changing any flag in install.sh that the wizard sends.
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "gui"))

try:
    import gi  # noqa: F401
except ImportError:
    print("check-wizard-flags: PyGObject is not installed — skipping (the "
          "wizard is optional, and install.sh asks in the terminal on this "
          "machine too)")
    sys.exit(0)

import aura_glass_setup_wizard as wiz  # noqa: E402

failures = []

# Every answer has to come from a default rather than from a memo, or the cases
# below would say something different on a machine that has aura-glass on it.
_EMPTY = tempfile.TemporaryDirectory()
wiz.CONF_DIR = _EMPTY.name

RECOMMENDED = ["just-perfection-desktop@just-perfection",
               "gnome-ui-tune@itstime.tech"]


def answers(**kw):
    """An Answers with fields overridden, and no disk behind it."""
    state = wiz.Answers(kw.pop("extensions", None))
    for field, value in kw.items():
        if not hasattr(state, field):
            failures.append("case built with an unknown field %r" % field)
        setattr(state, field, value)
    return state


# The font rides with the accent because to_argv states both on every run, and
# it is second because that is the order to_argv writes them in.
BASE = ["--accent", "purple", "--font", "system"]
FROSTED = ["--gtk-apps-blur", "--app-transparency", "0.90", "--popup-blur"]
# The wizard's recommended pair, which is not install.sh's flagless default —
# the wizard states its answer on every run rather than leaving the packs to the
# installer, so these are the two names the defaults case has to send.
PACKS = ["--icons", "reversal", "--cursors", "aosp", "--osd"]

# (description, the answers, whether there is a GDM, expected argv)
CASES = [
    # What "Skip all, use defaults" on the welcome page sends. Every flag the
    # wizard covers goes out on every run, so this is also the shape of all the
    # others: this list minus the parts a page changed.
    ("defaults, no login manager", answers(), False,
     BASE + FROSTED + PACKS),

    # The two GDM flags appear only where install.sh found a GDM to theme, and
    # both are stated rather than left out: the page has two switches and an
    # untouched switch is an answer.
    ("defaults, with a login manager", answers(), True,
     BASE + FROSTED + PACKS + ["--no-gdm", "--no-gdm-monitors"]),

    ("accent only", answers(accent="teal"), False,
     ["--accent", "teal", "--font", "system"] + FROSTED + PACKS),

    # The font rows on the accent page. system is the default and is still
    # stated; the other three name themselves, and install.sh downloads
    # whichever one is named if it is not already on the machine.
    ("a font of its own", answers(font="inter"), False,
     ["--accent", "purple", "--font", "inter"] + FROSTED + PACKS),

    # Solid mode is the absence of every blur, and install.sh rejects --no-blur
    # beside any blur flag by design. This is the case that says the wizard
    # cannot produce that combination.
    ("solid", answers(blur=False), False,
     BASE + ["--no-blur"] + PACKS),

    ("solid keeps its own packs", answers(blur=False, want_icons=False), False,
     BASE + ["--no-blur", "--no-icons", "--cursors", "aosp", "--osd"]),

    ("every window blurred", answers(scope="all"), False,
     BASE + ["--all-apps-blur", "--app-transparency", "0.90", "--popup-blur"]
     + PACKS),

    # The transparency has to follow the scope flag rather than precede it:
    # --no-window-blur picks 0.95 for itself only when nothing explicit has
    # already said one, so the order here is the thing being asserted.
    ("no window blur", answers(scope="none", transparency="0.95"), False,
     BASE + ["--no-window-blur", "--app-transparency", "0.95", "--popup-blur"]
     + PACKS),

    ("flat popups", answers(popup_blur=False), False,
     BASE + ["--gtk-apps-blur", "--app-transparency", "0.90", "--no-popup-blur"]
     + PACKS),

    ("deeper glass", answers(transparency="0.82"), False,
     BASE + ["--gtk-apps-blur", "--app-transparency", "0.82", "--popup-blur"]
     + PACKS),

    ("hatter icons and mactahoe pointers",
     answers(icons="hatter", cursors="mactahoe"), False,
     BASE + FROSTED + ["--icons", "hatter", "--cursors", "mactahoe", "--osd"]),

    ("keep both packs", answers(want_icons=False, want_cursors=False), False,
     BASE + FROSTED + ["--no-icons", "--no-cursors", "--osd"]),

    ("stock OSD", answers(want_osd=False), False,
     BASE + FROSTED + ["--icons", "reversal", "--cursors", "aosp",
                       "--no-osd"]),

    # A catalogue that could not be read leaves this None, which sends no
    # --extensions at all and leaves install.sh on its own recommended pack.
    # That is the fallback, and it has to stay expressible.
    ("no catalogue, no --extensions", answers(extensions=None), False,
     BASE + FROSTED + PACKS),

    ("some extensions", answers(extensions=list(RECOMMENDED)), False,
     BASE + FROSTED + PACKS + ["--extensions", ",".join(RECOMMENDED)]),

    # Every switch off is a minimal install said the long way round. install.sh
    # resolves an empty list to --no-extras rather than to a pack.
    ("no extensions", answers(extensions=[]), False,
     BASE + FROSTED + PACKS + ["--extensions", ""]),

    ("the login screen, themed",
     answers(gdm=True, gdm_monitors=True), True,
     BASE + FROSTED + PACKS + ["--gdm", "--gdm-monitors"]),
]

for label, state, gdm, want in CASES:
    got = state.to_argv(gdm)
    if got != want:
        failures.append("composition: %s\n      want: %s\n      got:  %s"
                        % (label, want, got))

# Stated as its own assertion rather than left implied by the solid cases: no
# argument list may ever ask for no blur and for a blur.
NO_BLUR_CONFLICTS = {"--window-blur", "--gtk-apps-blur", "--all-apps-blur",
                     "--all-app-blur", "--gtk-app-blur", "--app-transparency"}
for label, state, gdm, _want in CASES:
    args = set(state.to_argv(gdm))
    if "--no-blur" in args and NO_BLUR_CONFLICTS & args:
        failures.append("contradiction: %s emitted --no-blur with a blur flag: "
                        "%s" % (label, sorted(NO_BLUR_CONFLICTS & args)))


# ---- wiring -----------------------------------------------------------------
#
# Answers, the page list, the Skip table and the page builders are separate
# hand-written things that refer to each other by name. py_compile cannot see a
# getattr, so none of these would fail until a person clicked the button.
def check_wiring():
    fields = set(vars(wiz.Answers(None)))

    for tag, names in wiz.PAGE_FIELDS.items():
        if tag not in wiz.PAGES:
            failures.append("wiring: PAGE_FIELDS has %r, which is not a page"
                            % tag)
        unknown = [n for n in names if n not in fields]
        if unknown:
            failures.append(
                "wiring: Skip on the %s page would restore %s, which Answers "
                "does not have — the button would do nothing"
                % (tag, ", ".join(unknown)))

    for tag in wiz.PAGES:
        builder = "page_" + tag.replace("-", "_")
        if not hasattr(wiz.Window, builder):
            failures.append("wiring: no Window.%s, so reaching the %s page "
                            "raises" % (builder, tag))
        # Welcome has Get Started and Summary has Install; everything between
        # them is a question, and every question is skippable by design.
        if tag not in ("welcome", "summary") and tag not in wiz.PAGE_FIELDS:
            failures.append("wiring: the %s page has a Skip button but no "
                            "PAGE_FIELDS entry, so Skip keeps whatever was "
                            "clicked instead of the default" % tag)


check_wiring()


# ---- links ------------------------------------------------------------------
def check_links():
    with open(os.path.join(ROOT, "lib", "steps.sh"), encoding="utf-8") as fh:
        steps = fh.read()
    # The AOSP pointers are absent on purpose: install.sh fetches a release
    # tarball rather than cloning them, so there is no *_REPO to compare the
    # wizard's link against.
    for pack, var in (("colloid", "COLLOID_REPO"),
                      ("reversal", "REVERSAL_REPO"),
                      ("hatter", "HATTER_REPO"),
                      ("mactahoe", "MACTAHOE_REPO")):
        found = re.search(r'^%s="([^"]+)"' % var, steps, re.M)
        if not found:
            failures.append("links: lib/steps.sh no longer sets %s" % var)
            continue
        pinned = found.group(1)[:-4] if found.group(1).endswith(".git") \
            else found.group(1)
        if wiz.PACK_LINKS.get(pack) != pinned:
            failures.append(
                "links: the wizard sends people to %s for %s, but install.sh "
                "clones %s" % (wiz.PACK_LINKS.get(pack), pack, pinned))


check_links()

# Acceptance. --dry-run resolves and prints without writing anything, so this
# runs against the real installer on a real machine and still changes nothing.
if os.path.isdir(os.path.join(os.path.expanduser("~"), ".themes", "Tahoe-Dark")):
    for label, state, gdm, _want in CASES:
        args = state.to_argv(gdm)
        argv = ["bash", os.path.join(ROOT, "install.sh"),
                "--settings-only", "--dry-run", "--yes"] + args
        res = subprocess.run(argv, capture_output=True, text=True)
        if res.returncode != 0:
            tail = (res.stderr or res.stdout).strip().splitlines()
            failures.append("acceptance: install.sh rejected the list for %s\n"
                            "      args: %s\n      %s"
                            % (label, args, tail[-1] if tail else "(no output)"))

    # The other half of --extensions: a UUID that is not in the catalogue has to
    # be refused rather than fetched, looked for, and reported as an extension
    # upstream no longer carries.
    res = subprocess.run(
        ["bash", os.path.join(ROOT, "install.sh"), "--settings-only",
         "--dry-run", "--yes", "--extensions", "not-a-real@extension"],
        capture_output=True, text=True)
    if res.returncode == 0:
        failures.append("acceptance: install.sh accepted --extensions with a "
                        "UUID that is not in the catalogue")
else:
    print("check-wizard-flags: no ~/.themes/Tahoe-Dark — composition only, "
          "skipping the install.sh acceptance half")

if failures:
    print("wizard flag check FAILED\n")
    for problem in failures:
        print("  " + problem)
    print("\n%d problem%s" % (len(failures), "" if len(failures) == 1 else "s"))
    sys.exit(1)

print("wizard flag check passed — %d answer set%s compose and parse"
      % (len(CASES), "" if len(CASES) == 1 else "s"))
