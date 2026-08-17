#!/usr/bin/env python3
"""Assert the settings window builds install.sh arguments install.sh accepts.

gui/aura_glass_settings.py sends only the flags that changed, which keeps it out
of the business of resolving precedence — but it puts it squarely in the business
of not emitting a combination install.sh refuses. There is at least one: passing
--no-blur alongside --window-blur is a hard error by design, because whichever
way it were silently resolved would be the opposite of what half the people
writing it meant.

So this checks two different things:

  composition — the exact argument list for a set of transitions, including the
      ones where a flag has to be restated because another flag moved it. Reading
      these cases is the fastest way to see what Apply will do.

  acceptance — every one of those lists is then fed to install.sh --settings-only
      --dry-run, which parses and resolves it against the real precedence rules
      and changes nothing. A list that composes as expected but dies in the
      parser is still broken, and only the second half can tell.

Run it after changing flags_against, and after changing any flag in install.sh
that the window sends.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "gui"))

try:
    import gi  # noqa: F401
except ImportError:
    print("check-gui-flags: PyGObject is not installed — skipping (the settings "
          "window is optional, and install.sh skips it on this machine too)")
    sys.exit(0)

from aura_glass_settings import Settings  # noqa: E402


def state(**kw):
    """A Settings without touching the disk."""
    s = Settings.__new__(Settings)
    s.accent = kw.get("accent", "purple")
    s.radius = kw.get("radius", "default")
    s.radius_custom = kw.get("radius_custom", (30, 26, 33, 20, 20, 20, 12))
    s.blur = kw.get("blur", True)
    s.transparency = kw.get("transparency", "0.90")
    s.scope = kw.get("scope", "gtk")
    s.popup_blur = kw.get("popup_blur", True)
    s.allow = list(kw.get("allow", ["org.gnome.Nautilus", "org.gnome.Console"]))
    s.block = list(kw.get("block", ["*chrome*", "*electron*"]))
    s.icons = kw.get("icons", "colloid")
    s.cursors = kw.get("cursors", "adwaita")
    s.window_buttons = kw.get("window_buttons", "")
    s.update_check = kw.get("update_check", True)
    s.update_available = kw.get("update_available", None)
    return s


FROSTED = state()
SOLID = state(blur=False)

# (description, state on disk, state the widgets are asking for, expected argv)
CASES = [
    ("nothing touched", FROSTED, state(), []),

    ("radius only", FROSTED, state(radius="pill"),
     ["--radius-preset", "pill"]),

    # --radius-custom implies the custom preset, so it stands in for
    # --radius-preset rather than joining it.
    ("seven radii of your own", FROSTED,
     state(radius="custom", radius_custom=(20, 18, 22, 14, 14, 14, 8)),
     ["--radius-custom", "20,18,22,14,14,14,8"]),

    # "custom" says nothing about which custom, so moving one surface has to go
    # out even though the preset name did not change.
    ("one surface moved inside custom",
     state(radius="custom", radius_custom=(20, 18, 22, 14, 14, 14, 8)),
     state(radius="custom", radius_custom=(20, 18, 22, 14, 14, 14, 12)),
     ["--radius-custom", "20,18,22,14,14,14,12"]),

    ("custom back to a named preset",
     state(radius="custom", radius_custom=(20, 18, 22, 14, 14, 14, 8)),
     state(radius="rounded"), ["--radius-preset", "rounded"]),

    ("the same seven values twice is not a change",
     state(radius="custom", radius_custom=(20, 18, 22, 14, 14, 14, 8)),
     state(radius="custom", radius_custom=(20, 18, 22, 14, 14, 14, 8)), []),

    ("accent only", FROSTED, state(accent="teal"),
     ["--accent", "teal"]),

    ("accent and radius together", FROSTED, state(accent="red", radius="sharp"),
     ["--accent", "red", "--radius-preset", "sharp"]),

    # Solid mode is the absence of every blur, so it must go out alone. The blur
    # flags are not redundant here, they are the combination install.sh rejects.
    ("frosted -> solid", FROSTED, state(blur=False), ["--no-blur"]),

    ("frosted -> solid, with a radius change", FROSTED,
     state(blur=False, radius="sharp"),
     ["--radius-preset", "sharp", "--no-blur"]),

    # Coming back, every blur setting has to be restated: --no-blur was not
    # remembered (deliberately — see apply_popup_blur), so nothing on disk says
    # what the window is showing.
    ("solid -> frosted restates every blur setting", SOLID, state(),
     ["--blur", "--gtk-apps-blur", "--app-transparency", "0.90",
      "--popup-blur"]),

    ("scope to all apps restates the level", FROSTED, state(scope="all"),
     ["--all-apps-blur", "--app-transparency", "0.90"]),

    # --no-window-blur moves the level to 0.95 on its own unless the level is
    # given, so the level always follows it.
    ("scope to none restates the level", FROSTED, state(scope="none"),
     ["--no-window-blur", "--app-transparency", "0.90"]),

    ("level only", FROSTED, state(transparency="0.82"),
     ["--app-transparency", "0.82"]),

    ("level off", FROSTED, state(transparency="0"),
     ["--no-app-transparency"]),

    ("popup blur off", FROSTED, state(popup_blur=False), ["--no-popup-blur"]),

    # The per-app lists. Whichever one changed goes out, whether or not the mode
    # in force consults it. The window edits both at all times — they are two
    # memos that survive every mode switch — and apply_app_blur writes both keys
    # every run, so an edit to the list that is idle right now has a real place
    # to be stored. Dropping it here would lose it at the next reload instead.
    ("allow list edited, in gtk mode", FROSTED,
     state(allow=["org.gnome.Nautilus"]),
     ["--app-blur-allow", "org.gnome.Nautilus"]),

    ("block list edited in gtk mode is still sent", FROSTED,
     state(block=["*chrome*"]), ["--app-blur-block", "*chrome*"]),

    ("block list edited, in all mode", FROSTED,
     state(scope="all", block=["*chrome*", "*firefox*"]),
     ["--all-apps-blur", "--app-transparency", "0.90",
      "--app-blur-block", "*chrome*,*firefox*"]),

    ("allow list edited in all mode is still sent", FROSTED,
     state(scope="all", allow=["org.gnome.Nautilus"]),
     ["--all-apps-blur", "--app-transparency", "0.90",
      "--app-blur-allow", "org.gnome.Nautilus"]),

    ("both lists edited at once", FROSTED,
     state(allow=["org.gnome.Nautilus"], block=["*chrome*"]),
     ["--app-blur-allow", "org.gnome.Nautilus",
      "--app-blur-block", "*chrome*"]),

    ("emptying the allow list is a real change", FROSTED,
     state(allow=[]), ["--app-blur-allow", ""]),

    # The titlebar buttons. Empty is the default and means the key is not ours
    # to write, so it is the one value that never produces a flag — there is no
    # way back to "no opinion" once one has been applied, and inventing GNOME's
    # own default as the way back would assert a layout over whatever the user
    # had before.
    ("window buttons to close only", FROSTED, state(window_buttons="close"),
     ["--window-buttons", "close"]),

    ("window buttons to all three", FROSTED, state(window_buttons="all"),
     ["--window-buttons", "all"]),

    ("window buttons back to leaving it alone sends nothing",
     state(window_buttons="close"), state(window_buttons=""), []),

    ("window buttons alongside an accent", FROSTED,
     state(window_buttons="all", accent="teal"),
     ["--accent", "teal", "--window-buttons", "all"]),

    # The family goes out bare, so install.sh maps it to a colour Reversal
    # ships. Naming the colour here would need a second copy of that mapping —
    # and would reintroduce reversal-teal, which does not exist.
    ("reversal icons", FROSTED, state(icons="reversal"),
     ["--icons", "reversal"]),

    ("reversal icons and a new accent together", FROSTED,
     state(icons="reversal", accent="teal"),
     ["--accent", "teal", "--icons", "reversal"]),

    # Family and colour are one value, because --icons is one flag. A colour
    # named here is one the user picked; a bare family still means "follow the
    # accent" and leaves that mapping to lib/steps-assets.sh.
    ("colloid in a colour of its own", FROSTED, state(icons="colloid-teal"),
     ["--icons", "colloid-teal"]),

    ("a colour Reversal has and the accents do not", FROSTED,
     state(icons="reversal-brown"), ["--icons", "reversal-brown"]),

    ("icon colour back to following the accent",
     state(icons="colloid-teal"), state(icons="colloid"),
     ["--icons", "colloid"]),

    ("an icon colour that is not the accent", FROSTED,
     state(icons="colloid-teal", accent="pink"),
     ["--accent", "pink", "--icons", "colloid-teal"]),

    # "Keep current" and "Original" are different answers: keep is --no-icons,
    # a choice not to touch whatever is set now, and original goes back to the
    # snapshot preflight took before aura-glass first ran.
    ("icons back to the ones from before aura-glass", FROSTED,
     state(icons="original"), ["--icons", "original"]),

    ("pointer back to the one from before aura-glass", FROSTED,
     state(cursors="original"), ["--cursors", "original"]),

    ("original is not the same as keeping the current one",
     state(icons="original"), state(icons="keep"), ["--no-icons"]),

    ("keep the icons as they are", FROSTED, state(icons="keep"), ["--no-icons"]),

    ("mactahoe pointer", FROSTED, state(cursors="mactahoe"),
     ["--cursors", "mactahoe"]),

    ("keep the pointer", FROSTED, state(cursors="keep"), ["--no-cursors"]),

    ("turn the daily update check off", FROSTED, state(update_check=False),
     ["--no-update-check"]),

    # A pending update is a fact about the remote, not a setting — it must never
    # turn into a flag, or opening the window during a release would start
    # sending arguments nobody chose.
    ("a pending update is not a setting", FROSTED,
     state(update_available="v9.9.9"), []),

    ("everything at once", FROSTED,
     state(accent="slate", radius="rounded", transparency="0.82", scope="all",
           popup_blur=False),
     ["--accent", "slate", "--radius-preset", "rounded", "--all-apps-blur",
      "--app-transparency", "0.82", "--no-popup-blur"]),
]

failures = []

# Every case above builds a Settings with __new__ and fills it in by hand, which
# is what makes them fast and independent of the machine — and is exactly why
# they cannot see a field that Settings.__init__ forgets to set. Two shipped
# crashes came through that gap: the window read self._applied.update_check on a
# Settings whose __init__ never assigned it, and py_compile cannot see an
# attribute that is only ever set at runtime.
#
# So build one for real, against a $CONF_DIR that holds nothing, and require it
# to carry every field the hand-built ones do. An empty directory is the strict
# case: every value has to come from a default rather than from a memo.
def check_real_settings():
    import tempfile

    import aura_glass_settings as mod

    expected = set(vars(state()))
    original = mod.CONF_DIR
    try:
        with tempfile.TemporaryDirectory() as empty:
            mod.CONF_DIR = empty
            try:
                real = mod.Settings()
            except Exception as exc:                     # noqa: BLE001
                failures.append("real Settings: __init__ raised on an empty "
                                "config directory: %r" % exc)
                return
            missing = expected - set(vars(real))
            if missing:
                failures.append(
                    "real Settings: __init__ never sets %s — the window reads "
                    "these, so opening it would raise AttributeError"
                    % ", ".join(sorted(missing)))
            # flags_against touches every field; against itself it must be empty
            # rather than raising.
            try:
                if real.flags_against(real):
                    failures.append("real Settings: differs from itself")
            except AttributeError as exc:
                failures.append("real Settings: flags_against raised %r" % exc)
    finally:
        mod.CONF_DIR = original


check_real_settings()

for label, base, target, want in CASES:
    got = target.flags_against(base)
    if got != want:
        failures.append("composition: %s\n      want: %s\n      got:  %s"
                        % (label, want, got))

# The contradiction, stated as its own assertion rather than left implied by the
# solid-mode cases: no argument list may ever ask for no blur and for a blur.
NO_BLUR_CONFLICTS = {"--window-blur", "--gtk-apps-blur", "--all-apps-blur",
                     "--all-app-blur", "--gtk-app-blur"}
for label, _, target, _want in CASES:
    for base in (FROSTED, SOLID, state(scope="none"), state(transparency="0")):
        args = target.flags_against(base)
        if "--no-blur" in args and NO_BLUR_CONFLICTS & set(args):
            failures.append("contradiction: %s (from %s) emitted --no-blur with "
                            "a blur flag: %s" % (label, base.__dict__, args))

# Acceptance. --dry-run resolves and prints without writing anything, so this
# runs against the real installer on a real machine and still changes nothing.
if os.path.isdir(os.path.join(os.path.expanduser("~"), ".themes", "Tahoe-Dark")):
    for label, base, target, _want in CASES:
        args = target.flags_against(base)
        argv = ["bash", os.path.join(ROOT, "install.sh"),
                "--settings-only", "--dry-run", "--yes"] + args
        res = subprocess.run(argv, capture_output=True, text=True)
        if res.returncode != 0:
            tail = (res.stderr or res.stdout).strip().splitlines()
            failures.append("acceptance: install.sh rejected the list for %s\n"
                            "      args: %s\n      %s"
                            % (label, args, tail[-1] if tail else "(no output)"))
else:
    print("check-gui-flags: no ~/.themes/Tahoe-Dark — composition only, "
          "skipping the install.sh acceptance half")

# The transparency bar can land on any whole percent, and each one has to reach
# both halves of the same setting: the alpha inside a GTK4 window, and the
# compositor opacity that is all an Electron or browser window has. They drifted
# apart for every value outside the three buckets until the memo read in
# install.sh was guarded — the stylesheet moved and the actor stayed where it was
# last remembered. Nothing in the window could show that; only a window that is
# half one level and half another, on a machine with both kinds of app open.
if os.path.isdir(os.path.join(os.path.expanduser("~"), ".themes", "Tahoe-Dark")):
    LEVEL = re.compile(r"rewrite the transparency sheet to ([0-9.]+)")
    ACTOR = re.compile(r"actor opacity set to (\d+)")
    for percent in (70, 75, 82, 88, 90, 93, 95, 100):
        level = "%.2f" % (percent / 100.0)
        res = subprocess.run(
            ["bash", os.path.join(ROOT, "install.sh"), "--settings-only",
             "--dry-run", "--yes", "--app-transparency", level],
            capture_output=True, text=True)
        out = res.stdout + res.stderr
        got_level, got_actor = LEVEL.search(out), ACTOR.search(out)
        if not (got_level and got_actor):
            failures.append("ladder: install.sh reported no level or no actor "
                            "opacity for %s%%" % percent)
            continue
        # install.sh snaps a value that rounds onto a bucket's actor opacity, so
        # allow the bucket's own number as well as the exact arithmetic one.
        want = round(float(got_level.group(1)) * 255)
        if abs(int(got_actor.group(1)) - want) > 1:
            failures.append(
                "ladder: at %s%% the stylesheet is %s but the actor opacity is "
                "%s, which is %s rather than the %s that level means"
                % (percent, got_level.group(1), got_actor.group(1),
                   round(int(got_actor.group(1)) / 255 * 100), percent))

if failures:
    print("gui flag check FAILED\n")
    for f in failures:
        print("  " + f)
    print("\n%d problem%s" % (len(failures), "" if len(failures) == 1 else "s"))
    sys.exit(1)

print("gui flag check passed — %d transition%s compose and parse"
      % (len(CASES), "" if len(CASES) == 1 else "s"))
