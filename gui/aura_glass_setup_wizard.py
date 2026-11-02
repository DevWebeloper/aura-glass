#!/usr/bin/env python3
"""aura-glass — the opening questions, asked in a window.

install.sh runs this before it installs anything, walks the answers back into
its own flag parser, and carries on in the terminal. That is the whole of the
contract: this window does not install, configure, or write anything. It
composes a command line and prints it.

  stdout  the flags install.sh should run with, one token per line. Nothing
          else may ever be printed there — lib/steps-wizard.sh reads it.
  stderr  anything worth saying to a human.
  exit 0  answered.
  exit 2  cancelled, and install.sh stops. Closing the window is cancelling.
  else    something went wrong; install.sh asks the same questions in the
          terminal instead, so a traceback here costs a nicer wizard rather
          than the install.

  ┌─ PARITY ──────────────────────────────────────────────────────────────────┐
  │ Every question here has a twin in install.sh's text wizard (search for     │
  │ "Step 1: Choose Accent Color"), which is what runs where there is no       │
  │ display, no PyGObject, or no wish to install one. Adding a question to     │
  │ one and not the other is a setting that half the users on half the         │
  │ machines are never offered. Add it to both.                                │
  └───────────────────────────────────────────────────────────────────────────┘

Two deliberate differences from gui/aura_glass_settings.py, which is the other
window in this project:

  It runs before there is an install. The settings window refuses to open
  without $CONF_DIR and reconstructs the checkout path from a memo; this is
  handed --repo by the script that launched it, out of the checkout it is
  sitting in.

  install.sh blocks on it. The settings window spawns terminals it never waits
  for, because nothing downstream depends on them. Here the exit code and the
  stdout are the entire point — do not make this asynchronous.

It also deliberately does not import pycairo or anything else beyond PyGObject:
what lib/distro.sh probes for is what this is allowed to need. Gsk and Graphene
are not extra: Gtk 4 cannot load without them.
"""
import argparse
import collections
import configparser
import gzip
import json
import math
import os
import struct
import subprocess
import sys

import gi

gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")
gi.require_version("Gsk", "4.0")
gi.require_version("Graphene", "1.0")
from gi.repository import (  # noqa: E402
    Adw, Gdk, Gio, GLib, GObject, Graphene, Gsk, Gtk, Pango)

APP_ID = "io.github.DevWebeloper.AuraGlassSetup"

CONF_DIR = os.path.join(GLib.get_user_config_dir(), "aura-glass")

# The nine names install.sh accepts, in its order, with the colour libadwaita
# draws each one as.
#
# The hex values are for these swatches and nothing else. GNOME's accent is a
# read-only keyword backed by a nine-value enum rather than a colour anything
# can assign — tokens/tokens.sh:316 explains why at length, and why a custom
# hex is not on offer in either window. Nothing here sends a colour anywhere;
# it sends a name.
ACCENTS = [
    ("purple", "Purple", "#9141ac"),
    ("blue", "Blue", "#3584e4"),
    ("teal", "Teal", "#2190a4"),
    ("green", "Green", "#3a944a"),
    ("yellow", "Yellow", "#c88800"),
    ("orange", "Orange", "#ed5b00"),
    ("red", "Red", "#e62d42"),
    ("pink", "Pink", "#d56199"),
    ("slate", "Slate", "#6f8396"),
]

# The four answers install.sh's --font takes, with the download each one costs.
# The sizes are on the rows because this is the only question in the window that
# can start a 49M fetch, and a wizard that does not say so is a wizard that
# looks hung. The twin list is Step 3 of install.sh's text wizard.
FONTS = [
    ("system", "System default",
     "Whatever GNOME is using now, left alone"),
    ("misans", "MiSans",
     "Xiaomi's interface font — Latin and Arabic, 7 MB download"),
    ("inter", "Inter",
     "The screen-first grotesque — 34 MB download"),
    ("sf-pro", "San Francisco",
     "Apple's SF Pro, from a mirror — 49 MB download"),
]

# Every string the window shows in a font it may not have yet: (text, size in
# logical px, weight). Three of the four fonts arrive during the install, after
# this window has closed, so these exist as outlines in gui/samples/fonts/, and
# gui/samples/NOTICE.md says why. Change one here, then run
# gui/samples/render_samples.py. tools/check-wizard-flags.py fails on a missing
# outline.
#
# The sizes are the ones these strings have in the mock, which is smaller than
# life, and so are the -mock OSD lines. The others are life size: osd-capsule and
# osd-tab are .osd-window.aura-osd-capsule StLabel and its tab twin in
# css/shell-00-flat.css, which the check compares, and osd-stock is GNOME's own
# popup, bold in the shell's 11pt.
FONT_SAMPLES = {
    "aa": ("Aa", 17, "bold"),
    "line": ("The quick brown fox, 1234", 14, "normal"),
    "bar": ("Activities", 9, "bold"),
    "clock": ("Mon 10:42", 9, "bold"),
    "title-web": ("Browser", 9, "bold"),
    "title-files": ("Files", 9, "bold"),
    "side-home": ("Home", 8.5, "normal"),
    "side-photos": ("Photos", 8.5, "normal"),
    "side-music": ("Music", 8.5, "normal"),
    "heading": ("Recent", 10, "bold"),
    "osd-capsule": ("Speakers – Built-in Audio", 12.5, "medium"),
    "osd-tab": ("Speakers – Built-in Audio", 12, "normal"),
    "osd-stock": ("Speakers – Built-in Audio", 14.67, "bold"),
    "osd-capsule-mock": ("Speakers – Built-in Audio", 7.5, "medium"),
    "osd-tab-mock": ("Speakers – Built-in Audio", 7, "normal"),
}
SAMPLE_WEIGHTS = {"normal": Pango.Weight.NORMAL, "medium": Pango.Weight.MEDIUM,
                  "bold": Pango.Weight.BOLD}

# The volume and brightness popup's two designs, --osd-style. Fixed logical pixels
# copied from .osd-window.aura-osd-capsule and .osd-window.aura-osd-tab in
# css/shell-00-flat.css, because the window has to draw them before any of that is
# installed: nothing here follows the screen. tools/check-wizard-flags.py compares
# them, and the radii are also TOKEN_RADIUS_OSD_CAPSULE and TOKEN_RADIUS_OSD_TAB.
OSD_DESIGNS = {
    "capsule": {"width": 320, "padding_x": 16, "padding_y": 14, "gap": 13,
                "radius": 20, "icon": 20, "thickness": 12, "name_gap": 8},
    "tab": {"width": 360, "height": 38, "padding_x": 16, "gap": 10,
            "radius": 16, "icon": 16, "thickness": 6, "bar": 120},
}
# The same options, order and recommendation as Step 5 of the text wizard and
# OSD_STYLES in the settings window.
OSD_STYLES = [
    ("capsule", "Capsule", "A thick bar, where the popup has always been"),
    ("tab", "Top bar tab", "Hangs from the top bar, everything on one line"),
]
# The mocks are smaller than life, and a popup in one has to be too.
OSD_MOCK_SCALE = 0.6

# What the icons page shows of a pack. A folder and a document folder because
# those carry the pack's colour, and the rest because everyone has them open. The
# packs are fetched during the install too, so these exist in gui/samples/icons/
# as the packs' own drawings: <name>.svg where every accent gets the same one,
# <name>-<accent>.svg where the accent changes it. Change this, then run
# gui/samples/render_samples.py. The check fails on a missing one.
ICON_SAMPLES = ("folder", "folder-documents", "org.gnome.Nautilus",
                "org.gnome.Console", "org.gnome.Settings", "firefox",
                "org.gnome.Calendar", "org.gnome.TextEditor")

# --system-icons. The same options, order and recommendation as Step 3 of the text
# wizard and SYSTEM_ICONS in the settings window, which the check compares.
SYSTEM_ICONS = [
    ("lucide", "Lucide",
     "Thin modern icons for sound, Wi-Fi, battery and more. Recommended"),
    ("pack", "From the icon pack", "Whatever the pack above draws"),
]

# Where each pack comes from, so that picking somebody else's work links to it
# rather than just naming it. The same URLs as COLLOID_REPO, REVERSAL_REPO,
# HATTER_REPO and MACTAHOE_REPO in lib/steps.sh, minus the .git — the links
# check in tools/check-wizard-flags.py asserts the two lists still agree.
#
# The AOSP pointers are the odd one out: install.sh fetches a release tarball
# rather than cloning, so there is no *_REPO to check this against, and the link
# is the project page a person would want anyway.
PACK_LINKS = {
    "colloid": "https://github.com/vinceliuice/Colloid-icon-theme",
    "reversal": "https://github.com/yeyushengfan258/Reversal-icon-theme",
    "hatter": "https://github.com/Mibea/Hatter",
    "mactahoe": "https://github.com/vinceliuice/MacTahoe-icon-theme",
    "aosp": "https://github.com/Tech-Tac/aosp-cursors",
    "moga": "https://www.gnome-look.org/p/2302110",
}

# How each pack spells its own name, for the summary. .capitalize() was doing
# this and gets two of the five wrong — "Mactahoe" and "Aosp" are neither what
# the projects call themselves nor what the pages above say.
PACK_NAMES = {
    "colloid": "Colloid",
    "reversal": "Reversal",
    "hatter": "Hatter",
    "aosp": "AOSP",
    "mactahoe": "MacTahoe",
    "moga": "Aura Moga Neon",
}

# The stops on the opacity bar, and the three levels that have been looked at on
# a screen. The same range, marks, words and snap as the settings window's Opacity
# bar (TRANSPARENCY_* in gui/aura_glass_settings.py), so what is picked here is
# found again there unchanged. tools/check-wizard-flags.py asserts the two agree.
TRANSPARENCY_MIN = 70
TRANSPARENCY_MAX = 100
TRANSPARENCY_MARKS = [
    (82, "deep"),
    (90, "balanced"),
    (95, "subtle"),
]
TRANSPARENCY_SNAP = 1

# Pointer sizes, named for the display each suits. 32 on a 1440p panel is the
# baseline, and it is also the smallest size Moga's Xcursor files carry (32, 48,
# 64, 96): 24 and 48 keep the pointer the same share of a 1080p and a 4K screen.
# The twin list and recommended_cursor_size in lib/common.sh are the text wizard's.
CURSOR_SIZES = [
    ("24", "24px", "1080p"),
    ("32", "32px", "1440p"),
    ("48", "48px", "4K"),
    ("64", "64px", "Extra large"),
]
CURSOR_SIZE_FALLBACK = "32"

# The pages, in order. One of them does not always apply — see Window.applies.
PAGES = ["welcome", "accent", "glass", "icons", "cursors", "extensions", "gdm",
         "summary"]

# What Skip on each page puts back. Skip is not "leave whatever I clicked", it
# is "I did not want to decide this" — so it restores the defaults for the
# fields that page owns and moves on.
PAGE_FIELDS = {
    "accent": ("accent", "font"),
    "glass": ("scope", "transparency"),
    "icons": ("want_icons", "icons", "system_icons"),
    "cursors": ("want_cursors", "cursors", "want_cursor_size", "cursor_size"),
    "extensions": ("want_osd", "osd_style", "extensions"),
    "gdm": ("gdm", "gdm_monitors"),
}

# The same vocabulary as the update window (gui/aura_glass_install_progress.py):
# soft cards on alpha(currentColor), round badges, small pills. The mock desktop
# is fixed dark on purpose: it is a picture of the theme, which is dark-only,
# whatever this not-yet-themed machine draws the window around it in.
#
# Anything that follows an answer (@aura_accent, the mock windows' opacity) is in
# the second provider, rewritten by Window.sync_look.
CSS = """
flowbox.aura-flow > flowboxchild { padding: 0; }
checkbutton radio:checked, checkbutton check:checked {
    background-color: @aura_accent;
    background-image: none;
    color: white;
}
switch:checked { background-color: @aura_accent; background-image: none; }
scale > trough > highlight { background-color: @aura_accent; background-image: none; }
.page-eyebrow {
    font-size: smaller;
    font-weight: bold;
    letter-spacing: 1px;
    color: @aura_accent;
}
.stepper-seg {
    min-width: 26px;
    min-height: 4px;
    border-radius: 999px;
    background-color: alpha(currentColor, 0.15);
}
.stepper-seg.done { background-color: alpha(@aura_accent, 0.55); }
.stepper-seg.current { background-color: @aura_accent; }
button.aura-primary {
    background-image: none;
    background-color: @aura_accent;
    color: white;
    font-weight: bold;
    border-radius: 999px;
    padding: 6px 22px;
    min-height: 26px;
}
button.aura-primary:hover { background-image: image(alpha(white, 0.10)); }
button.aura-primary:active { background-image: image(alpha(black, 0.12)); }
.choice-card {
    padding: 12px 14px;
    min-height: 40px;
    border-radius: 14px;
    border: 2px solid transparent;
    background-color: alpha(currentColor, 0.05);
    transition: background-color 150ms ease-out, border-color 150ms ease-out;
}
.choice-card:hover { background-color: alpha(currentColor, 0.09); }
.choice-card.selected {
    border-color: @aura_accent;
    background-color: alpha(@aura_accent, 0.13);
}
.choice-card.dimmed { opacity: 0.5; }
.choice-card button {
    min-height: 26px;
    padding: 2px 10px;
    font-size: smaller;
}
.icon-badge {
    min-width: 36px;
    min-height: 36px;
    border-radius: 999px;
    background-color: alpha(currentColor, 0.09);
}
.selected .icon-badge, .icon-badge.accent {
    background-color: alpha(@aura_accent, 0.32);
}
.reco-pill {
    padding: 1px 8px;
    border-radius: 999px;
    background-color: alpha(@success_color, 0.18);
    color: @success_color;
    font-size: smaller;
    font-weight: bold;
}
.accent-swatch {
    min-width: 42px;
    min-height: 42px;
    padding: 0;
    border-radius: 50%;
    background-image: none;
    box-shadow: none;
    border: 3px solid transparent;
    color: white;
}
.accent-swatch:checked { border-color: alpha(currentColor, 0.75); }
.path-card {
    padding: 8px 12px;
    border-radius: 14px;
    background-image: none;
    background-color: alpha(currentColor, 0.06);
    font-weight: normal;
}
.path-card .icon-badge { min-width: 28px; min-height: 28px; }
.path-card:hover { background-color: alpha(currentColor, 0.10); }
.path-card.primary { background-color: @aura_accent; color: white; }
.path-card.primary:hover { background-image: image(alpha(white, 0.10)); }
.path-card.primary .icon-badge { background-color: alpha(white, 0.22); color: white; }
.path-card.primary .dim-label { opacity: 0.85; }
.summary-tile {
    padding: 12px 14px;
    border-radius: 14px;
    background-image: none;
    background-color: alpha(currentColor, 0.06);
    font-weight: normal;
}
.summary-tile:hover { background-color: alpha(currentColor, 0.10); }
.next-number {
    min-width: 26px;
    min-height: 26px;
    border-radius: 999px;
    background-color: alpha(@aura_accent, 0.22);
    color: @aura_accent;
    font-weight: bold;
}
.mock-frame { border-radius: 16px; }
.mock-wall {
    background-color: #14141c;
    background-image:
        radial-gradient(circle at 18% 28%, alpha(@aura_accent, 0.95), transparent 46%),
        radial-gradient(circle at 82% 78%, alpha(@aura_accent, 0.60), transparent 42%),
        radial-gradient(circle at 62% 12%, alpha(white, 0.28), transparent 30%),
        linear-gradient(135deg, #191926, #2c2740);
}
.mock-bar {
    min-height: 14px;
    padding: 0 8px;
    color: alpha(white, 0.85);
    background-color: alpha(#16161c, 0.55);
}
.mock-chip {
    min-width: 7px;
    min-height: 5px;
    border-radius: 999px;
    background-color: alpha(white, 0.55);
}
.mock-window {
    border-radius: 11px;
    padding: 8px;
    color: alpha(white, 0.85);
    border: 1px solid alpha(white, 0.14);
    box-shadow: 0 8px 22px alpha(black, 0.40);
}
.mock-dot {
    min-width: 7px;
    min-height: 7px;
    border-radius: 999px;
    background-color: alpha(white, 0.40);
}
.mock-side {
    border-radius: 7px;
    padding: 6px;
    background-color: alpha(white, 0.07);
}
.mock-line {
    min-height: 5px;
    border-radius: 999px;
    background-color: alpha(white, 0.28);
}
.mock-side-pick { color: @aura_accent; }
.mock-dock {
    padding: 5px 7px;
    border-radius: 12px;
    background-color: alpha(#20202a, 0.55);
    border: 1px solid alpha(white, 0.12);
}
.mock-tile {
    min-width: 15px;
    min-height: 15px;
    border-radius: 5px;
    background-color: alpha(white, 0.32);
}
.mock-tile.accent { background-color: @aura_accent; }
.mock-icons { padding: 10px 14px; border-radius: 20px; }
.mock-osd-level { border-radius: 999px; }
.mock-osd-stock {
    padding: 8px 12px;
    border-radius: 30px;
    color: #fafafa;
    background-color: rgba(0, 0, 0, 0.92);
}
.mock-osd-stock .mock-osd-trough { background-color: alpha(white, 0.12); }
.mock-osd-stock .mock-osd-fill { background-color: @aura_accent; }
""" + "".join("button.swatch-%s { background-color: %s; }\n" % (name, hexcolour)
              for name, _label, hexcolour in ACCENTS)

Choice = collections.namedtuple(
    "Choice", "value title subtitle icon pill link", defaults=(None, None, None))


def read_memo(name):
    """One $CONF_DIR memo, or None. The same files install.sh reads."""
    try:
        with open(os.path.join(CONF_DIR, name), encoding="utf-8") as handle:
            return handle.read().strip() or None
    except OSError:
        return None


def plain_row(row, title, subtitle=None):
    """Set a row's text as text rather than as Pango markup.

    Extension descriptions are other people's, and "Vitals — CPU, RAM & network
    monitor" has an & in it. With markup on, Pango rejects the whole string and
    the row renders empty. Same helper, and same reason, as the settings window.
    """
    row.set_use_markup(False)
    row.set_title(title)
    if subtitle is not None:
        row.set_subtitle(subtitle)
    return row


def open_link(uri):
    """Open uri in the default browser without touching our own stdio.

    Gio.AppInfo.launch_default_for_uri spawns with fd 0/1/2 inherited, and
    stdout here is the flags channel lib/steps-wizard.sh reads (see main()).
    A browser that prints anything on launch — Chrome does, "Opening in
    existing browser session." on stdout when a window is already open —
    would land in the flags file and make install.sh die on "unknown
    option". Gio.Subprocess gives control over that; the plain GAppInfo call
    does not.
    """
    try:
        Gio.Subprocess.new(
            ["gio", "open", uri],
            Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE)
    except GLib.Error:
        pass


def ext_catalogue(repo):
    """The catalogue, from bin/aura-glass-ext rather than a second copy of it.

    Same call the settings window makes, and for the same reason: the arrays and
    their descriptions change more often than anything else in this project, and
    a hand-maintained Python copy of them would be wrong within a release.

    An empty list is a working answer, not a failure — the extensions page says
    so and the wizard sends no --extensions at all, which leaves install.sh on
    its own default pack.
    """
    script = os.path.join(repo, "bin", "aura-glass-ext")
    try:
        res = subprocess.run(["bash", script, "list"],
                             capture_output=True, text=True, timeout=30)
        if res.returncode != 0:
            return []
        return json.loads(res.stdout)
    except (OSError, subprocess.SubprocessError, ValueError):
        return []


def cursor_size_for(height, scale):
    """The pointer size for one display: its physical height, and its scale.

    A display scaled 175% or more counts by what it is scaled down to, because
    GNOME multiplies the pointer by that scale itself: a 4K panel at 200% wants
    what 1080p wants, and asking for 48 there draws 96 device pixels. Below that,
    fractional scaling leaves the panel in its own class — 32 is the size this
    project settled on for 1440p at 133%.
    """
    effective = height / scale if scale >= 1.75 else height
    if effective <= 1200:
        return "24"
    if effective <= 1800:
        return "32"
    return "48"


def recommended_cursor_size():
    """The largest answer across the displays connected now, or the 1440p one.

    recommended_cursor_size in lib/common.sh makes the same call for the text
    wizard and for Complete Experience there.
    """
    display = Gdk.Display.get_default()
    if display is None:
        return CURSOR_SIZE_FALLBACK
    monitors = display.get_monitors()
    sizes = []
    for index in range(monitors.get_n_items()):
        monitor = monitors.get_item(index)
        scale = monitor.get_scale()
        sizes.append(int(cursor_size_for(
            round(monitor.get_geometry().height * scale), scale)))
    return str(max(sizes)) if sizes else CURSOR_SIZE_FALLBACK


def interface_setting(key):
    """A value of GNOME's interface schema, read only, or None.

    Looked up first because Gio.Settings aborts the process on a schema that
    is not installed, and this window must not be what stops an install.
    """
    source = Gio.SettingsSchemaSource.get_default()
    schema = "org.gnome.desktop.interface"
    if source is None or source.lookup(schema, True) is None:
        return None
    return Gio.Settings.new(schema).get_value(key).unpack()


def system_font_family():
    """The family --font system ends up on: apply_font's backup, else today's.

    Not simply today's. On a machine this project already gave a font, GNOME is
    using that font now, and --font system puts back the one from before it.
    """
    name = (read_memo(os.path.join("backups", "font-name.gsettings-orig"))
            or interface_setting("font-name"))
    if not name:
        return None
    return Pango.FontDescription.from_string(name.strip("'")).get_family()


PointerFrame = collections.namedtuple("PointerFrame",
                                      "nominal texture width height box")


def read_pointer(path):
    """Every size in an Xcursor file, gzipped or not, as PointerFrames.

    The file format is small enough to read here, and it is the one thing all
    the pointers have in common: the shipped samples are these files, and the
    theme already on the machine is too. An animated pointer has several images
    per size, and the first is the one to show. box is the drawn part of the
    image (left, top, right, bottom), so a sample can be centred on the arrow
    rather than on the empty canvas around it.
    """
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    frames = {}
    magic, _header, _version, count = struct.unpack_from("<4sIII", data)
    if magic != b"Xcur":
        return []
    for index in range(count):
        kind, _subtype, at = struct.unpack_from("<III", data, 16 + index * 12)
        if kind != 0xfffd0002:
            continue
        (_size, _kind, nominal, _version, width, height, _xhot, _yhot,
         _delay) = struct.unpack_from("<9I", data, at)
        if nominal in frames:
            continue
        pixels = data[at + 36:at + 36 + width * height * 4]
        rows = [row for row in range(height)
                if any(pixels[(row * width * 4) + 3:(row + 1) * width * 4:4])]
        columns = [col for col in range(width)
                   if any(pixels[col * 4 + 3::width * 4])]
        if not rows or not columns:
            continue
        # Xcursor's ARGB is premultiplied, and a little-endian word of it is
        # B, G, R, A in memory.
        texture = Gdk.MemoryTexture.new(
            width, height, Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED,
            GLib.Bytes.new(pixels), width * 4)
        frames[nominal] = PointerFrame(
            nominal, texture, width, height,
            (columns[0], rows[0], columns[-1] + 1, rows[-1] + 1))
    return list(frames.values())


def pointer_theme_file(theme, seen=()):
    """The arrow of an installed pointer theme, following Inherits, or None."""
    roots = [os.path.expanduser("~/.icons"),
             os.path.join(GLib.get_user_data_dir(), "icons")]
    roots += [os.path.join(d, "icons") for d in GLib.get_system_data_dirs()]
    inherits = []
    for root in roots:
        for name in ("default", "left_ptr"):
            path = os.path.join(root, theme, "cursors", name)
            if os.path.isfile(path):
                return path
        index = configparser.ConfigParser(interpolation=None, strict=False)
        try:
            index.read(os.path.join(root, theme, "index.theme"),
                       encoding="utf-8")
        except configparser.Error:
            continue
        inherits += index.get("Icon Theme", "Inherits", fallback="").split(",")
    for parent in inherits:
        parent = parent.strip().strip('"')
        if parent and parent != theme and parent not in seen:
            found = pointer_theme_file(parent, (*seen, theme))
            if found:
                return found
    return None


def osd_colours(repo):
    """The popup's fill and bar, from the preset the install is about to load.

    Colours only. The geometry is OSD_DESIGNS, because Custom OSD leaves it to the
    stylesheet for both designs.
    """
    preset = configparser.ConfigParser(interpolation=None, strict=False)
    preset.read(os.path.join(repo, "dconf", "core.ini"), encoding="utf-8")
    osd = preset["custom-osd"]

    def channels(key):
        return tuple(int(float(v.strip(" '")) * 255)
                     for v in osd[key].strip("[]").split(",")[:3])

    return {
        "background": "rgba(%d, %d, %d, %.2f)" % (
            *channels("bgcolor"), float(osd["alpha"]) / 100),
        "fill": "rgba(%d, %d, %d, %.2f)" % (
            *channels("levcolor"), float(osd["levalpha"]) / 100),
    }


class TextOutline(Gtk.Widget):
    """A string from gui/samples/fonts/, filled in the widget's CSS colour.

    A path rather than a picture of the text, because no picture stays sharp
    here. Any scale but the one it was drawn for resamples it, and at 133% the
    words came out soft at 2× and at 4× alike. A path is filled for the device
    pixels it lands on, which came out level with a real label beside it. The
    colour comes from the CSS around it, the way a label's does.
    """

    def __init__(self):
        super().__init__()
        self.path = None
        self.width = self.height = 0

    def set_outline(self, outline):
        self.path = Gsk.Path.parse(outline["path"]) if outline else None
        self.width = outline["width"] if outline else 0
        self.height = outline["height"] if outline else 0
        self.queue_resize()

    def do_measure(self, orientation, _for_size):
        length = (self.width if orientation == Gtk.Orientation.HORIZONTAL
                  else self.height)
        return length, length, -1, -1

    def do_snapshot(self, snapshot):
        if self.path is not None:
            snapshot.append_fill(self.path, Gsk.FillRule.WINDING,
                                 self.get_color())


def font_outlines(repo, font):
    """One font's {key: {width, height, path}}, or {} if it is not there."""
    try:
        with open(os.path.join(repo, "gui", "samples", "fonts", font + ".json"),
                  encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


class SampleText(Gtk.Box):
    """One FONT_SAMPLES string set in the font named by the font property.

    "system" is a real label, because that font is the one font here that is
    certainly on the machine, and nothing shipped could know what it is. The
    others are outlines. One that went missing falls back to the label.
    """

    def __init__(self, repo, key, font="system"):
        super().__init__(valign=Gtk.Align.CENTER)
        self.repo = repo
        self.key = key
        self._font = None
        text, px, weight = FONT_SAMPLES[key]
        attrs = Pango.AttrList()
        family = system_font_family()
        if family:
            attrs.insert(Pango.attr_family_new(family))
        attrs.insert(Pango.attr_size_new_absolute(int(px * Pango.SCALE)))
        attrs.insert(Pango.attr_weight_new(SAMPLE_WEIGHTS[weight]))
        self.label = Gtk.Label(label=text, attributes=attrs, xalign=0)
        self.outline = TextOutline()
        self.append(self.label)
        self.append(self.outline)
        self.font = font

    @GObject.Property(type=str)
    def font(self):
        return self._font

    @font.setter
    def font(self, value):
        if value == self._font:
            return
        self._font = value
        outline = (font_outlines(self.repo, value).get(self.key)
                   if value != "system" else None)
        self.outline.set_outline(outline)
        self.outline.set_visible(outline is not None)
        self.label.set_visible(outline is None)


class PointerSample(Gtk.Widget):
    """A pointer at the size it really is, in a box that fits the largest.

    Mutter picks the Xcursor image nearest the wanted size times the display's
    scale rounded up, then draws it at image size × wanted / nominal in logical
    pixels, whatever image it got
    (meta_cursor_sprite_xcursor_get_scaled_image_size). This widget's pixels are
    logical pixels on that same display, so the same sum here draws what the
    pointer is going to be on this screen, for any height and scale. It also
    keeps the empty canvas a real arrow sits in, which is why a 32 px pointer's
    arrow is well under 32 px tall. A pack's steps can be uneven: MacTahoe's
    images fill their nominal size differently from one to the next, and that
    shows here because it shows on the desktop.
    """

    BOX = 66

    def __init__(self):
        super().__init__(halign=Gtk.Align.CENTER)
        self.path = None
        self.size = 0
        self.frames = []

    def show_pointer(self, path, size):
        if path != self.path:
            self.path = path
            try:
                self.frames = read_pointer(path) if path else []
            except (OSError, EOFError, struct.error):
                self.frames = []
        self.size = size
        self.queue_draw()

    def do_measure(self, _orientation, _for_size):
        return self.BOX, self.BOX, -1, -1

    def do_snapshot(self, snapshot):
        if not self.frames:
            return
        scale = self.get_native().get_surface().get_scale()
        wanted = self.size * math.ceil(scale)
        frame = min(self.frames, key=lambda f: abs(f.nominal - wanted))
        factor = self.size / frame.nominal
        left, top, right, bottom = frame.box

        def snap(value):
            # On a device pixel, or a 1:1 image would come out soft.
            return round(value * scale) / scale

        x = snap((self.get_width() - (left + right) * factor) / 2)
        y = snap((self.get_height() - (top + bottom) * factor) / 2)
        snapshot.append_scaled_texture(
            frame.texture, Gsk.ScalingFilter.TRILINEAR,
            Graphene.Rect().init(x, y, frame.width * factor,
                                 frame.height * factor))


class Answers:
    """What the window collected, and the command line it means.

    Deliberately not a diff against what is on disk, which is what the settings
    window's Settings.flags_against does. That exists so a retune cannot clobber
    a value the window never showed a row for; here there is nothing to clobber.
    This only runs when install.sh was given no flags at all, and its text twin
    sets every one of these variables unconditionally on every run. Emitting the
    full set matches that, and has no diff logic to get subtly wrong.
    """

    def __init__(self, extensions=None):
        # The one field with a memory. install.sh resolves the remembered accent
        # before it reaches the wizard, and the text wizard offers it as the
        # default; this offers the same one.
        self.accent = read_memo("accent") or "purple"
        # Remembered the same way the accent is, and for the same reason: a
        # second run of the installer on a machine that already chose a font
        # should open on that font rather than offer to undo it.
        self.font = read_memo("font") or "system"
        self.scope = "all"          # all | gtk
        self.transparency = "0.90"
        self.want_icons = True
        # The recommended pair, and the wizard's defaults. Both go out as an
        # explicit --icons/--cursors, so install.sh's own flagless defaults
        # (colloid and adwaita) are untouched by this — the wizard states its
        # answer rather than relying on one.
        self.icons = "reversal"
        # As system_icons_choice reads the memo: only "pack" is the pack.
        self.system_icons = ("pack" if read_memo("system-icons") == "pack"
                             else "lucide")
        self.want_cursors = True
        self.cursors = "moga"
        # Independent of the pair above: pointer theme and pointer size are
        # two different gsettings keys, so "leave my theme alone" is not a
        # statement about size. Window moves this to what the display wants.
        self.want_cursor_size = True
        self.cursor_size = CURSOR_SIZE_FALLBACK
        self.want_osd = True
        self.osd_device_name = read_memo("osd-device-name") == "1"
        # As apply_osd_style reads the memo: only "tab" is the tab.
        self.osd_style = "tab" if read_memo("osd-style") == "tab" else "capsule"
        # None means "say nothing about extensions", which leaves install.sh on
        # the Core package. Only a readable catalogue turns this into a list.
        self.extensions = extensions
        self.gdm = True
        self.gdm_monitors = True

    def copy(self):
        clone = Answers.__new__(Answers)
        clone.__dict__.update(self.__dict__)
        if isinstance(self.extensions, list):
            clone.extensions = list(self.extensions)
        return clone

    @classmethod
    def best(cls, catalogue, gdm_present, multi_monitor,
             cursor_size=CURSOR_SIZE_FALLBACK):
        """Every default this project would pick for itself.

        Everything else about the look is already __init__'s own default —
        accent and font from their memos, Reversal and Moga recommended
        rather than install.sh's older bare defaults of Colloid and Adwaita.
        Only the questions with no single obviously-right answer move: every
        extension rather than the Core tier (the same set on_ext_preset's
        "Complete Experience" button builds), the pointer size the display
        wants, GDM theming wherever there is a GDM to theme, and the monitor
        sync only where it would fix something — a single display has nothing
        for it to fix.
        """
        answers = cls()
        answers.extensions = [e["uuid"] for e in catalogue
                              if e["tier"] in ("recommended", "full")] or None
        answers.cursor_size = cursor_size
        answers.gdm = gdm_present
        answers.gdm_monitors = gdm_present and multi_monitor
        return answers

    def to_argv(self, gdm_present):
        args = ["--accent", self.accent, "--font", self.font]

        # Always frosted, stated so a re-run on an install remembered as
        # performance lands here too. Performance itself is not a question any
        # more: it arrives with every install, one switch away in Settings.
        args += ["--glass-mode", "frosted"]
        args.append("--all-apps-blur" if self.scope == "all"
                    else "--gtk-apps-blur")
        args += ["--app-transparency", self.transparency, "--popup-blur"]

        if self.want_icons:
            args += ["--icons", self.icons, "--system-icons", self.system_icons]
        else:
            args.append("--no-icons")

        if self.want_cursors:
            args += ["--cursors", self.cursors]
        else:
            args.append("--no-cursors")

        if self.want_cursor_size:
            args += ["--cursor-size", self.cursor_size]

        args.append("--osd" if self.want_osd else "--no-osd")
        if self.want_osd:
            args.append("--osd-device-name" if self.osd_device_name
                        else "--no-osd-device-name")
            args += ["--osd-style", self.osd_style]

        if self.extensions is not None:
            args += ["--extensions", ",".join(self.extensions)]

        # Only where there is a login manager to theme. install.sh works out
        # whether there is one and tells us; asking about GDM on a machine
        # running SDDM would be offering a setting with nothing behind it.
        if gdm_present:
            args.append("--gdm" if self.gdm else "--no-gdm")
            args.append("--gdm-monitors" if self.gdm_monitors
                        else "--no-gdm-monitors")

        return args


class Window(Adw.ApplicationWindow):
    # The font the mocks are set in. A property so that every SampleText on
    # every page can bind to it, and a binding goes when its page goes.
    sample_font = GObject.Property(type=str, default="system")

    def __init__(self, app, repo, gdm_present):
        super().__init__(application=app, title="Aura Glass Setup",
                         default_width=860, default_height=780,
                         width_request=740, height_request=560)
        self.repo = repo
        self.gdm_present = gdm_present
        self.catalogue = ext_catalogue(repo)
        self.pointer_samples = []
        self.icon_samples = []
        # What redraws each popup preview, one per page that has one. Keyed so a
        # page built again replaces its own rather than adding another.
        self.osd_updates = {}

        full_experience = [e["uuid"] for e in self.catalogue
                           if e["tier"] in ("recommended", "full")] or None
        self.answers = Answers(full_experience)
        self.display_cursor_size = recommended_cursor_size()
        self.answers.cursor_size = self.display_cursor_size
        self.defaults = self.answers.copy()

        # Above the user's gtk.css for the reason the update window gives: on a
        # re-run that sheet is Aura Glass's own and sizes every button.
        self.look = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), self.look,
            Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)
        self.sync_look()
        self.load_osd_look()

        self.nav = Adw.NavigationView()
        self.nav.add(self.build_page("welcome"))
        self.set_content(self.nav)

    def sync_look(self):
        """The answers the window itself wears: accent, opacity and font.

        One provider rewritten rather than a class per value, so the bar can
        move every mock window on the page while it is being dragged. Frosted
        windows take the opacity. With blur only on GTK apps, the browser in the
        picture is opaque, which is what that choice does to one.
        """
        accent = next((hexcolour for name, _label, hexcolour in ACCENTS
                       if name == self.answers.accent), ACCENTS[0][2])
        alpha = float(self.answers.transparency)
        other = alpha if self.answers.scope == "all" else 1.0
        self.look.load_from_data((
            "@define-color aura_accent %s;\n"
            ".mock-window { background-color: rgba(30, 30, 38, %.2f); }\n"
            ".mock-window.browser { background-color: rgba(30, 30, 38, %.2f); }\n"
            % (accent, alpha, other)).encode("utf-8"))
        self.sample_font = self.answers.font
        for update in self.osd_updates.values():
            update()

    def load_osd_look(self):
        """The popups' colours and padding. See osd_colours and OSD_DESIGNS.

        Its own provider because it never changes, so the opacity bar does not
        reparse it on every step of a drag. The track is white 0.22 in both
        designs' .level rules, and Custom OSD leaves it to them.
        """
        rules = [
            ".mock-osd-popup {\n"
            "    color: rgba(255, 255, 255, 0.95);\n"
            "    background-color: %(background)s;\n"
            "}\n"
            ".mock-osd-popup .mock-osd-trough {\n"
            "    background-color: rgba(255, 255, 255, 0.22);\n"
            "}\n"
            ".mock-osd-popup .mock-osd-fill { background-color: %(fill)s; }\n"
            % osd_colours(self.repo)]
        for suffix, scale in (("", 1), (".mock", OSD_MOCK_SCALE)):
            capsule, tab = OSD_DESIGNS["capsule"], OSD_DESIGNS["tab"]
            rules.append(
                ".mock-osd-capsule%s { padding: %.1fpx %.1fpx; "
                "border-radius: %.1fpx; }\n"
                % (suffix, capsule["padding_y"] * scale,
                   capsule["padding_x"] * scale, capsule["radius"] * scale))
            # Square at the top, where it meets the bar.
            rules.append(
                ".mock-osd-tab%s { padding: 0 %.1fpx; "
                "border-radius: 0 0 %.1fpx %.1fpx; }\n"
                % (suffix, tab["padding_x"] * scale, tab["radius"] * scale,
                   tab["radius"] * scale))
        look = Gtk.CssProvider()
        look.load_from_data("".join(rules).encode("utf-8"))
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), look,
            Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)

    def mock_text(self, key):
        """A string in the mock, following the font answer as it changes."""
        text = SampleText(self.repo, key)
        self.bind_property("sample-font", text, "font",
                           GObject.BindingFlags.SYNC_CREATE)
        return text

    # ---- navigation ---------------------------------------------------------

    def applies(self, tag):
        if tag == "gdm":
            return self.gdm_present
        return True

    def advance(self, tag):
        index = PAGES.index(tag) + 1
        while index < len(PAGES) and not self.applies(PAGES[index]):
            index += 1
        if index < len(PAGES):
            self.nav.push(self.build_page(PAGES[index]))

    def skip(self, tag):
        for field in PAGE_FIELDS.get(tag, ()):
            value = getattr(self.defaults, field)
            setattr(self.answers, field, list(value)
                    if isinstance(value, list) else value)
        self.sync_look()
        self.advance(tag)

    def build_page(self, tag):
        return getattr(self, "page_" + tag.replace("-", "_"))()

    def finish(self):
        self.get_application().result = self.answers.to_argv(self.gdm_present)
        self.close()

    def _multi_monitor(self):
        """More than one display connected right now.

        install.sh's own text wizard makes the same call off
        ~/.config/monitors.xml and /sys/class/drm (multi_monitor_detected in
        lib/common.sh) for the machines that reach it with no display at all
        to ask Gdk. Here there is one, so this asks it directly.
        """
        display = Gdk.Display.get_default()
        if display is None:
            return False
        return display.get_monitors().get_n_items() > 1

    def _on_best(self, _button):
        self.answers = Answers.best(self.catalogue, self.gdm_present,
                                    self._multi_monitor(),
                                    self.display_cursor_size)
        self.finish()

    # ---- page furniture -----------------------------------------------------

    def _steps(self):
        return [p for p in PAGES if p not in ("welcome", "summary")
                and self.applies(p)]

    def _stepper(self, tag):
        """One segment per question page, filled up to this one."""
        steps = self._steps()
        here = steps.index(tag) if tag in steps else len(steps)
        row = Gtk.Box(spacing=5, valign=Gtk.Align.CENTER)
        for index in range(len(steps)):
            segment = Gtk.Box(valign=Gtk.Align.CENTER)
            segment.add_css_class("stepper-seg")
            if index < here:
                segment.add_css_class("done")
            elif index == here:
                segment.add_css_class("current")
            row.append(segment)
        return row

    def shell(self, tag, title, subtitle, content, *, skippable=True,
              next_label="Next", on_next=None, maximum=720):
        """One page: a stepper, a large heading, the content, the buttons."""
        view = Adw.ToolbarView()
        header = Adw.HeaderBar()
        header.set_title_widget(self._stepper(tag))
        view.add_top_bar(header)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=22,
                       margin_top=10, margin_bottom=24,
                       margin_start=20, margin_end=20)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        steps = self._steps()
        if tag in steps:
            eyebrow = Gtk.Label(
                label="STEP %d OF %d" % (steps.index(tag) + 1, len(steps)),
                xalign=0)
            eyebrow.add_css_class("page-eyebrow")
            words.append(eyebrow)
        heading = Gtk.Label(label=title, xalign=0, wrap=True)
        heading.add_css_class("title-1")
        words.append(heading)
        line = Gtk.Label(label=subtitle, xalign=0, wrap=True)
        line.add_css_class("dim-label")
        words.append(line)
        body.append(words)
        body.append(content)
        view.set_content(Gtk.ScrolledWindow(
            child=Adw.Clamp(maximum_size=maximum, tightening_threshold=maximum,
                            child=body), vexpand=True,
            hscrollbar_policy=Gtk.PolicyType.NEVER))

        bottom = Gtk.Box(spacing=12, margin_top=12, margin_bottom=12,
                         margin_start=16, margin_end=16)
        if skippable:
            button = Gtk.Button(label="Skip")
            button.add_css_class("flat")
            button.set_tooltip_text("Keep the default and move on")
            button.connect("clicked", lambda _b: self.skip(tag))
            bottom.append(button)
        bottom.append(Gtk.Box(hexpand=True))
        nxt = Gtk.Button(label=next_label)
        nxt.add_css_class("aura-primary")
        nxt.connect("clicked", lambda _b: (on_next or self.advance)(tag))
        bottom.append(nxt)
        view.add_bottom_bar(bottom)

        return Adw.NavigationPage(child=view, title=title, tag=tag)

    @staticmethod
    def stack(*children, spacing=22):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=spacing)
        for child in children:
            box.append(child)
        return box

    @staticmethod
    def section(title, description, *children):
        """A heading, a line under it, and what it is about."""
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        label = Gtk.Label(label=title, xalign=0, wrap=True)
        label.add_css_class("heading")
        words.append(label)
        if description:
            line = Gtk.Label(label=description, xalign=0, wrap=True)
            line.add_css_class("caption")
            line.add_css_class("dim-label")
            words.append(line)
        box.append(words)
        for child in children:
            box.append(child)
        return box

    @staticmethod
    def badge(icon=None, sample=None):
        """A round badge holding a symbolic icon, or a font sample."""
        box = Gtk.Box(halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        box.add_css_class("icon-badge")
        # The child fills the badge so it is centred in the circle; set here so
        # the badge does not pass that expand on to the card around it.
        box.set_hexpand(False)
        box.set_vexpand(False)
        if sample is not None:
            inner = sample
            inner.set_halign(Gtk.Align.CENTER)
            inner.set_hexpand(True)
            inner.set_vexpand(True)
        else:
            inner = Gtk.Image(icon_name=icon, hexpand=True, vexpand=True)
        box.append(inner)
        return box

    @staticmethod
    def flow(columns):
        # Both limits, or FlowBox falls back to one column whenever a wrapping
        # label asks for its natural width. Window's width_request keeps the
        # narrowest of these readable.
        box = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE,
                          homogeneous=True, column_spacing=10, row_spacing=10,
                          min_children_per_line=columns,
                          max_children_per_line=columns)
        box.add_css_class("aura-flow")
        return box

    @staticmethod
    def flow_add(flow, child):
        flow.append(child)
        # The card's own controls take the keyboard; a focus ring around each
        # cell as well would be one extra Tab stop per card.
        child.get_parent().set_focusable(False)

    def choice_cards(self, options, current, on_pick, columns=1):
        """Radio choices as cards. The whole card is the click target.

        A Gtk.CheckButton is still what holds the state, so the group behaves
        and reads as a radio list to the keyboard and a screen reader. The card
        cannot be a button itself, because some of them hold a link button.
        """
        flow = self.flow(columns)
        first = None
        for choice in options:
            card = Gtk.Box(spacing=12)
            card.add_css_class("choice-card")
            if choice.icon == "Aa":
                card.append(self.badge(sample=SampleText(
                    self.repo, "aa", choice.value)))
            elif choice.icon:
                card.append(self.badge(choice.icon))

            words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2,
                            hexpand=True, valign=Gtk.Align.CENTER)
            top = Gtk.Box(spacing=8)
            title = Gtk.Label(label=choice.title, xalign=0, wrap=True)
            title.add_css_class("heading")
            top.append(title)
            if choice.pill:
                pill = Gtk.Label(label=choice.pill, valign=Gtk.Align.CENTER)
                pill.add_css_class("reco-pill")
                top.append(pill)
            words.append(top)
            if choice.icon == "Aa":
                sample = SampleText(self.repo, "line", choice.value)
                sample.set_halign(Gtk.Align.START)
                words.append(sample)
            if choice.subtitle:
                line = Gtk.Label(label=choice.subtitle, xalign=0, wrap=True,
                                 wrap_mode=Pango.WrapMode.WORD_CHAR)
                line.add_css_class("caption")
                line.add_css_class("dim-label")
                words.append(line)
            card.append(words)

            if choice.link:
                button = Gtk.Button(label="View project",
                                    valign=Gtk.Align.CENTER)
                button.add_css_class("flat")
                button.set_tooltip_text(choice.link)
                button.connect("clicked",
                               lambda _b, uri=choice.link: open_link(uri))
                card.append(button)

            check = Gtk.CheckButton(valign=Gtk.Align.CENTER)
            if first is None:
                first = check
            else:
                check.set_group(first)
            check.set_active(choice.value == current)
            if choice.value == current:
                card.add_css_class("selected")
            card.append(check)

            def toggled(button, value=choice.value, card=card):
                if button.get_active():
                    card.add_css_class("selected")
                    on_pick(value)
                else:
                    card.remove_css_class("selected")
            check.connect("toggled", toggled)

            click = Gtk.GestureClick()
            click.connect("released",
                          lambda *_a, c=check: c.set_active(True))
            card.add_controller(click)

            self.flow_add(flow, card)
        return flow

    def switch_card(self, icon, title, subtitle, active, on_change):
        """A switch as a card, clickable anywhere. Returns (card, switch)."""
        card = Gtk.Box(spacing=12)
        card.add_css_class("choice-card")
        card.append(self.badge(icon))
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2,
                        hexpand=True, valign=Gtk.Align.CENTER)
        label = Gtk.Label(label=title, xalign=0, wrap=True)
        label.add_css_class("heading")
        words.append(label)
        line = Gtk.Label(label=subtitle, xalign=0, wrap=True)
        line.add_css_class("caption")
        line.add_css_class("dim-label")
        words.append(line)
        card.append(words)
        switch = Gtk.Switch(active=active, valign=Gtk.Align.CENTER)
        card.append(switch)
        switch.connect("notify::active",
                       lambda s, _p: on_change(s.get_active()))
        click = Gtk.GestureClick()
        click.connect("released", lambda *_a: switch.set_active(
            not switch.get_active()) if switch.get_sensitive() else None)
        card.add_controller(click)
        return card, switch

    def mock_bar(self):
        """The mock's top bar, with its words in the font answer."""
        bar = Gtk.CenterBox(valign=Gtk.Align.START)
        bar.add_css_class("mock-bar")
        bar.set_start_widget(self.mock_text("bar"))
        bar.set_center_widget(self.mock_text("clock"))
        tray = Gtk.Box(spacing=5)
        for _ in range(3):
            dot = Gtk.Box(valign=Gtk.Align.CENTER)
            dot.add_css_class("mock-chip")
            tray.append(dot)
        bar.set_end_widget(tray)
        return bar

    def osd_popup(self, style, scale):
        """One design of the popup. Returns (widget, update for the name switch).

        Both designs have the icon, whatever the preset's osd-* keys say. The
        icon is the Lucide drawing the desktop will have, from symbols/lucide
        rather than this machine's theme, which may be anything.
        """
        design = OSD_DESIGNS[style]
        mock = scale != 1

        def px(value):
            return round(value * scale)

        popup = Gtk.Box(spacing=px(design["gap"]), width_request=px(design["width"]),
                        halign=Gtk.Align.CENTER)
        popup.add_css_class("mock-osd-popup")
        popup.add_css_class("mock-osd-" + style)
        if mock:
            popup.add_css_class("mock")
        icon = Gtk.Image(pixel_size=px(design["icon"]), valign=Gtk.Align.CENTER)
        icon.set_from_gicon(Gio.FileIcon.new(Gio.File.new_for_path(os.path.join(
            self.repo, "symbols", "lucide", "audio-volume-high-symbolic.svg"))))
        popup.append(icon)
        name = self.mock_text("osd-%s%s" % (style, "-mock" if mock else ""))
        name.set_halign(Gtk.Align.START)
        # What is left for the bar when it takes the line, as the fixed width
        # makes it: everything but the padding, the icon and the gap after it.
        room = px(design["width"]) - 2 * px(design["padding_x"]) \
            - px(design["icon"]) - px(design["gap"])
        level = self.osd_level(room, px(design["thickness"]))

        if style == "capsule":
            words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True,
                            spacing=px(design["name_gap"]),
                            valign=Gtk.Align.CENTER)
            words.append(name)
            words.append(level)
            popup.append(words)
        else:
            popup.set_size_request(px(design["width"]), px(design["height"]))
            name.set_hexpand(True)
            popup.append(name)
            level.set_halign(Gtk.Align.END)
            popup.append(level)

        def update():
            on = self.answers.osd_device_name
            name.set_visible(on)
            if style == "tab":
                # The bar is 120 wide beside a name and takes the line without one.
                self.set_level_width(level, px(design["bar"]) if on else room)
        return popup, update

    def osd_scene(self, overlay, tag, scale, foot):
        """The popup the answers mean, placed where the desktop puts it.

        The capsule sits below the middle of the screen, 38% of the height down
        (vertical=-38 in dconf/core.ini, which Custom OSD negates), so near the
        foot; foot is what to leave clear there. The tab hangs flush from the top
        bar, 14 being .mock-bar's height. GNOME's own popup also sits low, and is
        only drawn life size: it is a popup the mock has no reason to show when
        nobody is changing the volume.

        Registered in osd_updates, so every answer that changes it redraws it.
        """
        capsule, update_capsule = self.osd_popup("capsule", scale)
        capsule.set_valign(Gtk.Align.END)
        capsule.set_margin_bottom(foot)
        overlay.add_overlay(capsule)
        tab, update_tab = self.osd_popup("tab", scale)
        tab.set_valign(Gtk.Align.START)
        tab.set_margin_top(14)
        overlay.add_overlay(tab)
        stock = self.osd_stock(foot) if scale == 1 else None
        if stock:
            overlay.add_overlay(stock)

        def update():
            on = self.answers.want_osd
            capsule.set_visible(on and self.answers.osd_style == "capsule")
            tab.set_visible(on and self.answers.osd_style == "tab")
            if stock:
                stock.set_visible(not on)
            update_capsule()
            update_tab()
        self.osd_updates[tag] = update
        update()

    def mock_desktop(self, height=210, osd=None):
        """A small picture of the desktop these answers make.

        Boxes and CSS, no cairo (see the module docstring), and no image except
        its words, which are SampleTexts. Nothing here can blur, so the
        wallpaper's soft blobs stand in for what shows through the glass.
        Colours, opacity and font come from sync_look.
        """
        overlay = Gtk.Overlay(hexpand=True, overflow=Gtk.Overflow.HIDDEN)
        overlay.add_css_class("mock-frame")
        wall = Gtk.Box(height_request=height, hexpand=True)
        wall.add_css_class("mock-wall")
        overlay.set_child(wall)

        overlay.add_overlay(self.mock_bar())

        def window(extra, title, width, tall, **place):
            frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7,
                            width_request=width, height_request=tall, **place)
            frame.add_css_class("mock-window")
            if extra:
                frame.add_css_class(extra)
            dots = Gtk.Box(spacing=4, valign=Gtk.Align.CENTER)
            for _ in range(3):
                dot = Gtk.Box(valign=Gtk.Align.CENTER)
                dot.add_css_class("mock-dot")
                dots.append(dot)
            head = Gtk.CenterBox()
            head.set_start_widget(dots)
            head.set_center_widget(self.mock_text(title))
            frame.append(head)
            inner = Gtk.Box(spacing=7, vexpand=True)
            side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4,
                           width_request=width // 4)
            side.add_css_class("mock-side")
            for key in ("side-home", "side-photos", "side-music"):
                label = self.mock_text(key)
                label.set_halign(Gtk.Align.START)
                if key == "side-home":
                    label.add_css_class("mock-side-pick")
                side.append(label)
            inner.append(side)
            text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6,
                           hexpand=True)
            heading = self.mock_text("heading")
            heading.set_halign(Gtk.Align.START)
            text.append(heading)
            for _ in range(3):
                line = Gtk.Box()
                line.add_css_class("mock-line")
                text.append(line)
            inner.append(text)
            frame.append(inner)
            return frame

        unit = height / 210
        overlay.add_overlay(window(
            "browser", "title-web", int(250 * unit), int(120 * unit),
            halign=Gtk.Align.CENTER, valign=Gtk.Align.START,
            margin_top=int(26 * unit), margin_end=int(110 * unit)))
        overlay.add_overlay(window(
            None, "title-files", int(250 * unit), int(120 * unit),
            halign=Gtk.Align.CENTER, valign=Gtk.Align.START,
            margin_top=int(48 * unit), margin_start=int(110 * unit)))

        dock = Gtk.Box(spacing=5, halign=Gtk.Align.CENTER,
                       valign=Gtk.Align.END, margin_bottom=8)
        dock.add_css_class("mock-dock")
        for index in range(5):
            tile = Gtk.Box()
            tile.add_css_class("mock-tile")
            if index == 0:
                tile.add_css_class("accent")
            dock.append(tile)
        overlay.add_overlay(dock)
        if osd:
            self.osd_scene(overlay, osd, OSD_MOCK_SCALE, 40)
        return overlay

    # ---- the pages ----------------------------------------------------------

    def page_welcome(self):
        logo = Gtk.Image(pixel_size=56, halign=Gtk.Align.START)
        logo.set_from_gicon(Gio.FileIcon.new(Gio.File.new_for_path(os.path.join(
            self.repo, "gui", "icons",
            "io.github.DevWebeloper.AuraGlassSettings.svg"))))

        title = Gtk.Label(label="Aura Glass", xalign=0)
        title.add_css_class("title-1")
        tagline = Gtk.Label(
            label="One frosted material across the shell and your apps. Take "
                  "the best of it in one click, or choose each part yourself. "
                  "Everything can be changed later in Aura Glass Settings.",
            xalign=0, wrap=True)
        tagline.add_css_class("dim-label")

        def path_card(icon, heading, text, pill, primary, on_click, tooltip):
            button = Gtk.Button(hexpand=True)
            button.add_css_class("path-card")
            if primary:
                button.add_css_class("primary")
            row = Gtk.Box(spacing=10)
            row.append(self.badge(icon))
            words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1,
                            hexpand=True, valign=Gtk.Align.CENTER)
            top = Gtk.Box(spacing=8)
            label = Gtk.Label(label=heading, xalign=0)
            label.add_css_class("heading")
            top.append(label)
            if pill:
                tag = Gtk.Label(label=pill, valign=Gtk.Align.CENTER)
                tag.add_css_class("caption")
                top.append(tag)
            words.append(top)
            line = Gtk.Label(label=text, xalign=0, wrap=True)
            line.add_css_class("caption")
            line.add_css_class("dim-label")
            words.append(line)
            row.append(words)
            row.append(Gtk.Image(icon_name="go-next-symbolic"))
            button.set_child(row)
            button.set_tooltip_text(tooltip)
            button.connect("clicked", on_click)
            return button

        # Not preferences-desktop-theme-symbolic, which reads like the obvious
        # choice and does not exist: no icon theme ships it, so GTK falls back
        # to the full-colour preferences-desktop-theme and the welcome page
        # opens on a tuxedo. These are in stock Adwaita's categories rather
        # than its legacy set, which is what a machine has before any of this
        # is installed.
        best = path_card(
            "starred-symbolic", "Complete Experience",
            "The recommended look, every extension, and the login screen.",
            None, False, self._on_best,
            "The recommended look, every extension, and the login screen "
            "themed — the terminal will ask for your password once")
        custom = path_card(
            "applications-graphics-symbolic", "Customize",
            "Choose the colour, glass, icons, pointer and more, step by step.",
            None, True, lambda _b: self.advance("welcome"),
            "Answer each question yourself")

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20,
                       margin_top=6, margin_bottom=24,
                       margin_start=20, margin_end=20)
        body.append(self.mock_desktop(240, osd="welcome"))
        words = Gtk.Box(spacing=16)
        words.append(logo)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4,
                       hexpand=True, valign=Gtk.Align.CENTER)
        text.append(title)
        text.append(tagline)
        words.append(text)
        body.append(words)
        paths = Gtk.Box(spacing=10, homogeneous=True)
        paths.append(best)
        paths.append(custom)
        body.append(paths)

        view = Adw.ToolbarView()
        view.add_top_bar(Adw.HeaderBar(show_title=False))
        view.set_content(Gtk.ScrolledWindow(
            child=Adw.Clamp(maximum_size=720, tightening_threshold=720,
                            child=body), vexpand=True,
            hscrollbar_policy=Gtk.PolicyType.NEVER))
        return Adw.NavigationPage(child=view, title="Welcome", tag="welcome")

    def page_accent(self):
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE,
                           homogeneous=True, column_spacing=6, row_spacing=12,
                           min_children_per_line=5, max_children_per_line=9)
        first = None
        for name, label, _hexcolour in ACCENTS:
            button = Gtk.ToggleButton(tooltip_text=label,
                                      halign=Gtk.Align.CENTER)
            button.add_css_class("accent-swatch")
            button.add_css_class("swatch-" + name)
            if first is None:
                first = button
            else:
                button.set_group(first)

            mark = Gtk.Image(icon_name="object-select-symbolic")
            mark.set_visible(name == self.answers.accent)
            button.set_child(mark)
            button.set_active(name == self.answers.accent)

            def picked(toggle, name=name, mark=mark):
                mark.set_visible(toggle.get_active())
                if toggle.get_active():
                    self.answers.accent = name
                    self.sync_look()
            button.connect("toggled", picked)

            cell = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            cell.append(button)
            caption = Gtk.Label(label=label)
            caption.add_css_class("caption")
            cell.append(caption)
            self.flow_add(flow, cell)

        # On this page rather than one of its own: it is the second half of the
        # same question — what the desktop is built out of — and a page holding
        # one radio list would be a click for its own sake. The three fonts are
        # fetched during the install, not here, so their cards and the mock
        # above show outlines of them (FONT_SAMPLES).
        fonts = self.choice_cards(
            [Choice(v, t, sub, "Aa") for v, t, sub in FONTS],
            self.answers.font, self.set_font, columns=2)

        return self.shell(
            "accent", "Colour and type",
            "The panel, highlights and icons are built around your accent.",
            self.stack(
                self.mock_desktop(),
                self.section("Accent colour",
                             "GNOME offers these nine and no others.", flow),
                self.section("Interface font",
                             "Labels, menus, titlebars, documents — the whole "
                             "desktop. Keeps your current text size.", fonts)))

    def set_font(self, value):
        self.answers.font = value
        self.sync_look()

    def page_glass(self):
        scope = self.choice_cards([
            Choice("all", "Every app window",
                   "Browsers and Electron apps too — heavy on the CPU and GPU",
                   "view-grid-symbolic"),
            Choice("gtk", "GTK and GNOME apps",
                   "Files, Settings, Console and the rest — light on the CPU",
                   "folder-symbolic"),
        ], self.answers.scope, self.on_scope, columns=2)

        # The settings window's Opacity bar: its range, marks and pull towards
        # them (snap_to_marks there, simplified to a step of 1 here).
        scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, TRANSPARENCY_MIN, TRANSPARENCY_MAX, 1)
        scale.set_hexpand(True)
        scale.set_draw_value(False)
        for at, label in TRANSPARENCY_MARKS:
            scale.add_mark(at, Gtk.PositionType.BOTTOM, label)
        scale.set_value(round(float(self.answers.transparency) * 100))
        readout = Gtk.Label(valign=Gtk.Align.START, width_chars=5)
        readout.add_css_class("title-3")

        def snapped(bar, scroll, value):
            if scroll != Gtk.ScrollType.JUMP:
                return False
            at = min((m for m, _l in TRANSPARENCY_MARKS),
                     key=lambda m: abs(m - value))
            bar.set_value(at if abs(at - value) <= TRANSPARENCY_SNAP
                          else round(value))
            return True

        def moved(bar):
            percent = round(bar.get_value())
            readout.set_label("%d%%" % percent)
            self.answers.transparency = "%.2f" % (percent / 100.0)
            self.sync_look()

        scale.connect("change-value", snapped)
        scale.connect("value-changed", moved)
        readout.set_label("%d%%" % round(scale.get_value()))
        row = Gtk.Box(spacing=12)
        row.append(scale)
        row.append(readout)

        return self.shell(
            "glass", "Frosted glass",
            "Frosted is set up for you. Performance is installed beside it, one "
            "switch away in Settings.",
            self.stack(
                self.mock_desktop(),
                self.section("Blur behind app windows",
                             "Every blurred window is compositor work, every "
                             "frame.", scope),
                self.section("Opacity",
                             "Lower is more see-through. 70% is the lowest.",
                             row)))

    def on_scope(self, value):
        self.answers.scope = value
        self.sync_look()

    def page_icons(self):
        current = self.answers.icons if self.answers.want_icons else "keep"
        # Hidden rather than dimmed for a theme left alone: --no-icons ignores
        # the answer, and "the pack above" would have no pack to mean.
        self.system_icons = self.section(
            "System icons", None, self.choice_cards(
                [Choice(value, title, subtitle, "audio-volume-high-symbolic")
                 for value, title, subtitle in SYSTEM_ICONS],
                self.answers.system_icons, self.on_system_icons, columns=2))
        self.system_icons.set_visible(self.answers.want_icons)
        cards = self.choice_cards([
            Choice("reversal", "Reversal",
                   "Round, flatter, a colour of its own. By yeyushengfan258",
                   "folder-symbolic", "Recommended", PACK_LINKS["reversal"]),
            Choice("hatter", "Hatter",
                   "Rounded squares, follows your accent colour. By Mibea",
                   "folder-symbolic", None, PACK_LINKS["hatter"]),
            Choice("colloid", "Colloid",
                   "Follows your accent colour. By vinceliuice",
                   "folder-symbolic", None, PACK_LINKS["colloid"]),
            Choice("keep", "Default",
                   "Leaves your current icon theme alone, whatever set it",
                   "action-unavailable-symbolic"),
        ], current, self.on_icons)
        return self.shell(
            "icons", "Icons",
            "Other people's work, fetched from GitHub. Have a look before you "
            "pick.", self.stack(cards, self.icon_preview(), self.system_icons))

    def icon_preview(self):
        """The answer's real icons on the mock's wall, at a size apps use."""
        frame = Gtk.Overlay(overflow=Gtk.Overflow.HIDDEN)
        frame.add_css_class("mock-frame")
        wall = Gtk.Box(height_request=108, hexpand=True)
        wall.add_css_class("mock-wall")
        frame.set_child(wall)
        dock = Gtk.Box(spacing=12, halign=Gtk.Align.CENTER,
                       valign=Gtk.Align.CENTER)
        dock.add_css_class("mock-dock")
        dock.add_css_class("mock-icons")
        self.icon_samples = []
        for name in ICON_SAMPLES:
            image = Gtk.Image(pixel_size=48)
            dock.append(image)
            self.icon_samples.append((image, name))
        frame.add_overlay(dock)
        self.sync_icons()
        return frame

    def sync_icons(self):
        """Point the preview at the answer: a pack's files, or the live theme.

        Keep asks GTK, which is already drawing this window in the theme that
        would be kept. A theme can lack any of these, and an image-missing
        square would say something untrue about it, so that one is left out.
        """
        theme = Gtk.IconTheme.get_for_display(self.get_display())
        folder = os.path.join(self.repo, "gui", "samples", "icons",
                              self.answers.icons)
        for image, name in self.icon_samples:
            if not self.answers.want_icons:
                image.set_visible(theme.has_icon(name))
                image.set_from_icon_name(name)
                continue
            path = os.path.join(folder, "%s-%s.svg"
                                % (name, self.answers.accent))
            if not os.path.isfile(path):
                path = os.path.join(folder, name + ".svg")
            image.set_visible(True)
            image.set_from_gicon(Gio.FileIcon.new(
                Gio.File.new_for_path(path)))

    def on_icons(self, value):
        self.answers.want_icons = value != "keep"
        if value != "keep":
            self.answers.icons = value
        self.system_icons.set_visible(self.answers.want_icons)
        self.sync_icons()

    def on_system_icons(self, value):
        self.answers.system_icons = value

    def page_cursors(self):
        current = self.answers.cursors if self.answers.want_cursors else "keep"
        theme = self.choice_cards([
            Choice("moga", "Aura Moga Neon",
                   "Accent-matched neon pointers. By Moyash",
                   "input-mouse-symbolic", "Recommended", PACK_LINKS["moga"]),
            Choice("aosp", "AOSP",
                   "Android's pointers, scalable with a soft shadow. By Tech-Tac",
                   "input-mouse-symbolic", None, PACK_LINKS["aosp"]),
            Choice("mactahoe", "MacTahoe",
                   "macOS Tahoe style pointers. By vinceliuice",
                   "input-mouse-symbolic", None, PACK_LINKS["mactahoe"]),
            Choice("keep", "Default",
                   "Leaves your current pointer theme alone, whatever set it",
                   "action-unavailable-symbolic"),
        ], current, self.on_cursors)

        # A separate section and a separate flag from the theme above: keeping
        # your own pointer theme is not a statement about its size, so this
        # question stands on its own the same way --cursor-size and --cursors
        # are two independent gsettings keys in install.sh.
        size_current = (self.answers.cursor_size
                        if self.answers.want_cursor_size else "keep")
        sizes = self.size_tiles(size_current)

        return self.shell(
            "cursors", "Pointer",
            "AOSP and MacTahoe are fetched from GitHub; Aura Moga Neon follows "
            "your accent.",
            self.stack(
                self.section("Pointer theme", None, theme),
                self.section("Pointer size",
                             "Pick for your display. Each one is drawn the size "
                             "it will be on this screen. Scaled displays need "
                             "no extra size: GNOME enlarges the pointer with "
                             "them.",
                             sizes)))

    def pointer_file(self):
        """Where the answer's arrow is: shipped, or on this machine for keep.

        Named for the accent, because that is what picks a Moga variant
        (moga_variant_for_accent), and the file names keep that table out of
        this window. Not gui/samples for keep: the theme it means is whichever
        one GNOME has now.
        """
        if not self.answers.want_cursors:
            return pointer_theme_file(interface_setting("cursor-theme")
                                      or "Adwaita")
        name = self.answers.cursors
        if name == "moga":
            name += "-" + self.answers.accent
        return os.path.join(self.repo, "gui", "samples", "pointers",
                            name + ".xcursor.gz")

    def sync_pointers(self):
        path = self.pointer_file()
        for sample, value in self.pointer_samples:
            sample.show_pointer(path, value)

    def size_tiles(self, current):
        """The sizes as tiles, each drawing the chosen pointer at that size."""
        flow = self.flow(5)
        first = None
        rows = [(v, t, sub) for v, t, sub in CURSOR_SIZES]
        rows.append(("keep", "Default", "Keep current"))
        self.pointer_samples = []
        for value, title, subtitle in rows:
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
            card.add_css_class("choice-card")
            sample = PointerSample()
            # Keep draws what it keeps: the size GNOME has now.
            self.pointer_samples.append((
                sample, int(interface_setting("cursor-size") or 24)
                if value == "keep" else int(value)))
            card.append(sample)
            name = Gtk.Label(label=title)
            name.add_css_class("heading")
            card.append(name)
            line = Gtk.Label(label=subtitle)
            line.add_css_class("caption")
            line.add_css_class("dim-label")
            card.append(line)
            pill = Gtk.Label(label="Recommended", halign=Gtk.Align.CENTER)
            pill.add_css_class("reco-pill")
            # Still takes its space on the other tiles, so all five names sit
            # on one line whichever size this display recommends.
            pill.set_opacity(1 if value == self.display_cursor_size else 0)
            card.append(pill)

            check = Gtk.CheckButton(halign=Gtk.Align.CENTER)
            if first is None:
                first = check
            else:
                check.set_group(first)
            check.set_active(value == current)
            if value == current:
                card.add_css_class("selected")
            card.append(check)

            def toggled(button, value=value, card=card):
                if button.get_active():
                    card.add_css_class("selected")
                    self.on_cursor_size(value)
                else:
                    card.remove_css_class("selected")
            check.connect("toggled", toggled)
            click = Gtk.GestureClick()
            click.connect("released", lambda *_a, c=check: c.set_active(True))
            card.add_controller(click)
            self.flow_add(flow, card)
        self.sync_pointers()
        return flow

    def on_cursors(self, value):
        self.answers.want_cursors = value != "keep"
        if value != "keep":
            self.answers.cursors = value
        self.sync_pointers()

    def on_cursor_size(self, value):
        self.answers.want_cursor_size = value != "keep"
        if value != "keep":
            self.answers.cursor_size = value

    def osd_level(self, width, thickness):
        """A level bar: a trough with a capsule of fill on it, 70% along.

        A capsule because the shell's BarLevel rounds the end of the fill too.
        """
        level = Gtk.Overlay(valign=Gtk.Align.CENTER)
        trough = Gtk.Box(height_request=thickness)
        trough.add_css_class("mock-osd-level")
        trough.add_css_class("mock-osd-trough")
        level.set_child(trough)
        fill = Gtk.Box(height_request=thickness, halign=Gtk.Align.START)
        fill.add_css_class("mock-osd-level")
        fill.add_css_class("mock-osd-fill")
        level.add_overlay(fill)
        level.fill = fill
        self.set_level_width(level, width)
        return level

    @staticmethod
    def set_level_width(level, width):
        level.get_child().set_property("width-request", width)
        level.fill.set_property("width-request", round(width * 0.7))

    def osd_stock(self, foot):
        """GNOME's own popup, from the theme's .osd-window: what --no-osd keeps.

        A large icon, the name, and an accent bar. The icon is whatever this
        machine's theme draws, because that popup is not ours.
        """
        stock = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER,
                        valign=Gtk.Align.END, margin_bottom=foot)
        stock.add_css_class("mock-osd-stock")
        stock.append(Gtk.Image(icon_name="audio-volume-high-symbolic",
                               pixel_size=32))
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                        valign=Gtk.Align.CENTER)
        words.append(self.mock_text("osd-stock"))
        words.append(self.osd_level(160, 4))
        stock.append(words)
        return stock

    def osd_preview(self):
        """The volume popup life size, in the design the answers pick.

        Fixed logical pixels, as the stylesheet draws it on every screen. Its
        blur comes from Blur My Shell, which nothing here can do, so the wall's
        soft blobs stand in, as they do in mock_desktop.
        """
        frame = Gtk.Overlay(overflow=Gtk.Overflow.HIDDEN)
        frame.add_css_class("mock-frame")
        wall = Gtk.Box(height_request=120, hexpand=True)
        wall.add_css_class("mock-wall")
        frame.set_child(wall)
        frame.add_overlay(self.mock_bar())
        self.osd_scene(frame, "extensions", 1, 12)
        return frame

    def page_extensions(self):
        frame = self.osd_preview()

        def answer(field, value):
            setattr(self.answers, field, value)
            self.sync_look()

        osd, osd_switch = self.switch_card(
            "audio-volume-high-symbolic", "Volume and brightness popup",
            "Aura Glass's own design rather than GNOME's",
            self.answers.want_osd,
            lambda on: answer("want_osd", on))
        design = self.choice_cards(
            [Choice(value, title, subtitle, "audio-volume-high-symbolic",
                    "Recommended" if value == "capsule" else None)
             for value, title, subtitle in OSD_STYLES],
            self.answers.osd_style,
            lambda value: answer("osd_style", value), columns=2)
        name, name_switch = self.switch_card(
            "audio-speakers-symbolic", "Show device name",
            "Name the speaker or screen on the popup",
            self.answers.osd_device_name,
            lambda on: answer("osd_device_name", on))
        for follower in (name_switch, design):
            osd_switch.bind_property("active", follower, "sensitive",
                                     GObject.BindingFlags.SYNC_CREATE)
        osd_section = self.section("On-screen display", None, frame,
                                   self.stack(osd, design, name, spacing=10))

        if not self.catalogue:
            group = self.section(
                "Extensions",
                "Catalogue unreadable — installing the Core package. Change it "
                "later in Settings.")
            return self.shell(
                "extensions", "Extensions",
                "Small additions to the shell, on top of the foundation.",
                self.stack(osd_section, group))

        current = "full" if (self.answers.extensions is None
                             or len(self.answers.extensions) > 0) else "minimal"
        package = self.choice_cards([
            Choice("full", "Full Experience",
                   "Foundation plus all optional extensions (tray icons, "
                   "tiling, effects, clipboard)",
                   "application-x-addon-symbolic", "Recommended"),
            Choice("minimal", "Minimal",
                   "Foundation only (blur, panel & user themes) — no optional "
                   "extensions",
                   "application-x-addon-symbolic"),
        ], current, self.on_ext_preset_picked, columns=2)

        return self.shell(
            "extensions", "Extensions",
            "Small additions to the shell. Everything is changeable later in "
            "Settings.",
            self.stack(osd_section,
                       self.section("Extension package", None, package)))

    def on_ext_preset_picked(self, value):
        if value == "full":
            self.answers.extensions = [
                e["uuid"] for e in self.catalogue
                if e["tier"] in ("recommended", "full")
            ]
        else:
            self.answers.extensions = []

    def page_gdm(self):
        theme, _switch = self.switch_card(
            "system-lock-screen-symbolic", "Theme the GDM login screen",
            "Frosted glass at the login prompt, following your desktop "
            "wallpaper",
            self.answers.gdm,
            lambda on: setattr(self.answers, "gdm", on))
        monitors, _switch = self.switch_card(
            "video-display-symbolic",
            "Match the login screen to your monitor layout",
            "Fixes GDM otherwise picking its own primary display",
            self.answers.gdm_monitors,
            lambda on: setattr(self.answers, "gdm_monitors", on))
        return self.shell(
            "gdm", "Login screen",
            "System-wide, not just yours — the terminal will ask for your "
            "password.", self.stack(theme, monitors, spacing=10))

    def page_summary(self):
        answers = self.answers
        selected = set(answers.extensions or [])
        core = {e["uuid"] for e in self.catalogue
                if e["tier"] == "recommended"}
        complete = {e["uuid"] for e in self.catalogue
                    if e["tier"] in ("recommended", "full")}
        # None first: an unreadable catalogue leaves no list at all, which
        # install.sh resolves to its own default rather than to Minimal.
        if answers.extensions is None:
            extras = "Full Experience"
        elif not selected:
            extras = "Minimal"
        elif selected == complete:
            extras = "Full Experience"
        elif selected == core:
            extras = "Core"
        else:
            extras = "%d selected (custom)" % len(selected)

        percent = round(float(answers.transparency) * 100)
        word = dict(TRANSPARENCY_MARKS).get(percent)
        pointer = (PACK_NAMES.get(answers.cursors, answers.cursors)
                   if answers.want_cursors else "Kept as it is")
        if answers.want_cursor_size:
            pointer += " · %spx" % answers.cursor_size

        # Every tag here was genuinely pushed to get to this page — advance
        # pushes each applicable page in turn whether or not Skip was the
        # button that moved past it — so pop_to_tag below always has
        # somewhere real to go back to.
        tiles = [
            ("color-select-symbolic", "Accent",
             answers.accent.capitalize(), "accent"),
            ("font-x-generic-symbolic", "Font",
             next(t for v, t, _s in FONTS if v == answers.font), "accent"),
            ("view-grid-symbolic", "Frosted glass",
             "Every app window" if answers.scope == "all"
             else "GTK and GNOME apps", "glass"),
            ("weather-fog-symbolic", "Opacity",
             "%d%%%s" % (percent, " · " + word if word else ""), "glass"),
            ("folder-symbolic", "Icons",
             "%s · %s" % (PACK_NAMES.get(answers.icons, answers.icons),
                          "Lucide system icons"
                          if answers.system_icons == "lucide"
                          else "its own system icons")
             if answers.want_icons else "Kept as they are", "icons"),
            ("input-mouse-symbolic", "Pointer", pointer, "cursors"),
            ("audio-volume-high-symbolic", "Volume popup",
             "GNOME's own" if not answers.want_osd
             else next(t for v, t, _s in OSD_STYLES
                       if v == answers.osd_style)
             + (", with the device name" if answers.osd_device_name else ""),
             "extensions"),
            ("application-x-addon-symbolic", "Extensions", extras,
             "extensions"),
        ]
        if self.gdm_present:
            login = "Left alone"
            if answers.gdm and answers.gdm_monitors:
                login = "Themed, monitors matched"
            elif answers.gdm:
                login = "Themed"
            elif answers.gdm_monitors:
                login = "Monitors matched"
            tiles.append(("system-lock-screen-symbolic", "Login screen", login,
                          "gdm"))

        # Buttons rather than plain text: every answer here was a page back, and
        # "that's wrong" should be one click from fixed rather than Cancel and
        # the whole wizard again from Welcome.
        flow = self.flow(3)
        for icon, caption, value, tag in tiles:
            button = Gtk.Button()
            button.add_css_class("summary-tile")
            row = Gtk.Box(spacing=12)
            badge = self.badge(icon)
            badge.add_css_class("accent")
            row.append(badge)
            words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1,
                            hexpand=True, valign=Gtk.Align.CENTER)
            small = Gtk.Label(label=caption, xalign=0)
            small.add_css_class("caption")
            small.add_css_class("dim-label")
            words.append(small)
            big = Gtk.Label(label=value, xalign=0, wrap=True)
            big.add_css_class("heading")
            words.append(big)
            row.append(words)
            button.set_child(row)
            button.set_tooltip_text("Change this")
            button.connect("clicked",
                           lambda _b, t=tag: self.nav.pop_to_tag(t))
            self.flow_add(flow, button)

        steps = self.flow(3)
        for index, (title, text) in enumerate((
                ("It installs", "The packs download and a window follows the "
                                "progress, step by step."),
                ("The terminal asks", "Your password, and any question, goes "
                                      "in the terminal, never in a window."),
                ("You log back in", "Extensions load into a new session. "
                                    "Retune anything later in Settings."))):
            cell = Gtk.Box(spacing=10)
            number = Gtk.Label(label=str(index + 1), valign=Gtk.Align.START)
            number.add_css_class("next-number")
            cell.append(number)
            words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1,
                            hexpand=True)
            head = Gtk.Label(label=title, xalign=0)
            head.add_css_class("heading")
            words.append(head)
            line = Gtk.Label(label=text, xalign=0, wrap=True)
            line.add_css_class("caption")
            line.add_css_class("dim-label")
            words.append(line)
            cell.append(words)
            self.flow_add(steps, cell)

        return self.shell(
            "summary", "Ready to install",
            "This is the desktop your answers make. Click anything to change "
            "it.",
            self.stack(self.mock_desktop(190, osd="summary"),
                       flow,
                       self.section("What happens next", None, steps)),
            skippable=False, next_label="Install Aura Glass",
            on_next=lambda _tag: self.finish(), maximum=820)


class Application(Adw.Application):
    def __init__(self, repo, gdm_present):
        # NON_UNIQUE: this is a one-shot subprocess whose exit code and
        # stdout are the entire protocol (see the module docstring) — nothing
        # is gained by owning APP_ID on the session bus, and doing so is a
        # trap. If a run is ever orphaned (killed, crashed) while it still
        # holds the name, a plain single-instance app.run() from the *next*
        # ./install.sh returns immediately without activating, leaving
        # self.result None — which reads as "cancelled" and silently exits
        # the installer every time after, for no reason visible from here.
        super().__init__(application_id=APP_ID,
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.repo = repo
        self.gdm_present = gdm_present
        # None until Install is pressed. Closing the window any other way
        # leaves it None, which is how cancelling is reported.
        self.result = None

    def do_activate(self):
        window = self.get_active_window()
        if window is None:
            provider = Gtk.CssProvider()
            provider.load_from_data(CSS.encode("utf-8"))
            # Above the user's gtk.css, as sync_look's provider is.
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(), provider,
                Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)
            window = Window(self, self.repo, self.gdm_present)
        window.present()


def main():
    parser = argparse.ArgumentParser(
        description="The aura-glass setup wizard. Prints the install.sh flags "
                    "it settled on, one per line.")
    parser.add_argument(
        "--repo", default=os.path.dirname(os.path.dirname(
            os.path.abspath(__file__))),
        help="the aura-glass checkout, for bin/aura-glass-ext")
    parser.add_argument(
        "--gdm-present", action="store_true",
        help="there is a GDM to theme, so ask about it")
    opts = parser.parse_args()

    # Real fd 1 is reserved for install.sh's flags (see the module docstring)
    # but is not ours alone for the life of the window: GTK/GLib work between
    # here and Install can spawn things — open_link's browser is the one this
    # was written for — that inherit fd 1 by default and print on it. Duping
    # it aside and pointing the live fd 1 at /dev/null means anything spawned
    # while the window is open writes there instead, whatever it is, and the
    # flags still reach lib/steps-wizard.sh's tempfile through flags_fd.
    flags_fd = os.dup(1)
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, 1)
    os.close(devnull)

    app = Application(opts.repo, opts.gdm_present)
    app.run([sys.argv[0]])

    if app.result is None:
        return 2
    with os.fdopen(flags_fd, "w") as flags:
        for token in app.result:
            print(token, file=flags)
    return 0


if __name__ == "__main__":
    sys.exit(main())
