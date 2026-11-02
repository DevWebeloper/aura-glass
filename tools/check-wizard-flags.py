#!/usr/bin/env python3
"""Assert the setup wizard builds install.sh arguments install.sh accepts.

gui/aura_glass_setup_wizard.py is a front end for install.sh's flags: it asks
the opening questions in a window, prints a command line, and install.sh parses
it with the same code that parses a hand-typed one. Everything downstream is
therefore only as correct as that command line, and a wizard that composes a
list install.sh rejects has turned a working install into an error message
before a single file was written.

So this checks eight things:

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

  accent colours — the swatch hex for each accent, against accent_hex in
      lib/steps-dconf.sh, which tints the tinted glass style with it.

  opacity bar — its range, marks and snap, against the settings window's.

  pointer size — the size recommended for each kind of display.

  previews — every outline, pointer and icon the window shows of something it has not
      installed yet is in gui/samples/, and the two OSD designs it draws still have
      the numbers css/shell-00-flat.css gives them.

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

RECOMMENDED = ["status-tray@keithvassallo.com",
               "tiling-assistant@leleat-on-github"]

# A small stand-in catalogue for Answers.best, covering all three tiers so the
# case below can assert core is excluded and the other two are not.
BEST_CATALOGUE = [
    {"uuid": "user-theme@gnome-shell-extensions.gcampax.github.com",
     "tier": "core"},
    {"uuid": "status-tray@keithvassallo.com",
     "tier": "recommended"},
    {"uuid": "restartto@tiagoporsch.github.io", "tier": "full"},
]
BEST_EXTENSIONS = ["status-tray@keithvassallo.com",
                   "restartto@tiagoporsch.github.io"]


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
FROSTED = ["--glass-mode", "frosted", "--all-apps-blur", "--app-transparency",
           "0.90", "--popup-blur"]
# The wizard's recommended pair, which is not install.sh's flagless default —
# the wizard states its answer on every run rather than leaving the packs to the
# installer, so these are the two names the defaults case has to send. The size
# is a third, independent answer — 32px until the window has asked the display.
PACKS = ["--icons", "reversal", "--system-icons", "lucide", "--cursors", "moga", "--cursor-size", "32",
         "--osd", "--no-osd-device-name",
                       "--osd-style", "capsule"]

# (description, the answers, whether there is a GDM, expected argv)
CASES = [
    # What "Skip all, use defaults" on the welcome page sends. Every flag the
    # wizard covers goes out on every run, so this is also the shape of all the
    # others: this list minus the parts a page changed.
    ("defaults, no login manager", answers(), False,
     BASE + FROSTED + PACKS),

    # The two GDM flags appear only where install.sh found a GDM to theme, and
    # both are stated rather than left out: the page has two switches, both on
    # until turned off, and an untouched switch is an answer.
    ("defaults, with a login manager", answers(), True,
     BASE + FROSTED + PACKS + ["--gdm", "--gdm-monitors"]),

    ("the login screen left alone", answers(gdm=False, gdm_monitors=False), True,
     BASE + FROSTED + PACKS + ["--no-gdm", "--no-gdm-monitors"]),

    ("accent only", answers(accent="teal"), False,
     ["--accent", "teal", "--font", "system"] + FROSTED + PACKS),

    # The font rows on the accent page. system is the default and is still
    # stated; the other three name themselves, and install.sh downloads
    # whichever one is named if it is not already on the machine.
    ("a font of its own", answers(font="inter"), False,
     ["--accent", "purple", "--font", "inter"] + FROSTED + PACKS),

    # Always frosted, whichever cards were picked: nothing the window can
    # produce says --no-blur or --no-window-blur any more.
    ("gtk windows blurred", answers(scope="gtk"), False,
     BASE + ["--glass-mode", "frosted", "--gtk-apps-blur", "--app-transparency",
             "0.90", "--popup-blur"]
     + PACKS),

    ("deeper glass", answers(transparency="0.82"), False,
     BASE + ["--glass-mode", "frosted", "--all-apps-blur", "--app-transparency",
             "0.82", "--popup-blur"]
     + PACKS),

    ("hatter icons and mactahoe pointers",
     answers(icons="hatter", cursors="mactahoe"), False,
     BASE + FROSTED + ["--icons", "hatter", "--system-icons", "lucide", "--cursors", "mactahoe",
                       "--cursor-size", "32", "--osd", "--no-osd-device-name",
                       "--osd-style", "capsule"]),
    ("aosp pointers", answers(cursors="aosp"), False,
     BASE + FROSTED + ["--icons", "reversal", "--system-icons", "lucide", "--cursors", "aosp",
                       "--cursor-size", "32", "--osd", "--no-osd-device-name",
                       "--osd-style", "capsule"]),

    ("keep both packs", answers(want_icons=False, want_cursors=False), False,
     BASE + FROSTED + ["--no-icons", "--no-cursors", "--cursor-size", "32",
                       "--osd", "--no-osd-device-name",
                       "--osd-style", "capsule"]),

    # Independent of the pack above: keeping the pointer theme is not a
    # statement about its size, and the reverse holds too.
    ("keep the pointer size, theme untouched",
     answers(cursor_size="24", want_cursor_size=False), False,
     BASE + FROSTED + ["--icons", "reversal", "--system-icons", "lucide", "--cursors", "moga", "--osd", "--no-osd-device-name",
                       "--osd-style", "capsule"]),

    ("a larger pointer, theme unchanged",
     answers(cursor_size="48"), False,
     BASE + FROSTED + ["--icons", "reversal", "--system-icons", "lucide", "--cursors", "moga",
                       "--cursor-size", "48", "--osd", "--no-osd-device-name",
                       "--osd-style", "capsule"]),

    ("OSD pill naming its device", answers(osd_device_name=True), False,
     BASE + FROSTED + ["--icons", "reversal", "--system-icons", "lucide", "--cursors", "moga",
                       "--cursor-size", "32", "--osd", "--osd-device-name",
                       "--osd-style", "capsule"]),

    ("the pack's own system icons", answers(system_icons="pack"), False,
     BASE + FROSTED + ["--icons", "reversal", "--system-icons", "pack",
                       "--cursors", "moga", "--cursor-size", "32", "--osd",
                       "--no-osd-device-name", "--osd-style", "capsule"]),
    ("the top bar tab", answers(osd_style="tab"), False,
     BASE + FROSTED + ["--icons", "reversal", "--system-icons", "lucide", "--cursors", "moga",
                       "--cursor-size", "32", "--osd", "--no-osd-device-name",
                       "--osd-style", "tab"]),
    ("stock OSD", answers(want_osd=False), False,
     BASE + FROSTED + ["--icons", "reversal", "--system-icons", "lucide", "--cursors", "moga",
                       "--cursor-size", "32", "--no-osd"]),

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

    # Answers.best, the welcome page's "Best experience" button. Extensions
    # come from the catalogue (core excluded — install.sh installs that
    # regardless of --extensions) rather than from the answers() helper's
    # __init__ defaults, so these three go straight to to_argv.
    ("best, no login manager",
     wiz.Answers.best(BEST_CATALOGUE, False, False), False,
     BASE + FROSTED + PACKS + ["--extensions", ",".join(BEST_EXTENSIONS)]),

    ("best, with a login manager, one display",
     wiz.Answers.best(BEST_CATALOGUE, True, False), True,
     BASE + FROSTED + PACKS
     + ["--extensions", ",".join(BEST_EXTENSIONS), "--gdm",
        "--no-gdm-monitors"]),

    ("best, with a login manager, several displays",
     wiz.Answers.best(BEST_CATALOGUE, True, True), True,
     BASE + FROSTED + PACKS
     + ["--extensions", ",".join(BEST_EXTENSIONS), "--gdm", "--gdm-monitors"]),
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


# ---- accent colours ---------------------------------------------------------
# The wizard's swatches and lib/steps-dconf.sh's accent_hex (the tinted glass
# style's colour) are two copies of libadwaita's nine accents. The swatch is
# what someone picks; the shell is then tinted with the other copy.
def check_accent_colours():
    for name, _label, swatch in wiz.ACCENTS:
        res = subprocess.run(
            ["bash", "-c", '. "$1/lib/steps-dconf.sh"; accent_hex "$2"',
             "_", ROOT, name], capture_output=True, text=True)
        got = res.stdout.strip()
        if res.returncode != 0 or "#" + got != swatch.lower():
            failures.append("accent colours: the wizard shows %s as %s, but "
                            "accent_hex tints the glass %s"
                            % (name, swatch, "#" + got if got else "(nothing)"))


check_accent_colours()


# ---- opacity bar ------------------------------------------------------------
# The wizard's bar is meant to be the settings window's bar: picking "deep" here
# has to land on "deep" there. Read from the source, because importing the
# settings window needs pycairo and this check does not.
def check_opacity_bar():
    with open(os.path.join(ROOT, "gui", "aura_glass_settings.py"),
              encoding="utf-8") as fh:
        settings = fh.read()
    marks = re.search(r"^TRANSPARENCY_MARKS = (\[.*?^\])", settings, re.M | re.S)
    if eval(marks.group(1)) != wiz.TRANSPARENCY_MARKS:  # our own source
        failures.append("opacity bar: the marks differ from the settings window")
    for name in ("TRANSPARENCY_MIN", "TRANSPARENCY_MAX", "TRANSPARENCY_SNAP"):
        found = re.search(r"^%s = (\d+)" % name, settings, re.M)
        if int(found.group(1)) != getattr(wiz, name):
            failures.append("opacity bar: %s differs from the settings window"
                            % name)


check_opacity_bar()


# ---- pointer size -----------------------------------------------------------
# (physical height, scale) -> size. 1440p is the baseline at any fractional
# scale; 4K at 200% is 1080p, because GNOME doubles the pointer by itself.
def check_cursor_sizes():
    offered = {size for size, _title, _sub in wiz.CURSOR_SIZES}
    for height, scale, want in ((1080, 1.0, "24"), (1200, 1.25, "24"),
                                (1440, 1.0, "32"), (1440, 1.33, "32"),
                                (1600, 1.67, "32"), (1600, 2.0, "24"),
                                (2160, 1.0, "48"), (2160, 1.5, "48"),
                                (2160, 2.0, "24")):
        got = wiz.cursor_size_for(height, scale)
        if got != want:
            failures.append("pointer size: %dp at %s gave %s, want %s"
                            % (height, scale, got, want))
        if got not in offered:
            failures.append("pointer size: %s is recommended but not offered"
                            % got)


check_cursor_sizes()


# ---- previews ---------------------------------------------------------------
# A missing outline falls back to a label in the system font, which would show
# every font as the same font, and a missing pointer draws an empty tile. Neither
# would raise, so nothing else would catch it.
def check_previews():
    samples = os.path.join(ROOT, "gui", "samples")
    for font, _title, _sub in wiz.FONTS:
        if font == "system":
            continue
        outlines = wiz.font_outlines(ROOT, font)
        for key in wiz.FONT_SAMPLES:
            if key not in outlines or wiz.Gsk.Path.parse(
                    outlines[key]["path"]) is None:
                failures.append("previews: %s has no usable outline of %s"
                                % (font, key))

    packs = ["moga-" + name for name, _label, _hex in wiz.ACCENTS]
    packs += ["aosp", "mactahoe"]
    for pack in packs:
        path = os.path.join(samples, "pointers", pack + ".xcursor.gz")
        try:
            if not wiz.read_pointer(path):
                failures.append("previews: %s holds no images" % path)
        except OSError as exc:
            failures.append("previews: %s" % exc)

    for pack in ("reversal", "hatter", "colloid"):
        for name in wiz.ICON_SAMPLES:
            for accent, _label, _hex in wiz.ACCENTS:
                folder = os.path.join(samples, "icons", pack)
                if not (os.path.isfile(os.path.join(folder, name + ".svg"))
                        or os.path.isfile(os.path.join(
                            folder, "%s-%s.svg" % (name, accent)))):
                    failures.append("previews: %s has no %s for %s"
                                    % (pack, name, accent))

    # The two popup designs against the sheet that draws them. See OSD_DESIGNS.
    with open(os.path.join(ROOT, "css", "shell-00-flat.css"),
              encoding="utf-8") as handle:
        sheet = handle.read()

    def declared(selector, prop):
        rule = re.search(r"^" + re.escape(selector) + r" \{([^}]*)\}", sheet, re.M)
        found = re.search(r"(?:^|\s)" + re.escape(prop) + r":\s*([^;]+);",
                          rule.group(1)) if rule else None
        return found.group(1).strip() if found else None

    base = ".osd-window.aura-osd-"
    want = {
        (base + "capsule", "width"): "%dpx" % wiz.OSD_DESIGNS["capsule"]["width"],
        (base + "capsule", "padding"): "%dpx %dpx" % (
            wiz.OSD_DESIGNS["capsule"]["padding_y"],
            wiz.OSD_DESIGNS["capsule"]["padding_x"]),
        (base + "capsule", "spacing"): "%dpx" % wiz.OSD_DESIGNS["capsule"]["gap"],
        (base + "capsule", "border-radius"):
            "%dpx" % wiz.OSD_DESIGNS["capsule"]["radius"],
        (base + "capsule > StBoxLayout", "spacing"):
            "%dpx" % wiz.OSD_DESIGNS["capsule"]["name_gap"],
        (base + "capsule StIcon", "icon-size"):
            "%dpx" % wiz.OSD_DESIGNS["capsule"]["icon"],
        (base + "capsule .level", "height"):
            "%dpx" % wiz.OSD_DESIGNS["capsule"]["thickness"],
        (base + "capsule StLabel", "font-size"):
            "%gpx" % wiz.FONT_SAMPLES["osd-capsule"][1],
        (base + "tab", "width"): "%dpx" % wiz.OSD_DESIGNS["tab"]["width"],
        (base + "tab", "height"): "%dpx" % wiz.OSD_DESIGNS["tab"]["height"],
        (base + "tab", "padding"): "0 %dpx" % wiz.OSD_DESIGNS["tab"]["padding_x"],
        (base + "tab", "spacing"): "%dpx" % wiz.OSD_DESIGNS["tab"]["gap"],
        (base + "tab", "border-radius"):
            "0 0 %dpx %dpx" % (wiz.OSD_DESIGNS["tab"]["radius"],
                               wiz.OSD_DESIGNS["tab"]["radius"]),
        (base + "tab StIcon", "icon-size"):
            "%dpx" % wiz.OSD_DESIGNS["tab"]["icon"],
        (base + "tab .level", "height"):
            "%dpx" % wiz.OSD_DESIGNS["tab"]["thickness"],
        (base + "tab .level", "width"): "%dpx" % wiz.OSD_DESIGNS["tab"]["bar"],
        (base + "tab StLabel", "font-size"):
            "%gpx" % wiz.FONT_SAMPLES["osd-tab"][1],
    }
    for (selector, prop), value in want.items():
        got = declared(selector, prop)
        if got != value:
            failures.append("previews: %s %s is %s in css, %s in the wizard"
                            % (selector, prop, got, value))
    if not wiz.osd_colours(ROOT)["fill"].startswith("rgba("):
        failures.append("previews: no [custom-osd] colours in dconf/core.ini")

    # The options the two front ends share.
    with open(os.path.join(ROOT, "gui", "aura_glass_settings.py"),
              encoding="utf-8") as handle:
        settings = handle.read()
    for _value, title, subtitle in wiz.OSD_STYLES + wiz.SYSTEM_ICONS:
        if not re.search(r'"%s",\s*"%s"' % (re.escape(title), re.escape(subtitle)),
                         settings):
            failures.append("previews: the settings window words %s differently"
                            % title)


check_previews()

# Acceptance. --dry-run resolves and prints without writing anything, so this
# runs against the real installer on a real machine and still changes nothing.
if any(os.path.isdir(os.path.join(os.path.expanduser("~"), ".themes", n))
       for n in ("Aura-Glass", "Tahoe-Dark")):
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
