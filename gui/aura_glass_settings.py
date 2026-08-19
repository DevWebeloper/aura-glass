#!/usr/bin/env python3
"""aura-glass settings — retune an installed aura-glass without the terminal.

    aura-glass-settings

Every control here is a flag install.sh already had. This window reads the
current answer out of ~/.config/aura-glass, shows it, and on Apply runs

    install.sh --settings-only --yes <only the flags that changed>

rather than writing any theme file itself. That division is deliberate: the
precedence between a flag, a $CONF_DIR memo and a default is intricate — see the
resolution block in install.sh and the apply_* functions in lib/steps-dconf.sh —
and a GUI with its own copy of it would drift from the installer within one
release. Passing only what changed means every untouched setting is resolved by
exactly the code that resolved it last time.

--settings-only is what makes that safe to drive from a window: it reapplies the
dconf preset, the CSS and the gsettings, and skips the theme, the extensions and
everything that wants root (the rounded-blur library, GDM). So Apply needs no
password and no terminal to answer a prompt in.

The icon and cursor packs are the one exception, and only when a row here has
actually been changed: asking for a different pack is asking for it to be
installed. A pack already on disk applies instantly — both steps skip when the
theme is there — and one that is not gets fetched, which is why those two rows
sit in their own group saying so. A flagless --settings-only still touches the
network not at all.

Accent is here, but as one of nine names install.sh understands rather than a
colour picker, because it is not this project's setting to own — the shell CSS
reads -st-accent-color and the GTK CSS reads @accent_bg_color, so
Settings -> Appearance already recolours the desktop live. The row exists to keep
the remembered value in step; the button beside it goes to the real thing.

Nor is a custom hex on offer, which looks like an omission and is not: -st-
accent-color is a read-only keyword backed by a nine-value C enum, so a hex
would reach every app window and none of the shell. tokens/tokens.sh has the
long version.

Not everything here rides on Apply. Three kinds of thing cannot:

  the extensions       instant, reversible and unprivileged, but not settings
                       install.sh resolves — so they apply as they are clicked,
                       through bin/aura-glass-ext
  the packages page    a filesystem delete for a pack under $HOME, with no flag
                       or memo behind it; and for one under /usr, a package
                       manager command handed to a terminal, because those
                       files are a package's and deleting them out from under
                       it would leave its database describing files that are
                       gone
  anything root        the dependency install, the rounded-blur library, the
                       login screen, the monitor sync, the uninstall scopes

The last of those used to be absent for a good reason: sudo down a pipe that
nothing can type into blocks forever. The answer is not to run it here but to
open a terminal that has a keyboard attached, which is what run_in_terminal
does — and to say so, rather than starting something that would silently
decline. Those rows report the last state this window read, not a live one:
a spawned terminal is deliberately not waited on, so there is nothing to wait
for.

One thing on the per-app page is not a setting anyone is asked for. This
window's own wm_class is pinned onto the blur allow list and taken off the
block list on every install.sh run, and shown here already pinned, because the
window that explains the glass cannot be the one window without it — unblurred
it argues for an effect while demonstrating its absence. apply_app_blur in
lib/steps-dconf.sh is the copy that reaches dconf; pin_self_allow below is the
copy that decides what the lists here say, so that they say what the next run
will install rather than what the memos hold. That is also why the two list
windows are windows: an Adw.Dialog is drawn inside its parent, and Blur My
Shell blurs behind toplevels, so a sheet had the settings page behind it rather
than the desktop.
"""
import colorsys
import fnmatch
import json
import math
import os
import re
import shutil
import subprocess
import sys

import cairo
import gi

gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

APP_ID = "io.github.DevWebeloper.AuraGlassSettings"

# This window's own wm_class, which is also what its desktop entry declares as
# StartupWMClass (see lib/steps-gui.sh).
#
# It is pinned onto the allow list and taken off the block list whenever there
# is any window blur at all, so the one window whose job is to show you the
# glass is never the one window without it. apply_app_blur in
# lib/steps-dconf.sh is the copy that reaches dconf; the copy here exists so
# the lists this window shows are the lists the next run will install, rather
# than the raw memos it is about to change.
SELF_WM_CLASS = APP_ID

CONF_DIR = os.path.join(GLib.get_user_config_dir(), "aura-glass")

# Accents in the order install.sh lists them, with the default first so the row
# reads as "purple, and eight others" rather than as an alphabetical list.
ACCENTS = ["purple", "blue", "teal", "green", "yellow", "orange", "red", "pink",
           "slate"]

# (id, title, subtitle). The radius rows describe what moves rather than naming
# pixel values: the seven numbers per preset are not a thing to read in a
# subtitle, and tokens/tokens.sh is where they belong.
#
# Six of them, running from square to one step above the shipped look. `pill`
# used to be the top of this list at 46px and is gone; tokens.sh records why,
# and still resolves the name so an old memo installs.
RADIUS_PRESETS = [
    ("flat", "Flat", "Square but for the very corner — 6px windows"),
    ("sharp", "Sharp", "Barely rounded — 10px windows, 8px menus"),
    ("soft", "Soft", "A visible corner, well short of the theme's — 16px "
                     "windows"),
    ("medium", "Medium", "Between soft and the shipped look — 22px windows"),
    ("default", "Default", "What the theme ships — 30px windows, 26px menus"),
    ("rounded", "Rounded", "The roundest on offer — 38px windows, 32px menus"),
]

# What a retired preset resolves to, for a $CONF_DIR memo written before it was
# retired. The same mapping radius_preset_values() in tokens/tokens.sh keeps,
# for the same reason — the window reads that memo directly and would otherwise
# fail on a name its own table no longer has.
RADIUS_PRESET_ALIASES = {"pill": "rounded"}

# The seven surfaces, in the order --radius-custom takes them, which is
# tools/token_manifest.py's RADIUS_TOKENS order.
#
# The bounds and the four preset rows below are the same numbers as
# radius_bounds() and radius_preset_values() in tokens/tokens.sh, written twice.
# That is the arrangement tokens.sh itself describes and defends for the CSS
# — the values live literally where they are used, and a checker makes the
# duplication checked rather than trusted. tools/check-gui-radius.py is that
# checker for this copy.
RADIUS_SURFACES = [
    ("window", "Windows", 6, 38,
     "Every app window, and the blur behind it"),
    ("menu", "Menus", 5, 32,
     "Right-click menus and app menus"),
    ("quick_settings", "Quick Settings", 6, 40,
     "The system menu and the calendar. Larger than a menu by design — Blur My "
     "Shell groups these two together"),
    ("notification", "Notifications", 4, 26,
     "Banners as they arrive, and the stack in the calendar"),
    ("dialog", "Dialogs", 4, 26,
     "Log out, restart, power off"),
    ("popup", "Other popups", 4, 26,
     "Anything the more specific ones above do not claim"),
    ("osd", "Volume and brightness", 2, 16,
     "The pill that appears on a volume key. Its ceiling is lower than the "
     "others — past it the corners meet and the pill turns into an ellipse"),
]

RADIUS_PRESET_VALUES = {
    "flat":    (6, 5, 6, 4, 4, 4, 2),
    "sharp":   (10, 8, 10, 6, 6, 6, 4),
    "soft":    (16, 14, 17, 10, 10, 10, 6),
    "medium":  (22, 19, 24, 15, 15, 15, 9),
    "default": (30, 26, 33, 20, 20, 20, 12),
    "rounded": (38, 32, 40, 26, 26, 26, 16),
}

# --app-transparency takes anything from 70% to 100%; install.sh clamps below 70
# because past that the text stops being readable over a bright wallpaper. The
# bar covers that whole range rather than offering the three buckets alone.
TRANSPARENCY_MIN = 70
TRANSPARENCY_MAX = 100

# The three levels that have been looked at on a screen, marked on the bar so
# they can be found again. install.sh snaps to them: a value that rounds to
# their actor opacity is pulled onto the bucket, so 94% installs as 95% and the
# bar shows 95 after Apply re-reads the memo. That is the truth rather than a
# rounding error, which is why nothing here tries to hide it.
#
# One word each, and no percentage. They used to read "82%\ndeep" over two
# lines, which put three numbers along a bar that was already drawing a fourth —
# the live readout — on top of them. The number moved to the row's own suffix,
# where it has somewhere to be, and these say the thing the number does not.
TRANSPARENCY_MARKS = [
    (82, "deep"),
    (90, "balanced"),
    (95, "subtle"),
]

# --blur-strength scales every blur radius at once. The bounds are
# BLUR_STRENGTH_MIN and BLUR_STRENGTH_MAX in lib/steps-dconf.sh, which is where
# the reasoning for them is; 100 is the tuned set and the default.
BLUR_STRENGTH_MIN = 25
BLUR_STRENGTH_MAX = 200

# Marks on that bar. Percentages of the tuned radii, so the words are relative
# to what the theme ships rather than absolute descriptions of a blur.
BLUR_STRENGTH_MARKS = [
    (50, "crisp"),
    (100, "tuned"),
    (150, "soft"),
]

# What both tint memos hold, and the shipped answer for each. Black is not a
# colour anyone picked — it is the sheets as written, which is why choosing it
# again restores them byte-for-byte rather than approximately.
HEX_COLOR = re.compile(r"^#[0-9a-f]{6}$")
TINT_DEFAULT = "#000000"


def level_to_percent(level):
    """A memo value ("0.90") as a bar position (90)."""
    try:
        pct = round(float(level) * 100)
    except (TypeError, ValueError):
        return 90
    return max(TRANSPARENCY_MIN, min(TRANSPARENCY_MAX, pct))


def percent_to_level(percent):
    """A bar position (90) as the argument install.sh takes ("0.90")."""
    return "%.2f" % (percent / 100.0)


# Icon packs install.sh understands. Colloid follows the accent, so it is one
# entry rather than nine; Reversal ships a colour per accent and is named for the
# one it is built with. "Keep current" is --no-icons: the pack on the system now,
# whatever it is, left alone.
# "Keep current" and "Original" are different answers and both are worth having.
# Keep is a choice not to touch whatever is set right now, whatever that is —
# which after one install is this theme's own pack. Original goes back to what
# the machine had before aura-glass first ran on it, from the snapshot
# gsettings_backup_once takes in preflight.
ICON_PACKS = [
    ("colloid", "Colloid", "Folder icons in a colour of their own"),
    ("reversal", "Reversal", "macOS-style circular icons"),
    ("keep", "Keep current", "Leave the icon theme alone, whatever it is now"),
    ("original", "Original", "Back to the icon theme from before aura-glass, "
                             "captured the first time this version ran here"),
]

# The colour the icons are built in, which is not the accent. install.sh has
# always taken it as part of --icons (reversal-purple), and takes it for Colloid
# now too — so this is one flag with two halves rather than a second setting.
#
# Each pack names its own colours. Colloid's are given in accent terms because
# accent_to_colloid_arg already translates them into Colloid's own spelling,
# where blue is "default" and slate is "grey"; naming them Colloid's way here
# would be a second copy of that mapping. Reversal's are its own, and are not
# the accent list — it ships browns and greys the accents do not, and no teal,
# yellow or slate.
ICON_COLOR_FOLLOW = ("", "Match the accent", "Whatever the accent is set to")
ICON_COLORS = {
    "colloid": [ICON_COLOR_FOLLOW] + [(a, a.capitalize(), "") for a in ACCENTS],
    "reversal": [ICON_COLOR_FOLLOW] + [
        (c, c.capitalize(), "") for c in
        ("default", "black", "blue", "brown", "cyan", "green", "grey",
         "lightblue", "orange", "pink", "purple", "red")],
    # Neither of these is a pack with colours to pick from.
    "keep": [ICON_COLOR_FOLLOW],
    "original": [ICON_COLOR_FOLLOW],
}


def split_icons(value):
    """"colloid-teal" as ("colloid", "teal"). A bare family follows the accent."""
    if value in ("keep", "original"):
        return value, ""
    family, _, color = value.partition("-")
    if family not in ("colloid", "reversal"):
        return "colloid", ""
    if color not in [c[0] for c in ICON_COLORS[family]]:
        color = ""
    return family, color


def join_icons(family, color):
    """The other way, and the spelling install.sh's --icons takes."""
    if family in ("keep", "original") or not color:
        return family
    return "%s-%s" % (family, color)

CURSOR_PACKS = [
    ("adwaita", "Adwaita", "Ships with GNOME. Crisper at every size"),
    ("mactahoe", "MacTahoe", "The macOS pointer set"),
    ("keep", "Keep current", "Leave the cursor theme alone, whatever it is now"),
    ("original", "Original", "Back to the pointer from before aura-glass, "
                             "captured the first time this version ran here"),
]

# What install.sh calls the three answers. It was a dropdown once; it is two
# switches now, because it was never really one question — whether windows get a
# blur behind them at all, and whether that reaches past GTK and GNOME apps, are
# separate settings in install.sh (WANT_WINDOW_BLUR and APP_BLUR_SCOPE) and were
# only ever folded together here. This stays as the set of values Settings.scope
# is allowed to hold.
BLUR_SCOPES = ("gtk", "all", "none")

# The three modes, in the order the tabs show them. Solid is last because it is
# the one that takes the theme away.
GLASS_MODES = ["frosted", "transparent", "solid"]

# Titlebar buttons. Two answers rather than the free string the key takes: see
# apply_window_buttons in lib/steps-dconf.sh for why the rest of what
# button-layout can express is not offered.
WINDOW_BUTTON_LAYOUTS = [
    ("", "Leave as it is", "Whatever GNOME or Tweaks has set. Not touched"),
    ("close", "Close only", "One button. The other two go to the right-click "
                            "menu and the keyboard"),
    ("all", "Minimize, maximize and close", "All three, the way GNOME ships"),
]

# The sidebar: (id, title, icon, builder method), in the order shown.
#
# Order is not only presentation — the builders run in it, and a page whose
# widgets another page's builder reads has to come first. Glass before Apps is
# the live case: the per-app list asks the blur rows which list is active.
NAV_SECTIONS = [
    ("look", "Look", "applications-graphics-symbolic", "_build_look_page"),
    ("radius", "Corner rounding", "circle-outline-thick-symbolic",
     "_build_radius_page"),
    ("glass", "Glass", "weather-fog-symbolic", "_build_glass_page"),
    ("apps", "Per-app blur", "view-list-symbolic", "_build_apps_page"),
    ("windows", "Window controls", "window-new-symbolic",
     "_build_window_controls_page"),
    ("icons", "Icons and pointer", "folder-symbolic", "_build_icons_page"),
    ("packages", "Packages", "package-x-generic-symbolic",
     "_build_packages_page"),
    ("extensions", "Extensions", "application-x-addon-symbolic",
     "_build_extensions_page"),
    ("system", "System", "emblem-system-symbolic", "_build_system_page"),
    ("updates", "Updates", "software-update-available-symbolic",
     "_build_updates_page"),
    # Last, and on its own, because everything above it is a less drastic
    # answer to "I do not want this bit".
    ("uninstall", "Uninstall", "user-trash-symbolic", "_build_uninstall_page"),
]


# The three families install.sh fetches, and the ones uninstall.sh --assets
# already knows to remove. Anything else under an icon directory belongs to the
# distribution or to the user and is not this window's to offer up.
ICON_PACK_FAMILIES = ("Colloid", "Reversal", "MacTahoe")

# Where a pack can be. The first two are ours to delete from; the rest are the
# package manager's, and a window that offered to rm -rf out of /usr would be
# picking a fight with pacman on the user's behalf.
PACK_DIRS_MINE = (os.path.join(GLib.get_user_data_dir(), "icons"),
                  os.path.expanduser("~/.icons"))
PACK_DIRS_SYSTEM = ("/usr/share/icons", "/usr/local/share/icons")


def pack_family(name):
    """Which family a directory belongs to, or None."""
    for family in ICON_PACK_FAMILIES:
        if name.lower().startswith(family.lower()):
            return family
    return None


def theme_stem(name):
    """A theme name with any light/dark half stripped.

    Colloid ships -Light and -Dark, Reversal ships the bare name plus -dark, and
    the icon-sync agent swaps between them as the desktop's colour scheme
    changes. So the halves of a pair are both in use when either is set, and
    saying otherwise would offer to delete half of the theme in the screenshot.
    """
    stem = name
    for suffix in ("-Dark", "-Light", "-dark", "-light"):
        if stem.endswith(suffix):
            stem = stem[:-len(suffix)]
    return stem.lower()


def installed_packs():
    """Every aura-glass icon or cursor pack on disk.

    Yields (name, path, mine) with mine saying whether it is under $HOME and so
    removable without root.
    """
    seen = set()
    for mine, roots in ((True, PACK_DIRS_MINE), (False, PACK_DIRS_SYSTEM)):
        for root in roots:
            try:
                names = sorted(os.listdir(root))
            except OSError:
                continue
            for name in names:
                path = os.path.join(root, name)
                if name in seen or not pack_family(name):
                    continue
                if not os.path.isdir(path):
                    continue
                seen.add(name)
                yield name, path, mine


def dir_size(path):
    """Bytes under a directory. Best effort — an unreadable corner counts as 0."""
    total = 0
    for root, _dirs, files in os.walk(path, onerror=lambda _e: None):
        for name in files:
            try:
                st = os.lstat(os.path.join(root, name))
            except OSError:
                continue
            total += st.st_size
    return total


def human_size(count):
    for unit in ("B", "kB", "MB", "GB"):
        if count < 1024 or unit == "GB":
            return "%.0f %s" % (count, unit) if unit != "GB" \
                else "%.1f GB" % count
        count /= 1024.0


def distro_answer(repo, snippet):
    """Ask lib/distro.sh one question, on one line, or None.

    Shelled out rather than reimplemented. Which package manager this machine
    has, what it calls a query and what it calls a removal are all resolved in
    exactly one place — detect_distro and the two functions beside it — and a
    Python copy of that case statement would be a second thing to update the
    next time a family is added to it.

    Every caller here is answering a question about a directory that is already
    on screen, so a failure is a row without an extra fact on it rather than
    anything to report.
    """
    if repo is None:
        return None
    script = (". %s/lib/common.sh; . %s/lib/distro.sh; "
              "detect_distro >/dev/null 2>&1; %s"
              % (GLib.shell_quote(repo), GLib.shell_quote(repo), snippet))
    try:
        res = subprocess.run(["bash", "-c", script], capture_output=True,
                             text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    answer = res.stdout.strip().splitlines()
    return answer[0].strip() if answer and answer[0].strip() else None


def pkg_owner(repo, path):
    """The distribution package a path belongs to, or None."""
    return distro_answer(repo, "pkg_owner %s" % GLib.shell_quote(path))


def pkg_remove_cmd(repo, package):
    """The command that would remove a package, for a terminal to run."""
    if not package:
        return None
    return distro_answer(repo,
                         "pkg_remove_cmd %s" % GLib.shell_quote(package))


# Terminals, and how each takes a command.
#
# They do not agree. gnome-terminal and the two GNOME terminals that followed it
# take everything after --, konsole and xterm take -e, and kitty and foot take
# the command as their own trailing arguments. Verified for ptyxis against its
# own --help on the machine this was written on; the rest are long-settled
# conventions.
#
# Order is "what this desktop most likely has", not preference: $TERMINAL first
# because someone who set it meant it, then GNOME's own, then the rest.
TERMINALS = [
    ("ptyxis",             lambda c: ["ptyxis", "--", "bash", "-c", c]),
    ("kgx",                lambda c: ["kgx", "--", "bash", "-c", c]),
    ("gnome-terminal",     lambda c: ["gnome-terminal", "--", "bash", "-c", c]),
    ("konsole",            lambda c: ["konsole", "-e", "bash", "-c", c]),
    ("alacritty",          lambda c: ["alacritty", "-e", "bash", "-c", c]),
    ("kitty",              lambda c: ["kitty", "bash", "-c", c]),
    ("foot",               lambda c: ["foot", "bash", "-c", c]),
    ("wezterm",            lambda c: ["wezterm", "start", "--",
                                      "bash", "-c", c]),
    ("x-terminal-emulator", lambda c: ["x-terminal-emulator", "-e",
                                       "bash", "-c", c]),
    ("xterm",              lambda c: ["xterm", "-e", "bash", "-c", c]),
]


def find_terminal():
    """(name, argv builder) for a terminal on this machine, or (None, None)."""
    preferred = os.environ.get("TERMINAL", "").strip()
    if preferred and shutil.which(preferred):
        for name, build in TERMINALS:
            if os.path.basename(preferred) == name:
                return preferred, build
        # Something we have no table entry for. -- is the commonest spelling and
        # the one every GNOME terminal takes, so it is the better guess than -e.
        return preferred, (lambda c, p=preferred: [p, "--", "bash", "-c", c])

    for name, build in TERMINALS:
        if shutil.which(name):
            return name, build
    return None, None


def keep_open(command):
    """A command, wrapped so the window stays up with its output on screen.

    A terminal that closes the instant the command ends is no better than the
    in-window log for anything that failed — and these are the runs that ask for
    a password, so the output is the whole point of using a terminal at all.
    """
    return (
        '%s\n'
        'status=$?\n'
        'printf "\\n"\n'
        'if [ "$status" -eq 0 ]; then printf "Finished.\\n"; '
        'else printf "Exited with status %%s.\\n" "$status"; fi\n'
        'read -r -p "Press Enter to close this window. " _\n' % command)


def parse_radius_custom(raw):
    """The radius-custom memo as seven ints, or None if it is not seven ints.

    None rather than a partial answer or a default: install.sh validates the
    same string and refuses a bad one, so a window that quietly repaired it
    would be showing something the installer would not accept.
    """
    parts = [p.strip() for p in (raw or "").split(",") if p.strip()]
    if len(parts) != len(RADIUS_SURFACES):
        return None
    try:
        values = [int(p) for p in parts]
    except ValueError:
        return None
    for value, (_id, _title, low, high, _sub) in zip(values, RADIUS_SURFACES):
        if not low <= value <= high:
            return None
    return tuple(values)


def read_memo(name, default=""):
    """One value from one file, the way install.sh remembers things."""
    try:
        with open(os.path.join(CONF_DIR, name), encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return default


def read_mode_memo(mode, key, default):
    """One value out of a mode's drawer under $CONF_DIR/modes/<mode>/.

    The drawer is written by save_glass_mode_memos in lib/steps-modes.sh at the
    end of every run. Missing is normal — a mode that has never been applied on
    this machine has no drawer — so every read carries the seed that
    seed_glass_mode would have used, and the two lists have to stay in step.
    """
    try:
        with open(os.path.join(CONF_DIR, "modes", mode, key),
                  encoding="utf-8") as fh:
            value = fh.read().strip()
    except OSError:
        return default
    return value or default


def read_memo_lines(name):
    """A list memo — one wm_class pattern per line, blanks dropped."""
    raw = read_memo(name)
    return [line.strip() for line in raw.splitlines() if line.strip()]


def read_hex_memo(name):
    """A colour memo, or black — which is the shipped tint and the default."""
    value = read_memo(name, "").lower()
    return value if HEX_COLOR.match(value) else "#000000"


def read_percent_memo(name):
    """The blur strength memo, bounded, or 100 — the tuned radii."""
    try:
        value = int(read_memo(name, ""))
    except ValueError:
        return 100
    return max(BLUR_STRENGTH_MIN, min(BLUR_STRENGTH_MAX, value))


def pattern_matches(pattern, wm_class):
    """Whether one Blur My Shell pattern covers a wm_class.

    wildcardToRegex in the extension's components/applications.js anchors the
    pattern at both ends, turns * into .* and ? into ., and compiles with the i
    flag — which is fnmatch over two lowercased strings. The one difference is
    [abc]: the extension escapes the brackets and matches them literally, while
    fnmatch reads a character set. Nobody's wm_class has brackets in it, and
    the two things this is asked — does the allow list already cover this
    window, and would the block list exclude it — are both about a name that
    does not.
    """
    return fnmatch.fnmatchcase(wm_class.lower(), pattern.strip().lower())


def pin_self_allow(lines):
    """The allow list with this window on it, unless something already covers it."""
    if any(pattern_matches(p, SELF_WM_CLASS) for p in lines):
        return list(lines)
    return [SELF_WM_CLASS] + list(lines)


def pin_self_block(lines):
    """The block list with anything that would exclude this window dropped."""
    return [p for p in lines if not pattern_matches(p, SELF_WM_CLASS)]


# Filled on first use, from every desktop entry on the machine rather than only
# the ones that should_show() — a hidden entry still knows what its app is
# called, and a name is all this map is for.
_APP_NAMES = None

# Words a title-case pass would get wrong. Short on purpose: this is a fallback
# for patterns no installed app claims, not a directory of software.
NAME_WORDS = {
    "gnome": "GNOME", "kde": "KDE", "xfce": "Xfce", "vlc": "VLC",
    "gimp": "GIMP", "obs": "OBS", "vs": "VS", "ding": "Desktop icons",
}


def app_names():
    """wm_class -> the name the app calls itself, lowercased keys."""
    global _APP_NAMES
    if _APP_NAMES is None:
        names = {}
        for info in Gio.AppInfo.get_all():
            wm = wm_class_for(info)
            if wm:
                names.setdefault(wm.lower(), info.get_display_name() or wm)
        _APP_NAMES = names
    return _APP_NAMES


def app_name(pattern):
    """A wm_class pattern as the name of the app it is for.

    "org.gnome.Nautilus" is what Blur My Shell needs and "Files" is what the
    user pointed at, so the lists show the name and keep the pattern under it.
    An installed app answers for itself; for a pattern nothing on this machine
    claims — most of the block list, which names browsers by wildcard — the
    name is read out of the pattern, because "Chrome" from *chrome* is still
    better than *chrome*.
    """
    core = pattern.strip().strip("*")
    if not core:
        return "Every window"
    names = app_names()
    for key in (pattern.strip().lower(), core.lower()):
        if key in names:
            return names[key]
    # org.gnome.Nautilus -> Nautilus, com.desktop.ding -> ding: the reverse-DNS
    # prefix is a vendor, and the last segment is the name.
    tail = core.rsplit(".", 1)[-1] or core
    words = [w for w in tail.replace("_", "-").split("-") if w]
    if not words:
        return core
    return " ".join(NAME_WORDS.get(w.lower(), w[:1].upper() + w[1:])
                    for w in words)


# Typed into the picker's entry, and read back under it as you type. The entry
# is the only place in the window that asks anyone to know what a wm_class is,
# so it is the one place worth spending a sentence of prose on.
#
# Written from the text as typed rather than from a real parse. What is wanted
# here is an intention read back — someone who typed "chrome" meaning "anything
# Chrome" needs to be told it will match only that exact class, and a matcher
# that agreed with Blur My Shell down to the last case fold would still not tell
# them that.
def describe_pattern(text):
    text = text.strip()
    if not text:
        return ""
    if "," in text:
        return ("Commas separate entries, so they cannot be part of one. This "
                "will be added with them dropped.")
    core = text.strip("*")
    if not core:
        return "Only wildcards — that matches every window. Add something to it."
    lead, trail = text.startswith("*"), text.endswith("*")
    if lead and trail:
        return 'Matches any window whose class contains "%s".' % core
    if trail:
        return 'Matches any window whose class starts with "%s".' % core
    if lead:
        return 'Matches any window whose class ends with "%s".' % core
    return ('Matches only windows whose class is exactly "%s" — put a * on '
            'either side to widen it.' % text)


# Shown in the picker above the entry. Three, because they are the three shapes
# the entry takes: one app named outright, a wildcard covering an app that
# spells itself several ways, and a bare lowercase name that looks like a typo
# until you know it is not.
PATTERN_EXAMPLES = [
    ("org.gnome.Nautilus",
     "One app, exactly. This is what picking from the list below writes"),
    ("*chrome*",
     "Every spelling Chrome uses — google-chrome, Google-chrome, chromium"),
    ("code",
     "VS Code, which announces itself under that bare name and no other"),
]


# Four things libadwaita has no style class for: the preset cards, the badge
# pill, the tip card and the dots that make a card read as a window.
#
# Generated rather than shipped as a file under css/, because none of it is the
# theme — it styles this window and nothing else, and the radius rules are read
# straight out of RADIUS_PRESET_VALUES so a card cannot show a corner its preset
# does not set.
def window_css():
    parts = ["""
.aura-tip {
  padding: 12px;
  border-radius: 12px;
  background-color: alpha(@window_fg_color, 0.05);
  border: 1px solid alpha(@window_fg_color, 0.10);
}
.aura-tip image {
  color: @warning_color;
}

.aura-badge {
  padding: 2px 10px;
  border-radius: 99px;
  background-color: alpha(@window_fg_color, 0.09);
}
.aura-badge.on {
  background-color: alpha(@accent_bg_color, 0.22);
  color: @accent_color;
}

/* The button behind a preset card is there for the click, the focus ring and
 * the keyboard, and for nothing you can see — the frame inside it is the whole
 * of the picture, so the button gives up its own background and padding. */
button.aura-preset {
  padding: 0;
  border: none;
  background: none;
  box-shadow: none;
  min-width: 0;
  min-height: 0;
}
.aura-preset-window {
  background-color: alpha(@window_fg_color, 0.06);
  border: 2px solid alpha(@window_fg_color, 0.12);
}
button.aura-preset:hover .aura-preset-window {
  background-color: alpha(@window_fg_color, 0.11);
}
.aura-preset-window.on {
  border-color: @accent_bg_color;
  background-color: alpha(@accent_bg_color, 0.13);
}
.aura-preset-dot {
  border-radius: 99px;
  background-color: alpha(@window_fg_color, 0.25);
}
"""]
    for ident, values in RADIUS_PRESET_VALUES.items():
        parts.append(".aura-preset-%s { border-radius: %dpx; }\n"
                     % (ident, values[0]))
    return "".join(parts)


def install_css():
    """Put window_css() on the display, above the theme's own sheet.

    Above it on purpose. install.sh writes the theme to ~/.config/gtk-4.0/gtk.css,
    which GTK loads at USER priority — higher than APPLICATION — so a plain
    application provider would lose `button` to gtk4-20-buttons.css and the
    preset cards would come back wearing button chrome. One over USER is the
    smallest number that keeps this window's own four classes to itself.
    """
    display = Gdk.Display.get_default()
    if display is None:
        return
    provider = Gtk.CssProvider()
    css = window_css()
    if hasattr(provider, "load_from_string"):    # GTK 4.12 and up
        provider.load_from_string(css)
    else:
        provider.load_from_data(css.encode("utf-8"))
    Gtk.StyleContext.add_provider_for_display(
        display, provider, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)


def tip_card(text):
    """A note to be read before the rows it is about, with markup allowed.

    A row would be shorter and this is not one, because Adw.PreferencesGroup
    puts every non-row child after its list box — so a warning about the
    switches below it cannot live in their group. It gets a group of its own.
    """
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
    box.add_css_class("aura-tip")
    icon = Gtk.Image.new_from_icon_name("dialog-warning-symbolic")
    icon.set_valign(Gtk.Align.START)
    box.append(icon)
    box.append(Gtk.Label(label=text, xalign=0, wrap=True, hexpand=True,
                         use_markup=True))
    group = Adw.PreferencesGroup()
    group.add(box)
    return group


def parse_hex(value):
    """A #rrggbb string as a Gdk.RGBA, falling back to the shipped black."""
    rgba = Gdk.RGBA()
    if not rgba.parse(value):
        rgba.parse(TINT_DEFAULT)
    return rgba


def rgba_hex(rgba):
    """A Gdk.RGBA as the #rrggbb install.sh takes. Alpha is dropped.

    The colour buttons are opened with_alpha=False, so there is none to keep —
    how much of a surface shows through is Opacity's question, and a tint that
    carried its own alpha would be a second answer to it.
    """
    return "#%02x%02x%02x" % (round(rgba.red * 255), round(rgba.green * 255),
                              round(rgba.blue * 255))


def mix_rgb(base, tint, weight):
    """base mixed toward tint, both (r, g, b) in 0-1, weight of the tint.

    The GTK sheet's own arithmetic: mix(@window_bg_color, TINT, weight), which
    is what css/gtk4-transparency.css writes for every translucent ground.
    """
    return tuple(b * (1 - weight) + t * weight for b, t in zip(base, tint))


def hue_shift(rgb, tint):
    """One shell ground given the tint's colour and left at its own lightness.

    The rule tools/apply-shell-tint.py applies to the installed sheets, in the
    one place the window needs to draw the same answer. That tool is where the
    reasoning lives and it is the copy that reaches the disk; this is only ever
    used to draw a preview of what it will do, so the two disagreeing would
    show a wrong picture rather than install a wrong colour.
    """
    _hue, lightness, saturation = colorsys.rgb_to_hls(*rgb)
    tint_hue, _l, tint_saturation = colorsys.rgb_to_hls(*tint)
    if tint_saturation <= 0.001:
        return rgb
    return colorsys.hls_to_rgb(tint_hue, lightness, tint_saturation)


def accent_rgba(widget):
    """The desktop's accent colour, as the one thing this window paints in it.

    Read from libadwaita rather than parsed out of the CSS, so it follows
    Settings -> Appearance live like everything else here does. The literal is
    only reached on a libadwaita too old to answer, where a wrong purple is a
    better outcome than a traceback in a draw handler.
    """
    manager = Adw.StyleManager.get_default()
    if hasattr(manager, "get_accent_color_rgba"):
        return manager.get_accent_color_rgba()
    rgba = Gdk.RGBA()
    rgba.parse("#9141ac")
    return rgba


def tinted(rgba, alpha):
    """One colour at a different alpha, without mutating the original."""
    out = Gdk.RGBA()
    out.red, out.green, out.blue, out.alpha = (rgba.red, rgba.green, rgba.blue,
                                               alpha)
    return out


def rounded_path(cr, x, y, w, h, r):
    """A rounded rectangle on the context's current path."""
    # Clamped rather than trusted. The OSD is a 23px-tall strip in here and its
    # ceiling is 16, so an unclamped arc would cross the middle of the shape and
    # cairo would draw the corners inside out.
    r = max(0.0, min(r, w / 2.0, h / 2.0))
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


# Each surface as a box inside the preview plate, in fractions of it:
# (width, height, y-centre). x is centred for all seven — the shapes are told
# apart by their proportions and their furniture, not by where they sit.
PREVIEW_SHAPES = {
    "window":         (0.60, 0.70, 0.50),
    "menu":           (0.26, 0.62, 0.50),
    "quick_settings": (0.46, 0.66, 0.50),
    "notification":   (0.56, 0.30, 0.44),
    "dialog":         (0.44, 0.52, 0.48),
    "popup":          (0.30, 0.34, 0.48),
    "osd":            (0.42, 0.13, 0.55),
}


class RadiusPreview(Gtk.DrawingArea):
    """The surface being edited, drawn at whatever its row currently says.

    One box for all seven rather than seven boxes. Every surface is a rounded
    rectangle and six of them would have been six rounded rectangles in a
    column, which is a lot of page for one shape repeated — so the box shows
    the surface whose row the pointer is on, and the row you are not touching
    does not need a picture of itself.

    Radii are drawn at 1:1 against a shape a fraction of a real window's size,
    which exaggerates them. That is the same deliberate choice the preset cards
    above make and for the same reason: scaled honestly, 38px on a 250px-wide
    drawing would land at 8 and every value would look alike.

    The two callables are read at draw time rather than being pushed in on
    every change, so there is one source for what is on screen — the seven spin
    rows — and nothing to keep in step with them.
    """

    def __init__(self, values, active):
        super().__init__(hexpand=True)
        self._values = values      # () -> {ident: pixels}
        self._active = active      # () -> ident being edited, or None
        self.set_draw_func(self._draw)

    def _draw(self, _area, cr, width, height):
        fg = self.get_color()
        accent = accent_rgba(self)
        values = self._values()
        live = self._active()
        ident = live or "window"
        radius = values.get(ident, 0)

        # The plate. Something for the shape to be rounded *against* — a
        # rounded corner over a flat background reads as a corner; over nothing
        # it reads as a gap.
        cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.05)
        rounded_path(cr, 1, 1, width - 2, height - 2, 12)
        cr.fill()

        fraction_w, fraction_h, centre = PREVIEW_SHAPES[ident]
        w = width * fraction_w
        h = height * fraction_h
        x = (width - w) / 2.0
        y = height * centre - h / 2.0

        rounded_path(cr, x, y, w, h, radius)
        cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.13)
        cr.fill_preserve()

        # Accent while the pointer is on the row that moves this value, plain
        # otherwise. The border is the answer to "which of these am I editing",
        # so it is only ever coloured while something is being edited.
        edge = accent if live else tinted(fg, 0.22)
        cr.set_source_rgba(edge.red, edge.green, edge.blue,
                           1.0 if live else 0.22)
        cr.set_line_width(2)
        cr.stroke()

        self._furniture(cr, ident, x, y, w, h, radius, fg)
        self._caption(cr, ident, radius, width, height, fg)

    def _furniture(self, cr, ident, x, y, w, h, radius, fg):
        """What makes a rounded rectangle read as the surface it stands for."""
        def bar(bx, by, bw, bh, alpha=0.20, r=None):
            cr.set_source_rgba(fg.red, fg.green, fg.blue, alpha)
            rounded_path(cr, bx, by, bw, bh, bh / 2.0 if r is None else r)
            cr.fill()

        pad = max(8.0, radius * 0.45)

        if ident == "window":
            for i in range(3):
                cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.25)
                cr.arc(x + pad + i * 11, y + pad + 1, 3.5, 0, 2 * math.pi)
                cr.fill()
            bar(x + pad, y + h * 0.42, w * 0.55, 6)
            bar(x + pad, y + h * 0.42 + 14, w * 0.34, 6)
        elif ident == "menu":
            for i in range(3):
                bar(x + pad, y + pad + i * 16, w - pad * 2, 6)
        elif ident == "quick_settings":
            cell_w = (w - pad * 2 - 8) / 2.0
            cell_h = (h - pad * 2 - 8) / 2.0
            for row in range(2):
                for col in range(2):
                    bar(x + pad + col * (cell_w + 8),
                        y + pad + row * (cell_h + 8), cell_w, cell_h,
                        alpha=0.16, r=min(cell_h / 2.0, radius * 0.6))
        elif ident == "notification":
            icon = min(h - pad * 2, 22)
            bar(x + pad, y + (h - icon) / 2.0, icon, icon, alpha=0.22,
                r=icon / 3.0)
            bar(x + pad * 2 + icon, y + h * 0.34, w * 0.42, 6)
            bar(x + pad * 2 + icon, y + h * 0.34 + 13, w * 0.28, 6)
        elif ident == "dialog":
            bar(x + pad, y + pad, w - pad * 2, 6)
            bar(x + pad, y + pad + 13, (w - pad * 2) * 0.7, 6)
            button = (w - pad * 2 - 8) / 2.0
            for i in range(2):
                bar(x + pad + i * (button + 8), y + h - pad - 16, button, 16,
                    alpha=0.18, r=min(8, radius * 0.6))
        elif ident == "popup":
            bar(x + pad, y + h / 2.0 - 3, w - pad * 2, 6)
        elif ident == "osd":
            inset = min(pad, h * 0.3)
            track = h - inset * 2
            bar(x + inset, y + inset, w - inset * 2, track, alpha=0.14)
            bar(x + inset, y + inset, (w - inset * 2) * 0.6, track, alpha=0.30)

    def _caption(self, cr, ident, radius, width, height, fg):
        title = next(s[1] for s in RADIUS_SURFACES if s[0] == ident)
        cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.55)
        cr.select_font_face("Cantarell", cairo.FONT_SLANT_NORMAL,
                            cairo.FONT_WEIGHT_NORMAL)
        cr.set_font_size(11)
        cr.move_to(14, height - 12)
        cr.show_text("%s — %dpx" % (title, radius))


def open_over(window, parent):
    """Show one of this app's own windows over another, modal.

    A real toplevel rather than the Adw.Dialog these two used to be. A dialog is
    drawn inside its parent, and Blur My Shell blurs behind windows — so an
    in-window sheet has the parent's own content behind it rather than the blur,
    which made the two per-app lists the one place where the glass stopped. A
    toplevel carries this app's wm_class, which is the name the allow list has
    pinned, so it gets the same blur and the same translucency as the window it
    came out of.

    Escape closes it, which is the one thing an Adw.Dialog gave for free.
    """
    window.set_transient_for(parent)
    window.set_modal(True)
    # Registered with the application, walking up because the picker's parent is
    # the list window rather than the main one. Without this GTK does not count
    # it as one of the app's windows, and it outlives a quit.
    owner = parent
    while owner is not None and owner.get_application() is None:
        owner = owner.get_transient_for()
    if owner is not None:
        window.set_application(owner.get_application())
    escape = Gtk.ShortcutController()
    escape.add_shortcut(Gtk.Shortcut(
        trigger=Gtk.ShortcutTrigger.parse_string("Escape"),
        action=Gtk.CallbackAction.new(lambda w, _args: w.close() or True)))
    window.add_controller(escape)
    window.present()
    return window


def plain_row(row, title, subtitle=None):
    """Set a row's text as text rather than as Pango markup.

    Every title in this window that is not a literal written here is somebody
    else's — an app's display name, a wm_class the user typed, a directory on
    disk, an extension description. An & in any of them is ordinary, and
    "Vitals — CPU, RAM & network monitor" is one of ours; with markup on, Pango
    rejects the whole string and the row renders empty.

    The title has to be set through this rather than at construction, because
    the markup is parsed when the title is set — turning it off afterwards is
    too late for a title the constructor already took.
    """
    row.set_use_markup(False)
    row.set_title(title)
    if subtitle is not None:
        row.set_subtitle(subtitle)
    return row


def wm_class_for(appinfo):
    """The wm_class Blur My Shell will most likely see for an installed app.

    StartupWMClass is the app telling us outright, and is right when it is there.
    Otherwise the desktop id without its suffix is the convention GTK apps follow
    — org.gnome.Nautilus.desktop announces itself as org.gnome.Nautilus — and is
    a guess, which is why the picker shows it before it is added rather than
    adding it silently.
    """
    wm = appinfo.get_string("StartupWMClass")
    if wm:
        return wm
    ident = appinfo.get_id() or ""
    return ident[:-len(".desktop")] if ident.endswith(".desktop") else ident


def find_repo():
    """Where install.sh is.

    install_gui records the checkout it ran from, because install.sh needs css/,
    dconf/ and lib/ beside it and a settings window has no way to guess where
    those went. A recorded path that no longer holds an install.sh is reported
    rather than worked around — the repo having been moved or deleted is a thing
    the user has to fix, and silently doing nothing would look like Apply being
    broken.
    """
    recorded = read_memo("repo-path")
    if recorded and os.path.isfile(os.path.join(recorded, "install.sh")):
        return recorded
    # Running straight out of a checkout, before anything is installed.
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if os.path.isfile(os.path.join(here, "install.sh")):
        return here
    return None


def git_out(repo, *args):
    """A git command's stdout, or None if it failed. Never raises."""
    try:
        res = subprocess.run(["git", "-C", repo] + list(args),
                             capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None
    return res.stdout.strip() if res.returncode == 0 else None


# main and master are the released line. Anything else is a branch someone is
# testing, and a detached HEAD is a release tag checked out rather than a branch
# with commits to follow. bin/aura-glass-update-check splits on exactly this, and
# the two have to agree: it decides what "an update" means, and this decides what
# the window calls the thing that is installed.
RELEASE_BRANCHES = ("main", "master")


def current_branch(repo):
    """The branch this checkout is on, or None on a detached HEAD."""
    if not repo:
        return None
    branch = git_out(repo, "rev-parse", "--abbrev-ref", "HEAD")
    return None if branch in (None, "HEAD") else branch


def is_test_build(repo):
    """Whether this checkout follows a branch's commits instead of release tags."""
    branch = current_branch(repo)
    return branch is not None and branch not in RELEASE_BRANCHES


def installed_version(repo):
    """What is installed, in the terms its own line is measured in.

    A release is a tag. A test build has no tag of its own — the newest one it
    can see belongs to a release cut before the branch existed, and naming the
    checkout after it would claim it holds a release it does not — so it is named
    for the branch and the commit, the way the update check names it.
    """
    if not repo:
        return None
    branch = current_branch(repo)
    if branch is None or branch in RELEASE_BRANCHES:
        return git_out(repo, "describe", "--tags", "--abbrev=0")
    short = git_out(repo, "rev-parse", "--short=7", "HEAD")
    return "%s@%s" % (branch, short) if short else None


def update_blockers(repo):
    """Why `git pull` here would be a bad idea. Empty list means go ahead.

    Updating edits the user's working tree, which is the most destructive thing
    this window can do. Every one of these is a case where pulling would either
    fail confusingly or throw away work, so each is refused with the reason
    rather than worked around — stashing on someone's behalf is not this
    program's decision to make.
    """
    if not repo:
        return ["The aura-glass checkout is gone."]

    reasons = []
    if git_out(repo, "rev-parse", "--is-inside-work-tree") != "true":
        return ["%s is not a git checkout." % repo]

    if git_out(repo, "status", "--porcelain"):
        reasons.append("You have uncommitted changes there. Commit or stash "
                       "them first — this will not do it for you.")

    branch = git_out(repo, "rev-parse", "--abbrev-ref", "HEAD")
    if branch in (None, "HEAD"):
        reasons.append("The checkout is on a detached HEAD rather than a branch.")
    else:
        # Being on a branch other than main is not a blocker: it is the other
        # line this window knows about, and pulling it is what someone testing
        # that branch asked for. What still has to hold either way is that there
        # is a remote branch to pull from — and --ff-only, which is what actually
        # refuses a checkout whose history has diverged from it.
        upstream = git_out(repo, "rev-parse", "--abbrev-ref",
                           "--symbolic-full-name", "@{upstream}")
        if upstream is None:
            reasons.append("The branch %s is not tracking a remote branch."
                           % branch)
    return reasons


class Settings:
    """The state of the installed theme, as install.sh remembers it.

    Read once at startup and again after a successful Apply, so that what the
    window shows is what is on disk rather than what it last sent.
    """

    def __init__(self):
        self.accent = read_memo("accent", "purple")
        if self.accent not in ACCENTS:
            self.accent = "purple"

        self.radius = read_memo("radius-preset", "default")
        # A memo written by a version that had presets this one does not. It
        # names the row that replaced it rather than falling back to default,
        # so a machine that installed `pill` opens showing the rounding it is
        # actually wearing.
        self.radius = RADIUS_PRESET_ALIASES.get(self.radius, self.radius)
        if self.radius not in [p[0] for p in RADIUS_PRESETS] + ["custom"]:
            self.radius = "default"

        # Only meaningful while radius is "custom", but read either way so the
        # seven spin rows have somewhere to start from when someone moves one.
        self.radius_custom = parse_radius_custom(read_memo("radius-custom"))
        if self.radius == "custom" and self.radius_custom is None:
            # A custom preset with no values behind it is not a state install.sh
            # would accept, so it is not one to carry around either.
            self.radius = "default"

        # The mode is the memo install.sh wrote, and the marker outranks it for
        # the same reason install.sh's resolve_glass_mode gives it precedence:
        # the marker is the state the desktop is in, the memo is a note about
        # it. A machine from before modes existed has neither, so the mode is
        # read out of what is installed — which is exactly what the window used
        # to do for the one switch this replaces.
        if os.path.exists(os.path.join(CONF_DIR, "styling-off")):
            self.glass_mode = "solid"
        else:
            mode = read_memo("glass-mode", "") or ""
            if mode not in GLASS_MODES:
                mode = ""
            self.glass_mode = mode

        # Solid mode has no memo of its own for the blur: install_css encodes it
        # by whether the solid sheet is installed at all.
        self.blur = not os.path.exists(
            os.path.join(CONF_DIR, "shell-80-solid.css"))

        self.transparency = read_memo("app-transparency", "0") or "0"
        self.scope = read_memo("app-blur-scope", "gtk") or "gtk"
        if read_memo("window-blur", "1") == "0":
            self.scope = "none"
        if self.scope not in BLUR_SCOPES:
            self.scope = "gtk"

        self.popup_blur = read_memo("popup-blur", "1") != "0"

        if not self.glass_mode:
            # Derived exactly as glass_mode_from_state does in
            # lib/steps-modes.sh: the two have to agree, because the window
            # showing one tab while install.sh resolves another is the one bug
            # a mode can have that nothing else would catch.
            if self.blur and self.scope == "none" and self.transparency != "0":
                self.glass_mode = "transparent"
            else:
                self.glass_mode = "frosted"

        # The colour each half of the desktop darkens toward under its alpha,
        # and how far every blur reaches. Black and 100 are the shipped answers
        # and mean "as the theme was written", which is why neither has a
        # switch beside it — going back to the default is picking it again.
        self.app_tint = read_hex_memo("app-tint-color")
        self.shell_tint = read_hex_memo("shell-tint-color")
        self.blur_strength = read_percent_memo("blur-strength")

        # Which windows the applications component treats. Blur My Shell reads
        # one or the other depending on enable-all, which is the same choice
        # `scope` makes — so the allow list belongs to gtk mode and the block
        # list to all mode. apply_app_blur writes both memos every run, so an
        # empty one here means an empty list rather than a missing file.
        #
        # Normalised through the pin rather than read raw. apply_app_blur puts
        # this window's own class on the allow list and takes anything that
        # would block it off the other one on every run, so the raw memos are
        # not what the next run installs — and a window that showed them raw
        # would be reporting a list it is about to change.
        self.allow = pin_self_allow(read_memo_lines("app-blur-allow"))
        self.block = pin_self_block(read_memo_lines("app-blur-block"))

        # Kept whole, family and colour together, because that is what --icons
        # takes and what the memo holds: "colloid", "colloid-teal", "reversal",
        # "reversal-cyan". The window splits it across two rows and joins it
        # back. A bare family still means "follow the accent" — the mapping from
        # accent to each pack's own colour names lives in lib/steps-assets.sh
        # and is not copied here.
        #
        # There is no memo for "keep" — --no-icons is a choice not to have
        # touched anything, which leaves nothing behind to read.
        icons = read_memo("icon-pack", "colloid") or "colloid"
        self.icons = join_icons(*split_icons(icons))
        self.cursors = read_memo("cursor-pack", "adwaita") or "adwaita"
        if self.cursors not in [c[0] for c in CURSOR_PACKS]:
            self.cursors = "adwaita"

        # Empty is a real answer here, and the default one: the key is shared
        # with GNOME Tweaks and with anyone who set it by hand, so until this
        # window is asked to have an opinion it does not have one.
        self.window_buttons = read_memo("window-buttons", "")
        if self.window_buttons not in [w[0] for w in WINDOW_BUTTON_LAYOUTS]:
            self.window_buttons = ""

        # A user systemd unit rather than a look, but a remembered setting like
        # any other, so it rides on Apply.
        self.panel_blur_fix = read_memo("panel-blur-fix", "1") != "0"

        self.update_check = read_memo("update-check", "1") != "0"
        # Written by bin/aura-glass-update-check, so the window can say what is
        # waiting without going to the network itself. None means up to date.
        self.update_available = read_memo("update-available") or None

        # Every mode's own settings, so switching tabs can show them without
        # applying anything. The seeds match seed_glass_mode's in
        # lib/steps-modes.sh — which, for every field but the level, seeds a
        # fresh drawer from whatever the top-level memo already holds and
        # falls back to its literal only when that is empty too, so a
        # customised tint or blur strength survives onto a tab that has never
        # been opened rather than resetting to the shipped default. Read raw
        # here (not through self.app_tint and friends, which have already
        # applied their own defaults) so an absent top-level memo reaches the
        # mode-specific literal exactly as the shell's disk_app/disk_shell/
        # disk_strength/disk_scope do.
        disk_transparency = read_memo("app-transparency", "")
        disk_app_tint = read_memo("app-tint-color", "")
        disk_shell_tint = read_memo("shell-tint-color", "")
        disk_strength = read_memo("blur-strength", "")
        disk_scope = read_memo("app-blur-scope", "")
        disk_popup = read_memo("popup-blur", "")

        self.modes = {}
        for mode in GLASS_MODES:
            if mode == "solid":
                continue
            # Transparent's level is the one field seed_glass_mode does not
            # inherit from disk: frosted's own level is tuned for a blurred
            # window behind it, and was never transparent's to start from, so
            # its seed is always the darker constant, unconditionally.
            if mode == "transparent":
                level = "0.82"
                tint_default = disk_app_tint or "#0b0b0f"
                shell_default = disk_shell_tint or "#0b0b0f"
            else:
                level = disk_transparency or "0"
                tint_default = disk_app_tint or "#000000"
                shell_default = disk_shell_tint or "#000000"
            try:
                strength = int(read_mode_memo(mode, "blur-strength",
                                              disk_strength or "100"))
            except ValueError:
                strength = 100
            self.modes[mode] = {
                "transparency": read_mode_memo(mode, "app-transparency", level),
                "app_tint": read_mode_memo(mode, "app-tint-color", tint_default),
                "shell_tint": read_mode_memo(mode, "shell-tint-color",
                                             shell_default),
                "blur_strength": strength,
                "popup_blur": read_mode_memo(mode, "popup-blur",
                                             disk_popup or "1") != "0",
                "scope": read_mode_memo(mode, "app-blur-scope",
                                        disk_scope or "gtk"),
            }

        # The mode in force is the live state whatever its drawer says: the
        # drawer is written at the end of a run, and a memo edited by hand must
        # not outrank the sheet that is actually installed.
        if self.glass_mode in self.modes:
            self.modes[self.glass_mode].update({
                "transparency": self.transparency,
                "app_tint": self.app_tint,
                "shell_tint": self.shell_tint,
                "blur_strength": self.blur_strength,
                "popup_blur": self.popup_blur,
                "scope": self.scope,
            })

    def flags_against(self, other):
        """The install.sh arguments that turn `other` into `self`.

        Only differences, because install.sh resolves an absent flag from the
        memo it wrote last time. Sending the full set every time would work but
        would make every Apply an assertion about settings the user did not
        touch, which is how a GUI ends up undoing a CLI choice it never showed.
        """
        args = []
        if self.accent != other.accent:
            args += ["--accent", self.accent]

        # Whole, family and colour together, which is the spelling --icons
        # takes. A bare family goes out bare: accent_to_reversal and
        # colloid_color in lib/steps-assets.sh turn that into each pack's own
        # colour name, which is not the accent's for several of them — Reversal
        # has no teal, yellow or slate, and Colloid calls blue "default".
        # Resolving it here would be a second copy of those mappings, and the
        # copy that used to exist in the wizard was wrong.
        if self.icons != other.icons:
            if self.icons == "keep":
                args.append("--no-icons")
            else:
                args += ["--icons", self.icons]
        if self.cursors != other.cursors:
            if self.cursors == "keep":
                args.append("--no-cursors")
            else:
                args += ["--cursors", self.cursors]

        if self.update_check != other.update_check:
            args.append("--update-check" if self.update_check
                        else "--no-update-check")
        if self.panel_blur_fix != other.panel_blur_fix:
            args.append("--panel-blur-fix" if self.panel_blur_fix
                        else "--no-panel-blur-fix")

        # Only ever on the way to a layout, never back to none. There is no flag
        # for "stop having an opinion" because there is nothing to restore to:
        # the value this overwrote was not recorded, and inventing GNOME's
        # default as the way back would assert a layout over whatever the user
        # actually had. Going back to "Leave as it is" leaves the last applied
        # layout standing, which the row says.
        if self.window_buttons != other.window_buttons and self.window_buttons:
            args += ["--window-buttons", self.window_buttons]
        # --radius-custom implies the custom preset, so it stands in for
        # --radius-preset rather than joining it. Sent when the seven values
        # moved even if the preset name did not, because "custom" says nothing
        # about which custom.
        if self.radius == "custom":
            if (other.radius != "custom"
                    or self.radius_custom != other.radius_custom):
                args += ["--radius-custom",
                         ",".join(str(v) for v in self.radius_custom)]
        elif self.radius != other.radius:
            args += ["--radius-preset", self.radius]

        # The mode first, and the flags it already implies are not restated.
        # install.sh resolves a mode into exactly these, so sending both would
        # be the same sentence twice — and in solid's case the second half is
        # the combination install.sh refuses outright.
        mode_changed = self.glass_mode != other.glass_mode
        if mode_changed:
            args += ["--glass-mode", self.glass_mode]

        if self.glass_mode == "solid":
            return args

        # Solid keeps no settings of its own — every field below reads, while
        # solid is in force, as whatever apply_glass_mode's solid branch
        # forced it to the moment WANT_STYLING went to 0 (APP_TRANSPARENCY=0,
        # popup and window blur off), not a preference anyone chose. An
        # earlier version of this function returned here whenever `other`
        # was solid, sending nothing past the mode flag — which happened to
        # be right for the tab exactly as its drawer left it, and silently
        # wrong the moment someone dragged that tab's opacity before pressing
        # Apply: the edit matched neither `other` (solid's forced 0) nor
        # anything else this function looked at, so it never went out.
        #
        # The honest baseline once the mode has moved is the drawer of the
        # mode being entered, not `other` itself: self.modes[mode] in
        # Settings.__init__ populates it from exactly the files install.sh's
        # load_glass_mode_memos (lib/steps-modes.sh) will read if this Apply
        # says nothing about a field, so comparing against it tells the truth
        # about whether the widgets are asking for something the drawer does
        # not already hold — nothing to send when they are not, the edit when
        # they are. A mode with no entry — nothing on this path should
        # produce one, since solid is handled above and Settings.__init__
        # seeds every other mode unconditionally — falls back to `other`
        # rather than raising.
        into = other.modes.get(self.glass_mode) if mode_changed else None

        def base(field):
            return into[field] if into is not None else getattr(other, field)

        scope_base = base("scope")
        transparency_base = base("transparency")
        popup_base = base("popup_blur")
        app_tint_base = base("app_tint")
        shell_tint_base = base("shell_tint")

        # Only frosted has a scope to send: not blurring behind windows is
        # what transparent is, and --glass-mode transparent has already said
        # so.
        if self.glass_mode == "frosted" and self.scope != scope_base:
            args.append({"gtk": "--gtk-apps-blur",
                         "all": "--all-apps-blur",
                         "none": "--no-window-blur"}[self.scope])

        # --no-window-blur moves the level to 0.95 unless the level is given,
        # so the level goes after the scope flag and always states itself
        # when either one is not what the baseline already holds. The scope
        # half only matters for frosted, for the same reason the flag above
        # is frosted-only — transparent has no scope flag of its own to move
        # it.
        if (self.transparency != transparency_base
                or (self.glass_mode == "frosted"
                    and self.scope != scope_base)):
            if self.transparency == "0":
                args.append("--no-app-transparency")
            else:
                args += ["--app-transparency", self.transparency]

        if self.popup_blur != popup_base:
            args.append("--popup-blur" if self.popup_blur
                        else "--no-popup-blur")

        # The two tints. Sent as the value rather than as an on/off, because
        # black is a value in its own right — it is the state the sheets ship
        # in, and asking for it again is how a tint is undone.
        #
        # The app tint rides inside the transparency sheet, which is only
        # installed while there is transparency to tint. Sending it with the
        # windows opaque would write a memo that install_transparency_css
        # returns before reading, so the window would show a colour that is not
        # on the disk — the row is insensitive there for the same reason.
        if self.app_tint != app_tint_base and self.transparency != "0":
            args += ["--app-tint-color", self.app_tint]
        if self.shell_tint != shell_tint_base:
            args += ["--shell-tint-color", self.shell_tint]

        # The blur strength is not part of a mode's identity the way level and
        # tint are — every mode's drawer seeds it to the same 100, and nothing
        # in apply_glass_mode ever moves it — so unlike them it stays a plain
        # comparison against `other`, never the drawer.
        if self.blur_strength != other.blur_strength:
            args += ["--blur-strength", str(self.blur_strength)]

        # Whichever list changed, consulted by the mode in force or not.
        #
        # This used to send only the consulted one, on the grounds that a list
        # the user had never seen had no business appearing in the argument
        # line. That held while the window showed one list at a time. It edits
        # both now — they are two memos that survive every mode switch, and
        # apply_app_blur writes both keys every run — so the idle list is one
        # the user did see and did change, and dropping it here would throw the
        # edit away at the next reload without saying so.
        if self.allow != other.allow:
            args += ["--app-blur-allow", ",".join(self.allow)]
        if self.block != other.block:
            args += ["--app-blur-block", ",".join(self.block)]

        return args


class AppPickerWindow(Adw.Window):
    """Pick an installed app, or type a pattern.

    Two ways in, because neither covers the other. The list handles the common
    case without anyone having to know what a wm_class is; the entry handles
    wildcards, and apps that are not installed as desktop entries at all — which
    is most of the ones the shipped block list names.

    A window rather than an Adw.Dialog, for the reason open_over gives: a dialog
    is drawn inside its parent and so has no blur behind it.
    """

    def __init__(self, existing, on_add):
        super().__init__(title="Add an app", default_width=460,
                         default_height=560)
        self._existing = set(existing)
        self._on_add = on_add

        self._entry = Adw.EntryRow(title="Window class or pattern")
        self._entry.connect("entry-activated", self._on_entry)
        self._entry.connect("changed", self._on_entry_changed)
        add_button = Gtk.Button(icon_name="list-add-symbolic",
                                valign=Gtk.Align.CENTER,
                                tooltip_text="Add this pattern")
        add_button.add_css_class("flat")
        add_button.connect("clicked", self._on_entry)
        self._entry.add_suffix(add_button)

        manual = Adw.PreferencesGroup(
            title="Type it",
            description="A window's class is the name it gives itself, which is "
                        "usually not the name on its title bar. * stands for any "
                        "amount of anything.")
        manual.add(self._entry)

        # Under the entry rather than in the group's description: it answers
        # what was just typed, so it has to be next to it and has to move.
        self._preview = Gtk.Label(
            xalign=0, wrap=True, margin_start=24, margin_end=24, margin_top=2)
        self._preview.add_css_class("dim-label")
        self._preview.add_css_class("caption")

        # Fill the entry rather than add outright: the point is to show the
        # shape, and the preview under it then explains the shape.
        examples = Adw.PreferencesGroup(title="Or start from one of these")
        for pattern, what in PATTERN_EXAMPLES:
            row = Adw.ActionRow(title=pattern, subtitle=what)
            use = Gtk.Button(label="Use", valign=Gtk.Align.CENTER)
            use.add_css_class("flat")
            use.connect("clicked",
                        lambda _b, p=pattern: self._entry.set_text(p))
            row.add_suffix(use)
            row.set_activatable_widget(use)
            examples.add(row)

        self._search = Gtk.SearchEntry(placeholder_text="Search installed apps")
        self._search.connect("search-changed", lambda _e: self._refill())

        self._list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self._list.add_css_class("boxed-list")
        self._list.set_margin_start(12)
        self._list.set_margin_end(12)
        self._list.set_margin_bottom(12)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for widget in (manual, examples):
            widget.set_margin_start(12)
            widget.set_margin_end(12)
        manual.set_margin_top(12)
        box.append(manual)
        box.append(self._preview)
        box.append(examples)
        self._search.set_margin_start(12)
        self._search.set_margin_end(12)
        box.append(self._search)
        box.append(self._list)

        scroller = Gtk.ScrolledWindow(child=box, vexpand=True)
        view = Adw.ToolbarView(content=scroller)
        view.add_top_bar(Adw.HeaderBar())
        self.set_content(view)

        self._apps = self._installed_apps()
        self._refill()

    def _installed_apps(self):
        """Every app with a visible desktop entry, by display name."""
        seen = {}
        for info in Gio.AppInfo.get_all():
            if not info.should_show():
                continue
            wm = wm_class_for(info)
            if not wm:
                continue
            # Several entries can resolve to one class (an app plus its actions).
            # First one wins; the name shown is that entry's.
            seen.setdefault(wm, info)
        return sorted(seen.items(), key=lambda kv: (kv[1].get_display_name() or "").lower())

    def _refill(self):
        needle = self._search.get_text().strip().lower()
        child = self._list.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            self._list.remove(child)
            child = nxt

        shown = 0
        for wm, info in self._apps:
            name = info.get_display_name() or wm
            if needle and needle not in name.lower() and needle not in wm.lower():
                continue
            if shown >= 60:      # the list is a picker, not a catalogue
                break
            row = plain_row(Adw.ActionRow(), name, wm)
            icon = info.get_icon()
            if icon is not None:
                row.add_prefix(Gtk.Image.new_from_gicon(icon))
            if wm in self._existing:
                row.add_suffix(Gtk.Image.new_from_icon_name("object-select-symbolic"))
                row.set_sensitive(False)
            else:
                row.set_activatable(True)
                row.connect("activated", self._on_pick, wm)
            self._list.append(row)
            shown += 1

    def _on_pick(self, _row, wm):
        self._on_add(wm)
        self.close()

    def _on_entry_changed(self, _entry):
        text = self._entry.get_text().strip().replace(",", "")
        if text and text in self._existing:
            self._preview.set_label("Already on this list.")
        else:
            self._preview.set_label(describe_pattern(self._entry.get_text()))

    def _on_entry(self, *_a):
        text = self._entry.get_text().strip().replace(",", "")
        if not text or text in self._existing:
            return
        self._on_add(text)
        self.close()


class AppListWindow(Adw.Window):
    """One of the two per-app lists, on its own.

    They used to share a single group in the main window that swapped which
    list it showed as the blur mode changed. That made the mode look like it
    owned the lists: switching modes read as the other list having been
    emptied, when in fact both are separate memos that survive every switch and
    are editable whatever the mode is. A window each says that instead.

    The list is mutated in place — it is the same object the main window keeps
    — and on_change is called after every edit so the summary behind this
    window and the Apply button stay in step with it.

    A window rather than an Adw.Dialog, for the reason open_over gives.
    """

    def __init__(self, which, title, description, entries, on_change,
                 active_note):
        super().__init__(title=title, default_width=520, default_height=600)
        self._which = which
        self._entries = entries
        self._on_change = on_change

        self._group = Adw.PreferencesGroup(description=description)
        self._group.set_margin_top(12)
        self._group.set_margin_start(12)
        self._group.set_margin_end(12)
        self._group.set_margin_bottom(12)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        # Shown rather than the window being refused: an inactive list is still
        # worth editing, and the note is the difference between "not consulted
        # at the moment" and "does not work".
        if active_note:
            box.append(Adw.Banner(title=active_note, revealed=True))
        box.append(self._group)

        # In the header bar rather than as the group's header suffix, which is
        # where it was. That slot sits at the end of a four-line paragraph of
        # description, and a 16px + against that much prose is a button you
        # have to hunt for. The top right of the window is the one corner
        # nothing else competes for, and it is where GNOME puts an add button
        # anyway. Labelled, too: an icon on its own was the other half of why
        # it was easy to miss.
        add = Gtk.Button(child=Adw.ButtonContent(icon_name="list-add-symbolic",
                                                 label="Add"),
                         tooltip_text="Add an app or a pattern to this list")
        add.add_css_class("suggested-action")
        add.connect("clicked", self._on_add)

        header = Adw.HeaderBar()
        header.pack_end(add)

        scroller = Gtk.ScrolledWindow(child=box, vexpand=True)
        view = Adw.ToolbarView(content=scroller)
        view.add_top_bar(header)
        self.set_content(view)

        self._rows = []
        self._rebuild()

    def _rebuild(self):
        for row in self._rows:
            self._group.remove(row)
        self._rows = []

        if not self._entries:
            row = Adw.ActionRow(title="Nothing listed",
                                subtitle="Use Add, up in the header bar")
            row.set_sensitive(False)
            self._group.add(row)
            self._rows.append(row)

        for pattern in self._entries:
            # The name first and the pattern under it. The pattern is the thing
            # Blur My Shell matches on and has to stay visible, but "Files" is
            # what the user pointed at and org.gnome.Nautilus is not.
            row = plain_row(Adw.ActionRow(), app_name(pattern), pattern)
            # What the pattern covers, which used to be the subtitle. It answers
            # a question about the wildcards rather than being the row's own
            # text, so it moves to where a question gets answered.
            row.set_tooltip_text(describe_pattern(pattern))

            if self._which == "allow" and pattern == SELF_WM_CLASS:
                # This window itself, which apply_app_blur pins back on every
                # run. A remove button that undid itself at the next Apply
                # would be worse than not having one.
                row.set_subtitle("%s — this window, always blurred while the "
                                 "blur is on" % pattern)
                self._group.add(row)
                self._rows.append(row)
                continue

            remove = Gtk.Button(icon_name="user-trash-symbolic",
                                valign=Gtk.Align.CENTER,
                                tooltip_text="Remove")
            remove.add_css_class("flat")
            remove.connect("clicked", self._on_remove, pattern)
            row.add_suffix(remove)
            self._group.add(row)
            self._rows.append(row)

    def _on_add(self, _button):
        def add(pattern):
            self._entries.append(pattern)
            self._rebuild()
            self._on_change()

        open_over(AppPickerWindow(self._entries, add), self)

    def _on_remove(self, _button, pattern):
        if pattern in self._entries:
            self._entries.remove(pattern)
            self._rebuild()
            self._on_change()


class TintPreviewWindow(Adw.Window):
    """Both tints over a stand-in wallpaper, with text on them, live.

    A tint is not a colour you can judge from a swatch. What matters is what it
    does to white text at the opacity it will be shown at, over something with
    detail in it — and the two colours have to be judged against each other,
    because a desktop with a warm app window and a cold panel is the failure
    mode this window exists to catch before it is installed.

    So: no swatches. An app window and the shell's own surfaces, drawn at the
    colours the two buttons currently hold and at the opacity the bar currently
    holds, over a gradient that stands in for a wallpaper.

    Drawn rather than styled. Doing it with real widgets would mean loading a
    stylesheet per keystroke of the colour picker, and the CSS that produces
    these surfaces is deliberately installed rather than switched on at read
    time — see install_transparency_css. Cairo draws the same arithmetic
    without touching anything on disk.

    A window rather than an Adw.Dialog, for the reason open_over gives.
    """

    # The theme's own dark grounds, which the tint is mixed into. The GTK value
    # is libadwaita's dark @window_bg_color; the shell ones are the notification
    # and menu grounds from css/shell-30-notifications.css, which are the
    # literals apply-shell-tint.py rewrites.
    APP_BASE = (0x24 / 255.0, 0x24 / 255.0, 0x24 / 255.0)
    SHELL_BASES = [(20 / 255.0, 20 / 255.0, 26 / 255.0),
                   (30 / 255.0, 30 / 255.0, 38 / 255.0)]

    # How much of the tint survives the mix, which is TOKEN_APP_TINT's
    # complement — tokens/tokens.sh keeps the number and css/gtk4-transparency
    # .css writes it; this draws with it.
    TINT_WEIGHT = 0.55

    def __init__(self, read):
        super().__init__(title="Tint preview", default_width=760,
                         default_height=460)
        self._read = read      # () -> (app hex, shell hex, opacity 0-1)

        self._area = Gtk.DrawingArea(hexpand=True, vexpand=True)
        self._area.set_draw_func(self._draw)

        view = Adw.ToolbarView(content=self._area)
        view.add_top_bar(Adw.HeaderBar())
        self.set_content(view)

    def refresh(self):
        self._area.queue_draw()

    def _draw(self, _area, cr, width, height):
        app_hex, shell_hex, opacity = self._read()
        app = parse_hex(app_hex)
        shell = parse_hex(shell_hex)

        self._wallpaper(cr, width, height)

        margin = 24
        column = (width - margin * 3) / 2.0
        self._app_window(cr, margin, margin, column, height - margin * 2,
                         (app.red, app.green, app.blue), opacity)
        self._shell(cr, margin * 2 + column, margin, column,
                    height - margin * 2, (shell.red, shell.green, shell.blue),
                    opacity)

    def _wallpaper(self, cr, width, height):
        """Something with detail behind the glass, so the glass has a job."""
        gradient = cairo.LinearGradient(0, 0, width, height)
        gradient.add_color_stop_rgb(0.0, 0.30, 0.24, 0.46)
        gradient.add_color_stop_rgb(0.5, 0.16, 0.31, 0.44)
        gradient.add_color_stop_rgb(1.0, 0.42, 0.26, 0.28)
        cr.set_source(gradient)
        cr.paint()

        # Stripes rather than a flat wash: a blur and a tint both read very
        # differently over an edge than over an even colour, and a preview that
        # only showed the even case would flatter every setting.
        cr.set_source_rgba(1, 1, 1, 0.07)
        step = 46
        for i in range(-height // step, (width + height) // step + 1):
            cr.move_to(i * step, 0)
            cr.line_to(i * step + height, height)
            cr.set_line_width(16)
            cr.stroke()

    def _text(self, cr, x, y, size, weight, alpha, text):
        cr.select_font_face("Cantarell", cairo.FONT_SLANT_NORMAL, weight)
        cr.set_font_size(size)
        cr.set_source_rgba(1, 1, 1, alpha)
        cr.move_to(x, y)
        cr.show_text(text)

    def _app_window(self, cr, x, y, w, h, tint, opacity):
        ground = mix_rgb(self.APP_BASE, tint, self.TINT_WEIGHT)

        rounded_path(cr, x, y, w, h, 18)
        cr.set_source_rgba(ground[0], ground[1], ground[2], opacity)
        cr.fill()

        # The header bar, which the sheet keeps a little more transparent than
        # the window under it.
        cr.save()
        rounded_path(cr, x, y, w, h, 18)
        cr.clip()
        cr.set_source_rgba(ground[0], ground[1], ground[2],
                           max(0.0, opacity - 0.06))
        cr.rectangle(x, y, w, 46)
        cr.fill()
        cr.set_source_rgba(1, 1, 1, 0.08)
        cr.rectangle(x, y + 45, w, 1)
        cr.fill()
        cr.restore()

        self._text(cr, x + 18, y + 30, 14, cairo.FONT_WEIGHT_BOLD, 0.95,
                   "An app window")
        self._text(cr, x + 18, y + 80, 13, cairo.FONT_WEIGHT_NORMAL, 0.92,
                   "Body text at full strength.")
        self._text(cr, x + 18, y + 104, 13, cairo.FONT_WEIGHT_NORMAL, 0.55,
                   "Dimmed text, which is the first thing")
        self._text(cr, x + 18, y + 124, 13, cairo.FONT_WEIGHT_NORMAL, 0.55,
                   "a tint too light will cost you.")
        self._text(cr, x + 18, y + h - 22, 11, cairo.FONT_WEIGHT_NORMAL, 0.45,
                   "App windows")

    def _shell(self, cr, x, y, w, h, tint, opacity):
        panel = hue_shift(self.SHELL_BASES[0], tint)
        menu = hue_shift(self.SHELL_BASES[1], tint)

        # The top bar.
        rounded_path(cr, x, y, w, 34, 10)
        cr.set_source_rgba(panel[0], panel[1], panel[2], 0.72)
        cr.fill()
        self._text(cr, x + 14, y + 22, 12, cairo.FONT_WEIGHT_NORMAL, 0.90,
                   "12:45")

        # A menu under it.
        rounded_path(cr, x, y + 48, w * 0.62, 132, 16)
        cr.set_source_rgba(menu[0], menu[1], menu[2], 0.78)
        cr.fill()
        for i, label in enumerate(("Wi-Fi", "Bluetooth", "Power")):
            self._text(cr, x + 16, y + 76 + i * 34, 13,
                       cairo.FONT_WEIGHT_NORMAL, 0.92, label)

        # And a notification, which is the surface with the most text on it.
        rounded_path(cr, x, y + 200, w, 84, 16)
        cr.set_source_rgba(panel[0], panel[1], panel[2], 0.80)
        cr.fill()
        self._text(cr, x + 16, y + 228, 13, cairo.FONT_WEIGHT_BOLD, 0.95,
                   "A notification")
        self._text(cr, x + 16, y + 252, 12, cairo.FONT_WEIGHT_NORMAL, 0.60,
                   "with the second line the shell dims.")
        self._text(cr, x + 14, y + h - 22, 11, cairo.FONT_WEIGHT_NORMAL, 0.45,
                   "Shell surfaces")


class ApplyDialog(Adw.Dialog):
    """install.sh's output, while it runs.

    Streamed rather than collected: --settings-only is quick but not instant,
    and a window that goes blank for ten seconds is indistinguishable from one
    that has hung.
    """

    def __init__(self, repo, args, on_done, title="Applying",
                 description="Reapplying the dconf preset, the CSS and the gsettings.",
                 argv=None):
        super().__init__(title=title, content_width=560,
                         content_height=420, can_close=False)
        self._on_done = on_done
        self._failed = False
        self._argv = argv

        self._status = Adw.StatusPage(title=title, description=description)
        spinner = Adw.Spinner(width_request=32, height_request=32)
        self._status.set_child(spinner)

        self._log = Gtk.TextView(
            editable=False, cursor_visible=False, monospace=True,
            top_margin=8, bottom_margin=8, left_margin=8, right_margin=8)
        self._log.add_css_class("card")
        scroller = Gtk.ScrolledWindow(child=self._log, vexpand=True,
                                      propagate_natural_height=True)
        self._log_reveal = Gtk.Expander(label="Details", child=scroller,
                                        margin_start=12, margin_end=12,
                                        margin_bottom=12)

        self._close = Gtk.Button(label="Close", sensitive=False)
        self._close.connect("clicked", lambda _b: self.close())
        header = Adw.HeaderBar(show_end_title_buttons=False)
        header.pack_end(self._close)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        body.append(self._status)
        body.append(self._log_reveal)
        view = Adw.ToolbarView(content=body)
        view.add_top_bar(header)
        self.set_child(view)

        self._run(repo, args)

    def _append(self, line):
        buf = self._log.get_buffer()
        buf.insert(buf.get_end_iter(), line + "\n")
        # Follow the tail, so the interesting end is the part on screen.
        buf_end = buf.create_mark(None, buf.get_end_iter(), False)
        self._log.scroll_to_mark(buf_end, 0, False, 0, 0)

    def _run(self, repo, args):
        argv = self._argv or ["bash", os.path.join(repo, "install.sh"),
                              "--settings-only", "--yes"] + args
        self._append("$ " + " ".join(argv[1:]))
        try:
            proc = Gio.Subprocess.new(
                argv,
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE)
        except GLib.Error as exc:
            self._finish(False, "Could not start install.sh", exc.message)
            return

        # NO_COLOR belongs to the environment install.sh reads, not to argv, and
        # a piped stdout already turns the colours off in lib/common.sh. Reading
        # the pipe line by line is what keeps the view live.
        stream = Gio.DataInputStream.new(proc.get_stdout_pipe())
        self._read_line(stream, proc)

    def _read_line(self, stream, proc):
        def done(src, res):
            try:
                line, _ = src.read_line_finish_utf8(res)
            except GLib.Error as exc:
                self._append("(could not read output: %s)" % exc.message)
                line = None
            if line is None:
                proc.wait_check_async(None, self._exited)
                return
            self._append(line.rstrip())
            self._read_line(src, proc)

        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, done)

    def _exited(self, proc, res):
        try:
            proc.wait_check_finish(res)
        except GLib.Error as exc:
            self._finish(False, "install.sh failed", exc.message)
            return
        self._finish(True, "Done" if self._argv else "Applied",
                     "The shell has already reloaded. Restart any open GTK app "
                     "to get the GTK side.")

    def _finish(self, ok, title, description):
        self._failed = not ok
        self._status.set_child(None)
        self._status.set_icon_name(
            "emblem-ok-symbolic" if ok else "dialog-error-symbolic")
        self._status.set_title(title)
        self._status.set_description(description)
        if not ok:
            self._log_reveal.set_expanded(True)
        self._close.set_sensitive(True)
        self._close.grab_focus()
        self.set_can_close(True)
        self._on_done(ok)


class Window(Adw.ApplicationWindow):
    def __init__(self, app, repo):
        super().__init__(application=app, title="Aura Glass",
                         default_width=920, default_height=740)
        self._repo = repo
        self._applied = Settings()   # what is on disk
        self._loading = True

        self._apply = Gtk.Button(label="Apply", sensitive=False)
        self._apply.add_css_class("suggested-action")
        self._apply.connect("clicked", self._on_apply)

        # The Glass page builds one set of these per mode and keys them by it.
        # They live here rather than in that builder because a dict created
        # inside the first tab's build would not be there for the second's.
        self._tints = {}
        self._tint_rows = {}
        self._strength_scales = {}

        # Every page is built up front rather than on first visit. _reload and
        # _mark_dirty both read every widget in the window — a page built later
        # would be a page whose rows do not exist when they run.
        self._stack = Gtk.Stack(
            transition_type=Gtk.StackTransitionType.CROSSFADE)
        self._sidebar = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
        self._sidebar.add_css_class("navigation-sidebar")
        for ident, title, icon, builder in NAV_SECTIONS:
            self._stack.add_named(getattr(self, builder)(), ident)
            row = Adw.ActionRow(title=title)
            row.add_prefix(Gtk.Image.new_from_icon_name(icon))
            row._section = ident
            self._sidebar.append(row)
        self._sidebar.connect("row-selected", self._on_section)

        self._toasts = Adw.ToastOverlay(child=self._stack)

        # Apply lives on the content pane, not the sidebar: it applies whatever
        # changed anywhere in the window, and a header that scrolls away with
        # one page would hide it from the others.
        content_header = Adw.HeaderBar()
        content_header.pack_end(self._apply)
        content_view = Adw.ToolbarView(content=self._toasts)
        content_view.add_top_bar(content_header)
        self._content_page = Adw.NavigationPage(child=content_view,
                                                title=NAV_SECTIONS[0][1])

        sidebar_view = Adw.ToolbarView(
            content=Gtk.ScrolledWindow(child=self._sidebar, vexpand=True))
        sidebar_view.add_top_bar(Adw.HeaderBar())
        sidebar_page = Adw.NavigationPage(child=sidebar_view,
                                          title="Aura Glass")

        split = Adw.NavigationSplitView(
            sidebar=sidebar_page, content=self._content_page,
            min_sidebar_width=210, max_sidebar_width=260)
        self.set_content(split)

        self._sidebar.select_row(self._sidebar.get_row_at_index(0))
        self._sync_sensitivity()

        self._loading = False
        if repo is None:
            self._apply.set_sensitive(False)
            self._banner_missing_repo()

    def _on_section(self, _list, row):
        if row is None:
            return
        self._stack.set_visible_child_name(row._section)
        self._content_page.set_title(row.get_title())

    # ---- construction -----------------------------------------------------

    def _combo(self, title, subtitle, options, current, key):
        """A ComboRow over (id, title, subtitle) options.

        The ids are kept beside the row rather than derived from the position, so
        reordering a list here cannot silently change which flag a row sends.
        """
        row = Adw.ComboRow(title=title, subtitle=subtitle)
        row.connect("notify::selected", self._on_changed, key)
        self._refill_combo(row, options, current)
        return row

    def _refill_combo(self, row, options, current):
        """Give a ComboRow a different set of options.

        Used at build time and again whenever one row decides what another may
        offer — the icon colour list, which each pack names differently. A
        selection the new list does not have falls back to its first entry
        rather than being kept and sent as something install.sh would reject.
        """
        model = Gtk.StringList()
        for _, label, _sub in options:
            model.append(label)
        row._ids = [o[0] for o in options]
        row._subs = [o[2] for o in options]
        row.set_model(model)
        row.set_selected(row._ids.index(current) if current in row._ids else 0)
        self._sync_subtitle(row)

    def _sync_subtitle(self, row):
        i = row.get_selected()
        if 0 <= i < len(row._subs):
            row.set_subtitle(row._subs[i])

    def _build_look_page(self):
        page = Adw.PreferencesPage()

        look = Adw.PreferencesGroup(
            title="Look",
            description="Both of these apply without logging out.")
        self._accent_row = self._combo(
            "Accent colour", "", [(a, a.capitalize(), "") for a in ACCENTS],
            self._applied.accent, "accent")
        # GNOME owns the accent; this button is the honest way to say so.
        settings_button = Gtk.Button(icon_name="external-link-symbolic",
                                    valign=Gtk.Align.CENTER,
                                    tooltip_text="Open GNOME Settings → Appearance")
        settings_button.add_css_class("flat")
        settings_button.connect("clicked", self._open_gnome_appearance)
        self._accent_row.add_suffix(settings_button)
        look.add(self._accent_row)

        page.add(look)
        return page

    def _build_radius_page(self):
        page = Adw.PreferencesPage()

        presets = Adw.PreferencesGroup(
            title="Corner rounding",
            description="Six steps, from square to one above what the theme "
                        "ships. Each sets all seven surfaces below at once — "
                        "move any one of them afterwards and the rounding "
                        "becomes yours rather than one of these.")

        # Six little windows rather than six buttons with words on them. Each
        # card is rounded by the window radius its preset sets, so the row of
        # them is the comparison — reading "38px" and picturing it is the part
        # nobody can do, and a card that is literally that shape does it for
        # them. The px is exaggerated against a real window, which is the point:
        # scaled down to a 150px card, 38px would land at 6 and every preset
        # would look the same.
        #
        # Three per line, in two rows. Four fitted while there were four of
        # them; six across a 600px page would be 88px each, which is narrower
        # than the word "Default".
        cards = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE,
                            homogeneous=True, column_spacing=12, row_spacing=12,
                            min_children_per_line=2, max_children_per_line=3,
                            margin_top=6, margin_bottom=6)
        self._radius_preset_frames = {}
        for ident, title, subtitle in RADIUS_PRESETS:
            cards.append(self._radius_card(ident, title, subtitle))
        presets.add(cards)

        # Under the cards, because FlowBox is not a row and Adw.PreferencesGroup
        # puts every non-row child after its list box — so neither of these can
        # be an ActionRow without jumping above the cards they belong to.
        self._radius_state = Gtk.Label(xalign=0, wrap=True, hexpand=True,
                                       valign=Gtk.Align.CENTER)
        self._radius_state.add_css_class("caption")
        self._radius_state.add_css_class("dim-label")

        # Beside what it undoes, rather than beside the four cards: Default is
        # already one of those, and what this button is for is the way out of a
        # set of numbers that is no longer any of them.
        #
        # It started as the "Each surface" header suffix and had to move.
        # Adw.PreferencesGroup lays a header suffix out beside the description as
        # well as the title, and both descriptions on this page run to three
        # lines, which left the button squeezed against prose.
        self._radius_reset = Gtk.Button(
            label="Reset to default", valign=Gtk.Align.CENTER,
            tooltip_text="Put all seven surfaces back to what the theme ships")
        self._radius_reset.add_css_class("flat")
        self._radius_reset.connect("clicked", self._on_radius_preset, "default")

        footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12,
                         margin_top=2)
        footer.append(self._radius_state)
        footer.append(self._radius_reset)
        presets.add(footer)
        page.add(presets)

        # One control per surface rather than one for all seven. The presets
        # stay because these numbers are not proportional to each other and a
        # single multiplier over them produces combinations nobody looked at —
        # but "pick one of six" was never the only alternative to that.
        #
        # Two groups for one section, so the preview lands between the heading
        # and the rows. Adw.PreferencesGroup appends every non-row child after
        # its list box, so a drawing added to the group that holds the seven
        # rows would sit under all of them — the same reason the transparency
        # bar on the Glass page ends its group where it does.
        heading = Adw.PreferencesGroup(
            title="Each surface",
            description="Pixels. Every range here is one the presets already "
                        "cover, so anything you can set is something that has "
                        "been seen on a screen. Point at a row to see it.")

        # Which surface the preview is drawing, or None while the pointer is
        # nowhere near a row. Kept here rather than in the drawing so that
        # everything the preview shows is read from the page it belongs to.
        self._radius_hover = None
        self._radius_preview = RadiusPreview(
            lambda: dict(zip((s[0] for s in RADIUS_SURFACES),
                             self._radius_values())),
            lambda: self._radius_hover)

        # 21:9, which is wide enough for a window shape to read as a window and
        # short enough not to push the seven rows off the page. The frame holds
        # the ratio whatever the window is resized to, so the shapes keep their
        # proportions rather than stretching with it.
        shape = Gtk.AspectFrame(ratio=21 / 9, obey_child=False,
                                child=self._radius_preview,
                                height_request=170, margin_top=6,
                                margin_bottom=6)
        heading.add(shape)
        page.add(heading)

        surfaces = Adw.PreferencesGroup()
        self._radius_rows = {}
        for ident, title, low, high, subtitle in RADIUS_SURFACES:
            spin = Adw.SpinRow.new_with_range(low, high, 1)
            spin.set_title(title)
            spin.set_subtitle(subtitle)
            spin.connect("notify::value", self._on_changed, "radius")
            self._watch_surface(spin, ident)
            surfaces.add(spin)
            self._radius_rows[ident] = spin
        page.add(surfaces)

        self._load_radius(self._applied)
        return page

    def _watch_surface(self, row, ident):
        """Point the preview at one row's surface while that row is in use.

        Pointer and keyboard both, because a spin row is as likely to be
        reached by tab and arrow keys as by a mouse, and a preview that went
        blank the moment you stopped using the mouse would be showing the wrong
        surface exactly while you changed a value.
        """
        def enter(*_a):
            self._radius_hover = ident
            self._radius_preview.queue_draw()

        def leave(*_a):
            if self._radius_hover == ident:
                self._radius_hover = None
                self._radius_preview.queue_draw()

        motion = Gtk.EventControllerMotion()
        motion.connect("enter", enter)
        motion.connect("leave", leave)
        row.add_controller(motion)

        focus = Gtk.EventControllerFocus()
        focus.connect("enter", enter)
        focus.connect("leave", leave)
        row.add_controller(focus)

    def _radius_card(self, ident, title, subtitle):
        """One preset drawn as the window it makes, with its name inside it."""
        # 120 rather than anything rounder. Adw.PreferencesPage clamps its
        # content to 600px and its own margins take 30 of that, GtkFlowBoxChild
        # adds 3px of padding either side of whatever it holds, and three 12px
        # gaps sit between four cards — so the widest card that keeps all four
        # on one line is about 130. At 150 the fourth wrapped onto a line of its
        # own; at 128 it fitted by two pixels, which is not fitting.
        frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL,
                        height_request=112, width_request=120)
        frame.add_css_class("aura-preset-window")
        frame.add_css_class("aura-preset-%s" % ident)

        # Three dots and no titlebar strip. Enough for the shape to read as a
        # window, and no second rounded edge to keep in step with the first —
        # GTK CSS has no overflow, so a bar across the top would have to carry
        # its own copy of the two upper corners.
        dots = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5,
                       halign=Gtk.Align.START, margin_start=14, margin_top=14)
        for _ in range(3):
            dot = Gtk.Box(width_request=8, height_request=8)
            dot.add_css_class("aura-preset-dot")
            dots.append(dot)
        frame.append(dots)

        inside = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1,
                         vexpand=True, valign=Gtk.Align.CENTER)
        name = Gtk.Label(label=title)
        name.add_css_class("heading")
        pixels = Gtk.Label(label="%dpx" % RADIUS_PRESET_VALUES[ident][0])
        pixels.add_css_class("caption")
        pixels.add_css_class("dim-label")
        inside.append(name)
        inside.append(pixels)
        frame.append(inside)

        button = Gtk.Button(child=frame, tooltip_text=subtitle)
        button.add_css_class("aura-preset")
        button.connect("clicked", self._on_radius_preset, ident)
        self._radius_preset_frames[ident] = frame
        return button

    def _load_radius(self, settings):
        """Put the seven rows where a Settings says they are."""
        values = (settings.radius_custom if settings.radius == "custom"
                  else RADIUS_PRESET_VALUES[settings.radius])
        was, self._loading = self._loading, True
        for (ident, _t, _lo, _hi, _s), value in zip(RADIUS_SURFACES, values):
            self._radius_rows[ident].set_value(value)
        self._loading = was
        self._sync_radius_state()

    def _radius_values(self):
        return tuple(int(self._radius_rows[ident].get_value())
                     for ident, _t, _lo, _hi, _s in RADIUS_SURFACES)

    def _radius_preset_name(self):
        """Which preset the seven rows spell, or custom if they spell none."""
        values = self._radius_values()
        for ident, preset in RADIUS_PRESET_VALUES.items():
            if values == preset:
                return ident
        return "custom"

    def _sync_radius_state(self):
        name = self._radius_preset_name()
        titles = {p[0]: p[1] for p in RADIUS_PRESETS}
        self._radius_state.set_label(
            "Currently: " + (titles[name] if name in titles
                             else "your own — " + ", ".join(
                                 "%s %d" % (s[1].lower(), v)
                                 for s, v in zip(RADIUS_SURFACES,
                                                 self._radius_values()))))
        for ident, frame in self._radius_preset_frames.items():
            # The active card takes an accent edge rather than going
            # insensitive: it is still the way back after moving a spin row.
            if ident == name:
                frame.add_css_class("on")
            else:
                frame.remove_css_class("on")
        # Nothing to reset to when the seven values already spell it.
        self._radius_reset.set_sensitive(name != "default")
        # Every path that moves a spin row comes through here — a preset click,
        # a reload, the rows themselves — so this is the one place the drawing
        # has to be told that what it reads has changed.
        self._radius_preview.queue_draw()

    def _on_radius_preset(self, _button, ident):
        was, self._loading = self._loading, True
        for (surface, _t, _lo, _hi, _s), value in zip(
                RADIUS_SURFACES, RADIUS_PRESET_VALUES[ident]):
            self._radius_rows[surface].set_value(value)
        self._loading = was
        self._sync_radius_state()
        self._mark_dirty()

    def _build_icons_page(self):
        page = Adw.PreferencesPage()

        # Their own page, because these two are the only settings in the window
        # that can reach the network. Switching to a pack already on disk is
        # instant — install_icons and install_cursors both skip when the theme is
        # there — and a pack that is not gets fetched, which the Apply log shows.
        packs = Adw.PreferencesGroup(
            title="Icons and pointer",
            description="A pack you have already installed applies instantly. "
                        "One you have not is downloaded first, so Apply can take "
                        "a minute and needs the network.")
        family, color = split_icons(self._applied.icons)
        self._icons_row = self._combo(
            "Icon pack", "", ICON_PACKS, family, "icons")
        packs.add(self._icons_row)

        # Its own row rather than nine entries folded into the pack list: the
        # colour is not the accent, and a pack list that spelled out every
        # colour would say it was.
        self._icon_color_row = self._combo(
            "Icon colour", "", ICON_COLORS[family], color, "icon_color")
        packs.add(self._icon_color_row)
        self._cursors_row = self._combo(
            "Pointer", "", CURSOR_PACKS, self._applied.cursors, "cursors")
        packs.add(self._cursors_row)
        page.add(packs)
        return page

    def _build_glass_page(self):
        """The three modes, as three tabs.

        The tab is the mode: switching one is asking for the other mode, in the
        ordinary pending way every other control here works, and Apply is what
        commits it. Which is why the tab bar cannot be the only mark — a
        selected tab says "you are reading this", not "you are running this",
        and those are two different answers until Apply. The badge under the
        switcher is the second one, in the words the per-app lists already use
        for the same question.

        Each tab owns its own controls rather than sharing dimmed ones. The page
        this replaces spent four rows and a sensitivity pass explaining which of
        its switches did not apply right now; a control that does not apply to
        the mode you are in is simply in another tab.

        All three are built here and now, like every page in this window and for
        the same reason: _reload and _mark_dirty read every widget there is, and
        a tab built on first visit would be a tab whose rows do not exist when
        they run.
        """
        self._mode_stack = Adw.ViewStack()
        self._mode_stack.add_titled_with_icon(
            self._build_frosted_page(), "frosted", "Frosted glass",
            "weather-fog-symbolic")
        self._mode_stack.add_titled_with_icon(
            self._build_transparent_page(), "transparent", "Transparent",
            "view-reveal-symbolic")
        self._mode_stack.add_titled_with_icon(
            self._build_solid_page(), "solid", "Solid",
            "checkbox-symbolic")
        self._mode_stack.set_visible_child_name(self._applied.glass_mode)
        self._mode_stack.set_vexpand(True)
        # After the child is set, so putting the window on the installed mode is
        # not itself a switch to react to.
        self._mode_stack.connect("notify::visible-child-name",
                                 self._on_mode_switched)

        # The badge the per-app lists already carry, for the question they
        # already ask with it: which of these several things is the one in force
        # right now. The alternative was a dot on the applied tab —
        # Adw.ViewStackPage's needs-attention, which is the only per-tab mark
        # libadwaita has — and it was rejected because it means "there is news
        # here" everywhere else a GNOME app puts one, and an unlabelled mark is
        # the wrong tool for the one thing on this page that is easy to get
        # wrong.
        self._mode_badge = Gtk.Label(halign=Gtk.Align.CENTER, wrap=True,
                                     justify=Gtk.Justification.CENTER)
        self._mode_badge.add_css_class("caption")
        self._mode_badge.add_css_class("aura-badge")
        self._sync_mode_badge()

        switcher = Adw.ViewSwitcher(stack=self._mode_stack,
                                    policy=Adw.ViewSwitcherPolicy.WIDE,
                                    halign=Gtk.Align.CENTER,
                                    margin_top=12)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.append(switcher)
        box.append(self._mode_badge)
        box.append(self._mode_stack)
        return box

    def _glass_mode(self):
        """The mode the tabs are showing, which is the mode being asked for."""
        return self._mode_stack.get_visible_child_name()

    def _mode_title(self, mode):
        """A mode's name, read back off the tab that carries it.

        Off the tab rather than out of a second list beside GLASS_MODES: the
        switcher is already showing these three words, and a copy of them here
        is a copy that can disagree with what the user is looking at.
        """
        return self._mode_stack.get_page(
            self._mode_stack.get_child_by_name(mode)).get_title()

    def _sync_mode_badge(self):
        """Say which of the three tabs the desktop is actually wearing."""
        applied = self._applied.glass_mode
        if self._glass_mode() == applied:
            self._mode_badge.set_label("In use")
            self._mode_badge.add_css_class("on")
        else:
            # The applied mode by name, rather than a bare "not this one". The
            # tab bar stops answering "so which one am I in?" the moment you
            # click away from it, which is exactly when the question gets asked.
            self._mode_badge.set_label("Not applied yet — %s is in use"
                                       % self._mode_title(applied))
            self._mode_badge.remove_css_class("on")

    def _on_mode_switched(self, _stack, _param):
        # Outside the loading guard for the reason the opacity readout is: the
        # badge has to follow the tab even when _reload was what moved it.
        self._sync_mode_badge()
        if self._loading:
            return
        # Which list the blur consults is a property of the mode, so the two
        # summaries on the Per-app blur page move with the tab.
        self._rebuild_app_list()
        self._mark_dirty()

    # ---- frosted ----------------------------------------------------------

    def _build_frosted_page(self):
        """Blur behind everything, which is the mode the theme is written for.

        Seeded from this mode's own drawer rather than from the live top-level
        memos. The tab exists whichever mode is installed, and a machine running
        Transparent still has a frosted drawer on disk — seed_glass_mode wrote
        it — holding what Apply would install if this tab were chosen. Reading
        the top-level memos instead would show a machine standing at Solid its
        own forced zeroes under a Frosted heading.
        """
        frosted = self._applied.modes["frosted"]
        page = Adw.PreferencesPage()

        # Above the switches rather than under them. Every row on this page
        # costs something, and someone who reaches this page because the desktop
        # feels slow should not have to read three subtitles to find that out.
        page.add(tip_card(
            "<b>Blur is the most expensive thing in this window.</b> The GPU "
            "redraws every blurred surface as what is behind it moves, and the "
            "shell has more to composite each frame, so it costs CPU too. On an "
            "integrated GPU, a 4K screen or a laptop on battery expect slower "
            "animations, dropped frames and less battery.\n\nIf the desktop "
            "feels heavy, turn off <b>Blur behind all application windows</b> "
            "first, then try the Transparent tab, then Solid."))

        glass = Adw.PreferencesGroup(
            title="Glass",
            description="Blur behind windows, popups and the panel.")

        # Two switches, not the dropdown this was. They are two settings in
        # install.sh — WANT_WINDOW_BLUR and APP_BLUR_SCOPE — and the dropdown
        # was the only thing that ever made them one question. Asking for the
        # blur to reach every window is now a switch you can find, rather than
        # the middle entry of a list called something else.
        self._window_blur_row = Adw.SwitchRow(
            title="Blur behind app windows",
            subtitle="Off leaves windows translucent with no blur behind them",
            active=frosted["scope"] != "none")
        self._window_blur_row.connect("notify::active", self._on_changed,
                                      "scope")
        glass.add(self._window_blur_row)

        # The cost in bold, and it is the only bold on the page. This is the one
        # switch here that measured the overview at p90 99% GPU against 32%
        # without it, and a subtitle that mentioned that in passing was a
        # subtitle people turned it on without reading.
        self._blur_all_row = Adw.SwitchRow(
            title="Blur behind all application windows",
            subtitle="On covers browsers and Electron apps too, and is "
                     "<b>heavy on the GPU</b>. Off keeps it to GTK and GNOME "
                     "apps",
            active=frosted["scope"] == "all")
        self._blur_all_row.connect("notify::active", self._on_changed, "scope")
        glass.add(self._blur_all_row)

        # Off is its own switch rather than the bottom of the bar. They are not
        # the same thing: 100% leaves the transparency sheet installed and fully
        # opaque, while off removes it, and install_transparency_css treats those
        # differently. A single control would have to pretend otherwise.
        #
        # It is also the one switch the Transparent tab does not have, and that
        # is the difference between the two modes rather than an oversight:
        # being translucent with nothing blurred behind it is what that mode is,
        # so turning it off there is asking for this tab.
        self._transparency_on = Adw.SwitchRow(
            title="Translucent app windows",
            subtitle="Let the blur and the wallpaper through GTK app windows",
            active=frosted["transparency"] != "0")
        self._transparency_on.connect("notify::active", self._on_changed,
                                      "transparency")
        glass.add(self._transparency_on)

        # The bar gets a row to itself, under the one that names it.
        #
        # It used to be a suffix on that row, which left it a few hundred pixels
        # wide with three two-line mark labels under it and GtkScale's own value
        # readout drawn over the top — four numbers competing for the same strip
        # of pixels, and on a narrow window they overlapped into an unreadable
        # smear. So: the readout moves to the row's suffix as an ordinary label,
        # the marks lose their percentages, and the bar gets the full width to
        # spread the three remaining words across.
        self._transparency_scale = self._opacity_scale(
            level_to_percent(frosted["transparency"]))

        self._transparency_row = Adw.ActionRow(
            title="Opacity",
            subtitle="Lower is more see-through. Below 70% the text stops "
                     "holding up over a bright wallpaper, so that is the floor")
        self._transparency_row.add_suffix(self._transparency_scale._readout)
        glass.add(self._transparency_row)

        self._transparency_bar = Gtk.Box(margin_start=12, margin_end=12,
                                         margin_top=4, margin_bottom=4)
        self._transparency_bar.append(self._transparency_scale)
        glass.add(self._transparency_bar)

        page.add(glass)

        # Its own group, and this is what puts the bar under the row that names
        # it. Adw.PreferencesGroup appends every non-row child after its list
        # box, so a bar added to a group with a row below it lands under that
        # row instead — which had the three marks reading as labels on the popup
        # switch. Ending the group at Opacity ends it where the bar goes.
        popups = Adw.PreferencesGroup()
        self._popup_row = Adw.SwitchRow(
            title="Blur behind menus and the top bar",
            subtitle="Popups, Quick Settings and the panel",
            active=frosted["popup_blur"])
        self._popup_row.connect("notify::active", self._on_changed, "popup_blur")
        popups.add(self._popup_row)
        page.add(popups)

        page.add(self._build_tint_group("frosted"))
        page.add(self._build_blur_strength_group("frosted"))
        return page

    # ---- transparent ------------------------------------------------------

    def _build_transparent_page(self):
        """Translucent windows with nothing blurred behind them.

        Two controls and a switch. There is no translucency on/off here: turning
        it off is asking for a different mode, and the tab bar is where that is
        asked. The level and the tint are this mode's own — they are not the
        ones the frosted tab shows, and moving one here does not move that one.
        """
        transparent = self._applied.modes["transparent"]
        page = Adw.PreferencesPage()
        page.add(tip_card(
            "Windows let the wallpaper through without the GPU cost of blurring "
            "it. Nothing is blurred behind a window, so the wallpaper is what "
            "your text sits on — which is why this mode starts darker and why "
            "70% is still the floor."))

        group = Adw.PreferencesGroup(
            title="Transparency",
            description="How much of the desktop comes through an app window.")

        self._t_transparency_scale = self._opacity_scale(
            level_to_percent(transparent["transparency"]))

        row = Adw.ActionRow(
            title="Opacity",
            subtitle="Lower is more see-through. Below 70% the text stops "
                     "holding up over a bright wallpaper, so that is the floor")
        row.add_suffix(self._t_transparency_scale._readout)
        group.add(row)

        # The bar last and loose in the group, for the reason the frosted tab
        # gives at more length: a group puts every non-row child after its list
        # box, so this is only under the row that names it while the row that
        # names it is the last one in the group.
        bar = Gtk.Box(margin_start=12, margin_end=12, margin_top=4,
                      margin_bottom=4)
        bar.append(self._t_transparency_scale)
        group.add(bar)
        page.add(group)

        popups = Adw.PreferencesGroup(
            title="Popups",
            description="The one blur this mode has. Menus and the panel are a "
                        "fraction of the pixels a window is, so this costs a "
                        "fraction of what window blur costs.")
        self._t_popup_row = Adw.SwitchRow(
            title="Blur behind menus and the top bar",
            subtitle="Popups, Quick Settings and the panel",
            active=transparent["popup_blur"])
        self._t_popup_row.connect("notify::active", self._on_changed,
                                  "popup_blur")
        popups.add(self._t_popup_row)
        page.add(popups)

        page.add(self._build_tint_group("transparent"))
        page.add(self._build_blur_strength_group(
            "transparent",
            description="How far the popup and panel blur reaches. Nothing "
                        "else is blurred in this mode, so this is the only "
                        "thing it moves."))
        return page

    def _opacity_scale(self, percent):
        """One opacity bar, with the label that reports it kept on its side.

        Two tabs have one of these and neither can borrow the other's, so the
        readout travels with the bar rather than on an attribute of the window:
        the handler is handed the bar that moved, and that is the only way it
        knows which of the two labels to write.
        """
        scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, TRANSPARENCY_MIN, TRANSPARENCY_MAX, 1)
        scale.set_hexpand(True)
        scale.set_draw_value(False)
        for at, label in TRANSPARENCY_MARKS:
            scale.add_mark(at, Gtk.PositionType.BOTTOM, label)

        # Percent, not the 0-255 actor opacity install.sh also understands: the
        # window is what the user is looking at, and 90% opaque is a thing you
        # can picture in a way that 230 is not.
        scale._readout = Gtk.Label(valign=Gtk.Align.CENTER)
        scale._readout.add_css_class("numeric")
        scale._readout.add_css_class("dim-label")

        scale.set_value(percent)
        self._sync_transparency_value(scale)
        scale.connect("value-changed", self._on_scale_changed)
        return scale

    # ---- solid ------------------------------------------------------------

    def _build_solid_page(self):
        """No controls: this tab is a description of what standing down means.

        It is the tab someone reaches because something is wrong, so it says
        what it takes away and what it leaves in the order those questions get
        asked, and it does not editorialise about performance — the frosted tab
        already does that.
        """
        page = Adw.PreferencesPage()
        page.add(tip_card(
            "<b>The theme stands down.</b> Your desktop goes back to GNOME's "
            "own look, as though this was never installed — for when something "
            "is wrong and you want the desktop back while you work out what.\n\n"
            "Nothing is deleted and nothing is forgotten. Coming back is "
            "picking another tab and pressing Apply."))

        goes = Adw.PreferencesGroup(title="What it takes away")
        for title, subtitle in (
            ("The stylesheets",
             "The aura-glass block comes out of your GTK and shell CSS, and "
             "the files it changed go back to the copies it backed up"),
            ("The shell and GTK themes",
             "Both keys go back to GNOME's defaults, so the shell is the one "
             "GNOME ships"),
            ("The extensions this installed",
             "Switched off, not removed and not reconfigured — every one of "
             "them keeps its own settings and comes back exactly as it was"),
        ):
            goes.add(Adw.ActionRow(title=title, subtitle=subtitle))
        page.add(goes)

        stays = Adw.PreferencesGroup(title="What it leaves")
        for title, subtitle in (
            ("Your icons and pointer",
             "The packs stay installed and selected"),
            ("Your accent colour",
             "A GNOME setting rather than one of this theme's, so it stands"),
            ("Every setting in the other two tabs",
             "Opacity, tint, blur strength and the per-app lists are all "
             "remembered where they are"),
            ("Extensions you installed yourself",
             "Only the ones this project installs are switched off"),
        ):
            stays.add(Adw.ActionRow(title=title, subtitle=subtitle))
        page.add(stays)
        return page

    # ---- the tint ---------------------------------------------------------

    def _build_tint_group(self, mode, description=None):
        """The colour under the glass, for the two halves of the desktop.

        Two colours rather than one, because they are two different mechanisms
        and pretending otherwise would be a lie the first time one of them
        could not do what the other did. A translucent app window has a single
        tint the whole sheet mixes toward; the shell has eight separately tuned
        grounds and gets the hue and saturation applied to each of them with
        their own lightness kept. The switch between the two rows is for the
        common case, which is wanting one colour everywhere.

        Neither is an on/off. Black is what the sheets ship with, so choosing
        black is how a tint is undone — and there is no third state to have a
        switch for.

        One group per mode, and one pair of colours per mode with it. Sharing a
        single group between two tabs is not on offer — a widget has one parent
        — and sharing the colours would be wrong anyway: the two modes seed
        different blacks, the drawer on disk keeps them apart, and a tint picked
        for a blurred window is not the one picked for a bare wallpaper.
        """
        tints = self._tints.setdefault(mode, {
            "app": self._applied.modes[mode]["app_tint"],
            "shell": self._applied.modes[mode]["shell_tint"],
        })
        rows = self._tint_rows.setdefault(mode, {})

        group = Adw.PreferencesGroup(
            title="Tint",
            description=description or
            "What the glass is coloured with. The theme darkens every "
            "translucent surface toward black before its opacity is applied; "
            "this is the colour it darkens toward instead. How dark it stays "
            "is Opacity's question, not this one.")

        rows["link"] = Adw.SwitchRow(
            title="One colour for both",
            subtitle="Point the shell at whatever the app windows are tinted "
                     "with",
            active=tints["app"] == tints["shell"])
        rows["link"].connect("notify::active", self._on_tint_link, mode)
        group.add(rows["link"])

        rows["app"] = self._tint_row(
            "App windows",
            "GTK and libadwaita windows, wherever they are translucent",
            "app", mode)
        group.add(rows["app"])

        rows["shell"] = self._tint_row(
            "Shell surfaces",
            "The panel, menus, Quick Settings, notifications and dialogs",
            "shell", mode)
        group.add(rows["shell"])

        # A window rather than an inline swatch, because what a tint does to
        # text is the whole question and one row of colour cannot answer it.
        preview = Adw.ActionRow(
            title="Preview",
            subtitle="Opens a window of real surfaces and real text in these "
                     "two colours, before anything is applied")
        button = Gtk.Button(label="Show me", valign=Gtk.Align.CENTER)
        button.connect("clicked", self._on_tint_preview, mode)
        preview.add_suffix(button)
        preview.set_activatable_widget(button)
        group.add(preview)
        return group

    def _tint_row(self, title, subtitle, which, mode):
        """One colour button, with the swatch and the hex both readable."""
        row = Adw.ActionRow(title=title, subtitle=subtitle)
        button = Gtk.ColorDialogButton(
            dialog=Gtk.ColorDialog(with_alpha=False, title="%s tint" % title),
            valign=Gtk.Align.CENTER)
        button.set_rgba(parse_hex(self._tints[mode][which]))
        button.connect("notify::rgba", self._on_tint_picked, which, mode)
        row.add_suffix(button)
        row._button = button
        return row

    def _on_tint_picked(self, button, _param, which, mode):
        if self._loading:
            return
        colour = rgba_hex(button.get_rgba())
        self._tints[mode][which] = colour
        rows = self._tint_rows[mode]

        # The link is one-directional on purpose: the app windows are the side
        # with a single honest tint behind it, so they are the side that leads.
        # Dragging the shell's own colour while the two are linked is a choice
        # to stop linking them, and the switch says so rather than snapping the
        # value back.
        if rows["link"].get_active():
            if which == "app":
                self._tints[mode]["shell"] = colour
                self._loading = True
                rows["shell"]._button.set_rgba(parse_hex(colour))
                self._loading = False
            else:
                rows["link"].set_active(False)

        self._sync_tint_preview()
        self._mark_dirty()

    def _on_tint_link(self, row, _param, mode):
        if self._loading:
            return
        if row.get_active():
            tints = self._tints[mode]
            tints["shell"] = tints["app"]
            self._loading = True
            self._tint_rows[mode]["shell"]._button.set_rgba(
                parse_hex(tints["shell"]))
            self._loading = False
            self._sync_tint_preview()
            self._mark_dirty()

    def _on_tint_preview(self, _button, mode):
        def read():
            # The opacity the bar is on right now, not the one on disk — the
            # point of the window is to judge a tint before Apply, and it is
            # the same tab's own control. The transparent tab has no off switch
            # to consult, because a window that is not translucent is not that
            # mode.
            if mode == "transparent":
                opacity = self._t_transparency_scale.get_value() / 100.0
            else:
                opacity = (self._transparency_scale.get_value() / 100.0
                           if self._transparency_on.get_active() else 1.0)
            tints = self._tints[mode]
            return tints["app"], tints["shell"], opacity

        self._tint_preview = open_over(TintPreviewWindow(read), self)
        self._tint_preview.connect(
            "close-request", lambda *_a: setattr(self, "_tint_preview", None))

    def _sync_tint_preview(self):
        """Keep an open preview window in step with the two buttons."""
        window = getattr(self, "_tint_preview", None)
        if window is not None:
            window.refresh()

    # ---- how far the blur reaches -----------------------------------------

    def _build_blur_strength_group(self, mode, description=None):
        group = Adw.PreferencesGroup(
            title="Blur amount",
            description=description or
            "One control for every blurred surface — the panel, menus, Quick "
            "Settings, the overview, app windows and the lock screen. They are "
            "already in proportion to each other, so this scales the set "
            "rather than flattening it.")

        # On the bar rather than on the window, for the reason _opacity_scale
        # gives: two tabs have one of these each, and the handler is handed the
        # bar that moved.
        readout = Gtk.Label(valign=Gtk.Align.CENTER)
        readout.add_css_class("numeric")
        readout.add_css_class("dim-label")

        row = Adw.ActionRow(
            title="Amount",
            subtitle="Higher is softer and costs more GPU time, because a "
                     "wider blur is more pixels read per frame")
        row.add_suffix(readout)
        group.add(row)

        scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, BLUR_STRENGTH_MIN, BLUR_STRENGTH_MAX, 5)
        scale.set_hexpand(True)
        scale.set_draw_value(False)
        for at, label in BLUR_STRENGTH_MARKS:
            scale.add_mark(at, Gtk.PositionType.BOTTOM, label)
        scale._readout = readout
        scale.set_value(self._applied.modes[mode]["blur_strength"])
        self._sync_blur_strength_value(scale)
        scale.connect("value-changed", self._on_blur_strength_changed)
        self._strength_scales[mode] = scale

        bar = Gtk.Box(margin_start=12, margin_end=12, margin_top=4,
                      margin_bottom=4)
        bar.append(scale)
        group.add(bar)
        return group

    def _sync_blur_strength_value(self, scale):
        scale._readout.set_label("%d%%" % round(scale.get_value()))

    def _on_blur_strength_changed(self, scale):
        self._sync_blur_strength_value(scale)
        if self._loading:
            return
        self._mark_dirty()

    def _build_window_controls_page(self):
        page = Adw.PreferencesPage()

        group = Adw.PreferencesGroup(
            title="Titlebar buttons",
            description="A GNOME setting rather than one of the theme's, shared "
                        "with Tweaks — so it is left alone until you pick one "
                        "here, and picking Leave as it is again leaves the last "
                        "one you applied standing rather than guessing a way "
                        "back.")
        self._window_buttons_row = self._combo(
            "Buttons", "", WINDOW_BUTTON_LAYOUTS,
            self._applied.window_buttons, "window_buttons")
        group.add(self._window_buttons_row)
        page.add(group)
        return page

    # ---- extensions ---------------------------------------------------------

    EXT_TIERS = [
        ("core", "Core",
         "What the desktop is built out of. Turning one off changes the look "
         "rather than trimming it, and none of them can be removed from here."),
        ("recommended", "Recommended",
         "The pack install.sh fits by default. None of it is required."),
        ("full", "Everything else",
         "The rest of --all-extras. Installed on request, one at a time."),
    ]

    def _ext_catalogue(self):
        """The catalogue, from bin/aura-glass-ext rather than a second copy.

        The arrays and their descriptions change more often than anything else
        in this project, and a hand-maintained Python copy would be wrong within
        a release. Unlike the radius numbers, which are small, stable and have a
        checker, this is a list of other people's UUIDs.
        """
        if self._repo is None:
            return []
        script = os.path.join(self._repo, "bin", "aura-glass-ext")
        try:
            res = subprocess.run(["bash", script, "list"],
                                 capture_output=True, text=True, timeout=30)
            if res.returncode != 0:
                return []
            return json.loads(res.stdout)
        except (OSError, subprocess.SubprocessError, ValueError):
            return []

    def _build_extensions_page(self):
        page = Adw.PreferencesPage()

        actions = Adw.PreferencesGroup(
            title="Extensions",
            description="These apply as you click them rather than waiting for "
                        "Apply. Enabling an extension is a gsettings key and "
                        "installing one lands under your home directory, so "
                        "none of it needs a password — and none of it is a "
                        "setting install.sh would resolve, so there is nothing "
                        "for Apply to collect.")
        row = Adw.ActionRow(
            title="Fit a pack",
            subtitle="Installs and enables everything in it, leaving the rest "
                     "alone")
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6,
                      valign=Gtk.Align.CENTER)
        for pack, label in (("recommended", "Recommended"), ("full", "All")):
            button = Gtk.Button(label=label)
            button.connect("clicked", self._on_ext_pack, pack)
            box.append(button)
        refresh = Gtk.Button(icon_name="view-refresh-symbolic",
                             tooltip_text="Re-read what is installed")
        refresh.add_css_class("flat")
        refresh.connect("clicked", lambda _b: self._rebuild_extensions())
        box.append(refresh)
        row.add_suffix(box)
        actions.add(row)
        page.add(actions)

        self._ext_groups = {}
        for tier, title, description in self.EXT_TIERS:
            group = Adw.PreferencesGroup(title=title, description=description)
            self._ext_groups[tier] = group
            page.add(group)

        self._ext_rows = []
        self._rebuild_extensions()
        return page

    def _rebuild_extensions(self):
        for group, row in self._ext_rows:
            group.remove(row)
        self._ext_rows = []

        catalogue = self._ext_catalogue()
        if not catalogue:
            for tier, _t, _d in self.EXT_TIERS[:1]:
                row = Adw.ActionRow(
                    title="Could not read the extension list",
                    subtitle="bin/aura-glass-ext did not answer — is the "
                             "checkout still there?",
                    sensitive=False)
                self._ext_groups[tier].add(row)
                self._ext_rows.append((self._ext_groups[tier], row))
            return

        for entry in catalogue:
            group = self._ext_groups.get(entry["tier"])
            if group is None:
                continue

            row = plain_row(Adw.SwitchRow(active=entry["enabled"]),
                            entry["description"])
            # The UUID under the description: the description is what it does,
            # the UUID is what it is, and only one of them is searchable.
            row.set_subtitle(entry["uuid"] + (
                "" if entry["installed"] else " — not installed"))
            row.set_sensitive(entry["installed"])
            row._uuid = entry["uuid"]
            row._handler = row.connect("notify::active", self._on_ext_toggled)

            if not entry["installed"]:
                button = Gtk.Button(label="Install", valign=Gtk.Align.CENTER)
                button.connect("clicked", self._on_ext_action, entry["uuid"],
                               "install")
                row.add_prefix(button)
            elif entry["tier"] != "core" and not entry["system"]:
                # Core stays: removing what the theme is built out of from a
                # page listing optional extras is a footgun, and turning it off
                # is already the reversible way to get the same look.
                button = Gtk.Button(icon_name="user-trash-symbolic",
                                    valign=Gtk.Align.CENTER,
                                    tooltip_text="Remove this extension")
                button.add_css_class("flat")
                button.connect("clicked", self._on_ext_action, entry["uuid"],
                               "remove")
                row.add_prefix(button)

            group.add(row)
            self._ext_rows.append((group, row))

    def _on_ext_toggled(self, row, _param):
        self._run_ext("enable" if row.get_active() else "disable", row._uuid,
                      title="Enabling" if row.get_active() else "Disabling")

    def _on_ext_action(self, _button, uuid, action):
        self._run_ext(action, uuid,
                      title="Installing" if action == "install" else "Removing")

    def _on_ext_pack(self, _button, pack):
        self._run_ext(pack, None, title="Fitting the %s pack" % pack)

    def _run_ext(self, action, uuid, title):
        if self._repo is None:
            self._toasts.add_toast(Adw.Toast(
                title="The aura-glass checkout is gone"))
            return
        argv = ["bash", os.path.join(self._repo, "bin", "aura-glass-ext"),
                action]
        if uuid:
            argv.append(uuid)

        def done(_ok):
            # Re-read rather than assume: an extension can install and still
            # decline to enable until the next login, and the row should say
            # which of those happened.
            self._rebuild_extensions()

        ApplyDialog(self._repo, [], done, title=title,
                    description="gnome-extensions is doing this, under your "
                                "home directory. No password needed.",
                    argv=argv).present(self)

    # ---- things that need root ---------------------------------------------

    def run_in_terminal(self, command, what):
        """Run a command in a real terminal window, and do not wait for it.

        For everything that needs a password. Apply runs install.sh in-window
        and reads its output down a pipe, which works precisely because
        --settings-only never asks for anything — sudo down that pipe would
        block forever on a prompt nobody can see. So these get a terminal with a
        keyboard attached, which is also what the project already tells people
        to do rather than running sudo on their behalf.

        Not waited on: the point is that the terminal is answering prompts this
        window cannot see, so there is nothing useful to wait for. Callers
        refresh their state from disk afterwards instead.
        """
        name, build = find_terminal()
        if name is None:
            self._no_terminal_dialog(command, what)
            return False
        try:
            Gio.Subprocess.new(build(keep_open(command)),
                               Gio.SubprocessFlags.NONE)
        except GLib.Error as exc:
            self._no_terminal_dialog(command, what, exc.message)
            return False
        self._toasts.add_toast(Adw.Toast(
            title="%s is running in %s" % (what, name)))
        return True

    def _no_terminal_dialog(self, command, what, why=None):
        """No terminal to be found — hand over the command rather than fail.

        A window that quietly did nothing here would be the worst outcome, and
        running the command itself is the one thing it must not do: it would
        need the password it has no way to ask for.
        """
        dialog = Adw.AlertDialog(
            heading="Run this in a terminal",
            body=("%s needs a terminal, and none of the ones this knows about "
                  "are installed%s. Copy the command and run it yourself — it "
                  "will ask for your password."
                  % (what, "" if why is None else " (%s)" % why)))

        entry = Gtk.Entry(text=command, editable=False, hexpand=True)
        entry.add_css_class("monospace")
        dialog.set_extra_child(entry)

        dialog.add_response("copy", "Copy")
        dialog.add_response("close", "Close")
        dialog.set_default_response("copy")
        dialog.set_close_response("close")

        def response(_d, answer):
            if answer == "copy":
                self.get_clipboard().set(command)
                self._toasts.add_toast(Adw.Toast(title="Command copied"))

        dialog.connect("response", response)
        dialog.present(self)

    def _install_cmd(self, args):
        """`bash <repo>/install.sh <args>`, quoted for a shell."""
        return "bash %s %s" % (
            GLib.shell_quote(os.path.join(self._repo, "install.sh")), args)

    def _build_system_page(self):
        page = Adw.PreferencesPage()

        group = Adw.PreferencesGroup(
            title="Needs a password",
            description="These are the steps install.sh cannot do without root, "
                        "so this window opens a terminal for them rather than "
                        "starting something that would silently decline. "
                        "Nothing here is applied by the Apply button.")
        reread = Gtk.Button(icon_name="view-refresh-symbolic",
                            valign=Gtk.Align.CENTER,
                            tooltip_text="Re-read after a terminal has closed")
        reread.add_css_class("flat")
        reread.connect("clicked", lambda _b: self._refresh_system())
        group.set_header_suffix(reread)

        self._deps_row = Adw.ActionRow(
            title="Command line dependencies",
            subtitle="Checking…")
        deps_check = Gtk.Button(label="Check", valign=Gtk.Align.CENTER)
        deps_check.connect("clicked", lambda _b: self._check_deps())
        self._deps_install = Gtk.Button(label="Install",
                                        valign=Gtk.Align.CENTER,
                                        sensitive=False)
        self._deps_install.add_css_class("suggested-action")
        self._deps_install.connect("clicked", self._on_install_deps)
        self._deps_row.add_suffix(deps_check)
        self._deps_row.add_suffix(self._deps_install)
        group.add(self._deps_row)

        # Its state is a stamp file rather than a setting, so it is a button
        # that acts rather than a switch Apply would collect. Nothing here goes
        # through Settings or flags_against.
        self._rounded_row = Adw.ActionRow(
            title="Rounded blur library",
            subtitle="Lets the blur behind popups follow their rounded corners "
                     "instead of falling back to a static one")
        self._rounded_button = Gtk.Button(label="Install",
                                          valign=Gtk.Align.CENTER)
        self._rounded_button.connect("clicked", self._on_install_rounded_blur)
        self._rounded_row.add_suffix(self._rounded_button)
        group.add(self._rounded_row)

        # Two separate things, despite both being "multi-monitor". This one is
        # a user systemd unit and rides on Apply with everything else; the sync
        # below copies into /etc and GDM's own home, and cannot.
        self._gdm_monitors_row = Adw.ActionRow(
            title="Sync the monitor layout to the login screen",
            subtitle="Copies ~/.config/monitors.xml where GDM will read it, so "
                     "the login screen comes up on the same monitor your "
                     "session does")
        self._gdm_monitors_button = Gtk.Button(valign=Gtk.Align.CENTER)
        self._gdm_monitors_button.connect("clicked", self._on_gdm_monitors)
        self._gdm_monitors_row.add_suffix(self._gdm_monitors_button)
        group.add(self._gdm_monitors_row)

        self._gdm_row = Adw.ActionRow(title="Theme the login screen")
        self._gdm_button = Gtk.Button(valign=Gtk.Align.CENTER)
        self._gdm_button.connect("clicked", self._on_gdm)
        self._gdm_row.add_suffix(self._gdm_button)
        group.add(self._gdm_row)
        page.add(group)

        local = Adw.PreferencesGroup(
            title="Runs without a password",
            description="A user systemd unit, so this one rides on Apply with "
                        "the rest of the window.")
        self._panel_blur_row = Adw.SwitchRow(
            title="Rebuild the panel blur after a monitor change",
            subtitle="Blur My Shell clips the panel blur to a geometry that is "
                     "not settled yet at login, which leaves a strip of it "
                     "wrong until something disturbs it. This puts it back",
            active=self._applied.panel_blur_fix)
        self._panel_blur_row.connect("notify::active", self._on_changed,
                                     "panel_blur_fix")
        local.add(self._panel_blur_row)
        page.add(local)

        self._sync_system()
        self._check_deps()
        return page

    def _refresh_system(self):
        """Re-read the stamp files, for after a spawned terminal has been and
        gone. There is no signal that it finished — that is the price of it
        having a keyboard — so this is on a button."""
        self._sync_system()
        self._toasts.add_toast(Adw.Toast(title="Re-read"))

    def _on_gdm_monitors(self, _button):
        synced = os.path.exists(os.path.join(CONF_DIR, "gdm-monitors-synced"))
        if synced:
            self.run_in_terminal(
                "bash %s --gdm-monitors --yes"
                % GLib.shell_quote(os.path.join(self._repo, "uninstall.sh")),
                "Removing the login screen monitor layout")
            return
        self._confirm_root(
            "Sync the monitor layout to the login screen?",
            "This copies ~/.config/monitors.xml into /etc/xdg and into GDM's "
            "own home directory, so it needs your password. A terminal will "
            "open and ask for it.",
            "Sync",
            self._install_cmd("--gdm-monitors --yes"),
            "Syncing the monitor layout")

    def _on_gdm(self, _button):
        installed = read_memo("gdm-installed")
        if installed:
            self._confirm_root(
                "Remove the login screen theme?",
                "This puts GNOME's own login screen back. It modifies files "
                "under /usr, so it needs your password — a terminal will open "
                "and ask for it.",
                "Remove",
                "bash %s --gdm --yes"
                % GLib.shell_quote(os.path.join(self._repo, "uninstall.sh")),
                "Removing the login screen theme")
            return
        self._confirm_root(
            "Theme the login screen?",
            "This modifies system files under /usr and needs your password — a "
            "terminal will open and ask for it. The first run also clones and "
            "patches a copy of the WhiteSur theme, which takes a minute.\n\n"
            "The login screen keeps GNOME's accent colour rather than this "
            "theme's: it is compiled separately and does not read the desktop's "
            "stylesheets.",
            "Theme it",
            self._install_cmd("--gdm --yes"),
            "Theming the login screen")

    def _confirm_root(self, heading, body, verb, command, what):
        dialog = Adw.AlertDialog(heading=heading, body=body)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("go", verb)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")

        def response(_d, answer):
            if answer == "go":
                self.run_in_terminal(command, what)

        dialog.connect("response", response)
        dialog.present(self)

    def _sync_system(self):
        """Read the stamp files these buttons act on.

        Every one of them is "last known" rather than live. A spawned terminal
        is not waited on — the whole point is that it is answering prompts this
        window cannot see — so nothing here can know the moment one finishes.
        The rows say so rather than implying otherwise.
        """
        installed = os.path.exists(os.path.join(CONF_DIR, "rounded-blur"))
        self._rounded_row.set_subtitle(
            "Installed. Reinstall if a mutter update stopped it loading"
            if installed else
            "Lets the blur behind popups follow their rounded corners instead "
            "of falling back to a static one")
        self._rounded_button.set_label("Reinstall" if installed else "Install")

        synced = os.path.exists(os.path.join(CONF_DIR, "gdm-monitors-synced"))
        self._gdm_monitors_button.set_label("Remove" if synced else "Sync")
        self._gdm_monitors_row.set_subtitle(
            "Synced, as of the last time this window looked. Use Re-read after "
            "the terminal closes" if synced else
            "Copies ~/.config/monitors.xml where GDM will read it, so the login "
            "screen comes up on the same monitor your session does")

        gdm = read_memo("gdm-installed")
        self._gdm_button.set_label("Remove" if gdm else "Theme it")
        self._gdm_row.set_subtitle(
            "Themed, as of the last time this window looked. Use Re-read after "
            "the terminal closes" if gdm else
            "Blurs and darkens your wallpaper behind the login screen. Needs "
            "your password, and keeps GNOME's accent rather than this theme's")

        for widget in (self._rounded_button, self._gdm_monitors_button,
                       self._gdm_button):
            widget.set_sensitive(self._repo is not None)

    def _check_deps(self):
        """Ask install.sh's own missing_cmds, which needs no root to answer."""
        self._deps_row.set_subtitle("Checking…")
        if self._repo is None:
            self._deps_row.set_subtitle("The aura-glass checkout is gone")
            return

        script = (". %s/lib/common.sh; . %s/lib/distro.sh; "
                  "detect_distro >/dev/null 2>&1; missing_cmds"
                  % (GLib.shell_quote(self._repo), GLib.shell_quote(self._repo)))
        try:
            res = subprocess.run(["bash", "-c", script], capture_output=True,
                                 text=True, timeout=20)
        except (OSError, subprocess.SubprocessError) as exc:
            self._deps_row.set_subtitle("Could not check: %s" % exc)
            return

        missing = [line.strip() for line in res.stdout.splitlines()
                   if line.strip()]
        if missing:
            self._deps_row.set_subtitle(
                "Missing: %s" % ", ".join(missing))
        else:
            self._deps_row.set_subtitle("All present")
        self._deps_install.set_sensitive(bool(missing) and self._repo is not None)

    def _on_install_deps(self, _button):
        self.run_in_terminal(self._install_cmd("--deps-only"),
                             "Installing dependencies")

    def _on_install_rounded_blur(self, _button):
        # No --yes. install_rounded_blur asks with confirm_always, which asks
        # even under --yes because it is a root package — and a real terminal is
        # exactly where that question can be answered, so it is left to ask
        # rather than pre-answered on the user's behalf.
        self.run_in_terminal(self._install_cmd("--rounded-blur --force"),
                             "Installing the rounded blur library")

    # The three scopes uninstall.sh already has, in the order it offers them.
    # Each is its own row and its own confirmation rather than a dropdown with
    # one button: the difference between them is the difference between undoing
    # the styling and deleting the packs, and a control where that difference is
    # a selection you might mis-read is the wrong control.
    UNINSTALL_SCOPES = [
        ("", "Revert the styling", "Undo",
         "Puts the stylesheets, the gsettings and the extensions' settings "
         "back. Leaves the extensions and the icon packs installed.",
         "This strips the aura-glass block out of your GTK and shell "
         "stylesheets, restores the files it backed up, resets the accent, "
         "theme, icon and pointer keys, and removes the agents it installed.\n\n"
         "The extensions and the icon packs stay."),
        ("--extensions", "Revert, and remove the extensions", "Remove",
         "Everything above, and deletes the extensions this installed along "
         "with their settings.",
         "Everything the first scope does, and deletes the sixteen extensions "
         "this installed, with their settings.\n\n"
         "Extensions your distribution packaged are left alone."),
        ("--all", "Remove everything", "Remove everything",
         "Everything above, plus the theme, the icon and pointer packs, the "
         "source cache, the login screen theme and its monitor layout.",
         "Everything the other two do, and deletes the Tahoe theme, every "
         "Colloid, Reversal and MacTahoe pack under your home directory, and "
         "the download cache. It also puts GNOME's own login screen back and "
         "undoes the monitor layout sync.\n\n"
         "This is the whole of it. There is nothing left to undo afterwards."),
    ]

    def _build_uninstall_page(self):
        page = Adw.PreferencesPage()

        group = Adw.PreferencesGroup(
            title="Uninstall",
            description="These run uninstall.sh in a terminal. Parts of each "
                        "need your password, and all of it is easier to watch "
                        "than to read back afterwards. None of it can be "
                        "undone from here — reinstalling is the way back.")

        for flags, title, verb, subtitle, body in self.UNINSTALL_SCOPES:
            row = Adw.ActionRow(title=title, subtitle=subtitle)
            button = Gtk.Button(label=verb, valign=Gtk.Align.CENTER)
            button.add_css_class("destructive-action")
            button.connect("clicked", self._on_uninstall, flags, title, verb,
                           body)
            button.set_sensitive(self._repo is not None)
            row.add_suffix(button)
            group.add(row)
        page.add(group)
        return page

    def _on_uninstall(self, _button, flags, title, verb, body):
        dialog = Adw.AlertDialog(heading=title + "?", body=body)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("go", verb)
        # Destructive rather than suggested, and Cancel is what Escape and the
        # default land on. Nothing on this page should be one stray Return away.
        dialog.set_response_appearance("go",
                                       Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")

        def response(_d, answer):
            if answer != "go":
                return
            command = "bash %s %s --yes" % (
                GLib.shell_quote(os.path.join(self._repo, "uninstall.sh")),
                flags)
            self.run_in_terminal(command.replace("  ", " "), title)

        dialog.connect("response", response)
        dialog.present(self)

    def _build_packages_page(self):
        page = Adw.PreferencesPage()

        self._packs_mine = Adw.PreferencesGroup(
            title="Installed for you",
            description="Icon and pointer packs under your home directory. "
                        "Switching packs never removes the one you left, so "
                        "they accumulate — this is where to get the space back.")
        page.add(self._packs_mine)

        # Listed rather than hidden. Colloid and MacTahoe often arrive from the
        # distribution rather than from install.sh, and a page that showed no
        # trace of the pack currently on screen would look broken.
        #
        # Remove here goes through the package manager, never through rmtree.
        # These files are a package's, and deleting them out from under it
        # would leave the database claiming files that are gone — which is the
        # same reason uninstall.sh will not delete gnome-rounded-blur for you.
        # pkg_owner and pkg_remove_cmd in lib/distro.sh answer which package
        # and which command; the command runs in a terminal, because it is
        # root's work and a password prompt needs a keyboard.
        self._packs_system = Adw.PreferencesGroup(
            title="Installed system-wide",
            description="Owned by your distribution's package manager. Remove "
                        "asks it to take one out, in a terminal, so you can "
                        "see what else it would go with.")
        page.add(self._packs_system)

        self._pack_rows = []
        self._rebuild_packs()
        return page

    def _live_theme_stems(self):
        """The stems of the icon and cursor themes actually in use right now."""
        try:
            iface = Gio.Settings.new("org.gnome.desktop.interface")
            return {theme_stem(iface.get_string("icon-theme")),
                    theme_stem(iface.get_string("cursor-theme"))}
        except GLib.Error:
            return set()

    def _rebuild_packs(self):
        for group, row in self._pack_rows:
            group.remove(row)
        self._pack_rows = []

        live = self._live_theme_stems()

        # Grouped, not one row per directory. A pack is its light/dark pair —
        # Colloid ships -Light and -Dark, Reversal the bare name plus -dark, and
        # the icon-sync agent swaps between them — so removing one half of one
        # is never the thing anyone meant. Yours group by that pair, since that
        # is what Remove acts on. The system's group by family instead: there is
        # no button on them, and Colloid alone arrives as 27 directories that
        # would bury everything else for no gain.
        mine_groups, system_groups = {}, {}
        for name, path, is_mine in installed_packs():
            key = theme_stem(name) if is_mine else pack_family(name)
            bucket = mine_groups if is_mine else system_groups
            entry = bucket.setdefault(key, {"names": [], "paths": [],
                                            "in_use": False})
            entry["names"].append(name)
            entry["paths"].append(path)
            if theme_stem(name) in live:
                entry["in_use"] = True

        for bucket, group, empty in (
                (mine_groups, self._packs_mine,
                 "No packs under your home directory"),
                (system_groups, self._packs_system,
                 "No packs installed system-wide")):
            for key in sorted(bucket):
                entry = bucket[key]
                # The shortest name in the pair reads as the pack's own name:
                # Reversal-purple rather than Reversal-purple-dark.
                title = min(entry["names"], key=len)
                row = plain_row(Adw.ActionRow(), title)
                row._paths = entry["paths"]
                row._in_use = entry["in_use"]
                row._sized = False
                row._size_text = None
                # Only the system rows have an owner to look for, and None here
                # is "not asked yet" while "" is "asked, and no package claims
                # it" — a directory someone unpacked into /usr by hand.
                row._owner = None if group is self._packs_system else ""
                self._sync_pack_subtitle(row)

                if group is self._packs_mine:
                    remove = Gtk.Button(icon_name="user-trash-symbolic",
                                        valign=Gtk.Align.CENTER,
                                        tooltip_text="Remove this pack")
                    remove.add_css_class("flat")
                    remove.add_css_class("destructive-action")
                    remove.connect("clicked", self._on_remove_pack, row, title)
                    row.add_suffix(remove)

                group.add(row)
                self._pack_rows.append((group, row))

            if not bucket:
                row = Adw.ActionRow(title=empty, sensitive=False)
                group.add(row)
                self._pack_rows.append((group, row))

        # Sizes and owners both come after the rows are up. Walking a full icon
        # theme is tens of thousands of stat calls and asking the package
        # manager who owns a path forks a process, and doing either before the
        # page exists would make opening the window wait on all of them.
        GLib.idle_add(self._size_next_pack)
        GLib.idle_add(self._own_next_pack)

    def _sync_pack_subtitle(self, row):
        """One subtitle from facts that arrive at different times.

        The size walk and the owner lookup are separate idle passes and finish
        in whichever order they finish, so neither writes the subtitle itself —
        they record what they learned and ask for it to be composed again.
        """
        line = "In use" if row._in_use else "Not in use"
        if row._size_text:
            line += " — " + row._size_text
        if row._owner:
            line += " — " + row._owner
        row.set_subtitle(line)

    def _size_next_pack(self):
        for _group, row in self._pack_rows:
            if getattr(row, "_sized", True):
                continue
            row._sized = True
            total = sum(dir_size(p) for p in row._paths)
            row._size_text = human_size(total)
            if len(row._paths) > 1:
                row._size_text += " (%d variants)" % len(row._paths)
            self._sync_pack_subtitle(row)
            return True     # one per idle turn, so the window stays responsive
        return False

    def _own_next_pack(self):
        """Name the package behind one system row, and give it a Remove."""
        for group, row in self._pack_rows:
            if group is not self._packs_system or row._owner is not None:
                continue
            row._owner = pkg_owner(self._repo, row._paths[0]) or ""
            self._sync_pack_subtitle(row)

            command = pkg_remove_cmd(self._repo, row._owner)
            if command:
                remove = Gtk.Button(icon_name="user-trash-symbolic",
                                    valign=Gtk.Align.CENTER,
                                    tooltip_text="Remove %s with your package "
                                                 "manager" % row._owner)
                remove.add_css_class("flat")
                remove.add_css_class("destructive-action")
                remove.connect("clicked", self._on_remove_system_pack,
                               row.get_title(), row._owner, command,
                               row._in_use)
                row.add_suffix(remove)
            return True
        return False

    def _on_remove_system_pack(self, _button, title, package, command, in_use):
        body = ("%s belongs to the package %s, so removing it is your package "
                "manager's job rather than this window's.\n\nThis opens a "
                "terminal and runs:\n\n    %s\n\nIt will ask for your password, "
                "and it will list anything that depends on the package before "
                "it does anything — read that list. Nothing is removed until "
                "you answer it."
                % (title, package, command))
        if in_use:
            body += ("\n\n%s is the theme in use right now. Removing it leaves "
                     "the desktop showing fallback icons until you choose "
                     "another pack." % title)

        self._confirm_root("Remove %s?" % package, body, "Open a terminal",
                           command, "Removing %s" % package)

    def _on_remove_pack(self, _button, row, name):
        where = "\n".join(row._paths)
        if row._in_use:
            body = ("%s is the theme in use right now. Removing it leaves the "
                    "desktop showing fallback icons until you choose another "
                    "pack.\n\nThis deletes:\n%s\n\nIt cannot be undone."
                    % (name, where))
        else:
            body = ("This deletes:\n%s\n\nIt cannot be undone, though choosing "
                    "this pack again later would fetch it again." % where)

        dialog = Adw.AlertDialog(heading="Remove %s?" % name, body=body)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("remove", "Remove")
        dialog.set_response_appearance("remove",
                                       Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")
        dialog.connect("response", self._on_remove_pack_response, name,
                       list(row._paths))
        dialog.present(self)

    def _on_remove_pack_response(self, _dialog, response, name, paths):
        if response != "remove":
            return
        for path in paths:
            try:
                shutil.rmtree(path)
            except OSError as exc:
                self._toasts.add_toast(Adw.Toast(
                    title="Could not remove %s: %s" % (name, exc.strerror)))
                self._rebuild_packs()
                return
        self._toasts.add_toast(Adw.Toast(title="Removed %s" % name))
        self._rebuild_packs()

    def _build_apps_page(self):
        page = Adw.PreferencesPage()

        # Both lists, always. Blur My Shell consults one or the other depending
        # on enable-all, which is the same choice the blur mode makes — but they
        # are separate memos, apply_app_blur writes both every run, and neither
        # is emptied by a mode switch. Showing only the active one said the
        # opposite, which is what made the other look lost.
        self._allow = list(self._applied.allow)
        self._block = list(self._applied.block)

        self._allow_row = self._list_summary_row(page, "allow")
        self._block_row = self._list_summary_row(page, "block")
        self._rebuild_app_list()
        return page

    # Title, description and empty-state wording for each list, in one place:
    # the summary row, the window it opens and the banner in that window all
    # need them to agree, and three copies of a sentence is how they stop.
    LIST_TEXT = {
        "allow": (
            "Apps to blur",
            "Consulted while the blur is limited to GTK and GNOME apps. Only "
            "what is listed gets the blur and the window opacity — Blur My "
            "Shell applies those together, so an app cannot be translucent "
            "without also being blurred.",
            "Empty — nothing would be blurred",
        ),
        "block": (
            "Apps never blurred",
            "Consulted while every app is blurred. Everything not listed gets "
            "the blur and the window opacity; these are the exceptions, and "
            "they are worth having — browsers and Electron apps redraw "
            "constantly, so a blur behind them is rebuilt constantly.",
            "Empty — nothing is excluded",
        ),
    }

    def _list_summary_row(self, page, which):
        title, description, _empty = self.LIST_TEXT[which]

        # The group's own title and description, built by hand, because the
        # badge belongs against the end of the title rather than against the
        # end of the window. Adw.PreferencesGroup has one slot in its header —
        # the suffix — and lays it out hard against the right edge with the
        # title's own box expanding into the gap, which put "In use" four
        # hundred pixels away from the words it qualifies. Handing the whole
        # header to the suffix puts the two together, where a badge reads as
        # part of the heading instead of as a stray pill.
        badge = Gtk.Label()
        badge.add_css_class("caption")
        badge.add_css_class("aura-badge")

        heading = Gtk.Label(label=title, xalign=0)
        heading.add_css_class("heading")
        line = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        line.append(heading)
        line.append(badge)

        subtitle = Gtk.Label(label=description, xalign=0, wrap=True)
        subtitle.add_css_class("dim-label")

        header = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4,
                         hexpand=True)
        header.append(line)
        header.append(subtitle)

        group = Adw.PreferencesGroup()
        group.set_header_suffix(header)

        row = Adw.ActionRow(title="Listed apps")
        row._badge = badge
        edit = Gtk.Button(label="Edit", valign=Gtk.Align.CENTER)
        edit.connect("clicked", self._on_edit_list, which)
        row.add_suffix(edit)
        row.set_activatable_widget(edit)
        group.add(row)
        page.add(group)
        return row

    def _build_updates_page(self):
        page = Adw.PreferencesPage()

        # Both the description and the version row's title are rewritten by
        # _sync_updates, which is the one place that knows which of the two lines
        # this checkout is on. These are what a released install reads.
        self._updates_group = Adw.PreferencesGroup(
            title="Updates",
            description="The check asks the git remote which release tags exist. "
                        "It never installs anything on its own.")
        updates = self._updates_group

        self._version_row = Adw.ActionRow(title="Version")
        self._check_button = Gtk.Button(label="Check now",
                                        valign=Gtk.Align.CENTER)
        self._check_button.connect("clicked", self._on_check_updates)
        self._version_row.add_suffix(self._check_button)
        updates.add(self._version_row)

        self._update_button_row = Adw.ActionRow(
            title="Install update",
            subtitle="Pulls the new release and runs the full installer")
        self._update_button = Gtk.Button(label="Install",
                                         valign=Gtk.Align.CENTER)
        self._update_button.add_css_class("suggested-action")
        self._update_button.connect("clicked", self._on_install_update)
        self._update_button_row.add_suffix(self._update_button)
        updates.add(self._update_button_row)

        self._update_check_row = Adw.SwitchRow(
            title="Check daily",
            subtitle="One notification per release, in the background",
            active=self._applied.update_check)
        self._update_check_row.connect("notify::active", self._on_changed,
                                       "update_check")
        updates.add(self._update_check_row)
        page.add(updates)
        self._sync_updates()

        return page

    # ---- state ------------------------------------------------------------

    # ---- the per-app list -------------------------------------------------

    def _scope(self):
        """The three-way install.sh value, from the frosted tab's two switches.

        Only that tab has them, and only that mode has a scope: the other two
        do not blur behind a window at all, which _current spells "none"
        without asking here.
        """
        if not self._window_blur_row.get_active():
            return "none"
        return "all" if self._blur_all_row.get_active() else "gtk"

    def _list_is_consulted(self, which):
        """Whether the mode the tabs are showing reads this list."""
        # Frosted first, because a window blur is the only thing that consults
        # either list and frosted is the only mode that has one. Transparent
        # keeps both lists — they are the same two memos, apply_app_blur still
        # writes them and flags_against still sends an edit — but nothing reads
        # them while it is in force.
        if self._glass_mode() != "frosted":
            return False
        scope = self._scope()
        if scope == "none":
            return False
        return (scope == "all") == (which == "block")

    def _rebuild_app_list(self):
        """Put both summaries back in step with the two lists."""
        for which, row in (("allow", self._allow_row),
                           ("block", self._block_row)):
            entries = self._allow if which == "allow" else self._block
            _title, _desc, empty = self.LIST_TEXT[which]

            if entries:
                shown = ", ".join(app_name(e) for e in entries[:3])
                if len(entries) > 3:
                    shown += " and %d more" % (len(entries) - 3)
            else:
                shown = empty
            row.set_subtitle(shown)

            # Changing which list is consulted changes the badge and nothing
            # else: dimming the idle list would put back the "your list is
            # gone" reading the two groups exist to fix. That covers the
            # Transparent tab too, which consults neither and keeps both. Solid
            # is the one case that does dim them, and it is not the same case —
            # there is no blur at all to list apps for, and flags_against
            # returns on the mode flag alone, so an edit made there would be
            # dropped rather than stored.
            if self._glass_mode() == "solid":
                row.set_sensitive(False)
                row._badge.remove_css_class("on")
                row._badge.set_label("Solid mode — nothing is blurred")
                continue
            row.set_sensitive(True)
            live = self._list_is_consulted(which)
            row._badge.set_label("In use" if live else "Not in use right now")
            if live:
                row._badge.add_css_class("on")
            else:
                row._badge.remove_css_class("on")

    def _on_edit_list(self, _button, which):
        title, description, _empty = self.LIST_TEXT[which]
        entries = self._allow if which == "allow" else self._block

        def changed():
            self._rebuild_app_list()
            self._mark_dirty()

        note = None
        if not self._list_is_consulted(which):
            if self._glass_mode() == "frosted":
                other = "every app is blurred" if which == "allow" \
                    else "the blur is limited to GTK and GNOME apps"
            else:
                # Outside frosted it is not the other list's turn — there is no
                # window blur to have a turn at, and saying which list is
                # winning would be answering a question nobody asked.
                other = "the glass mode is %s" % self._mode_title(
                    self._glass_mode()).lower()
            note = ("Kept, but not consulted while %s. Edits are saved either "
                    "way." % other)

        open_over(AppListWindow(which, title, description, entries, changed,
                                note), self)

    # ---- state ------------------------------------------------------------

    def _current(self):
        """What the widgets are asking for."""
        s = Settings.__new__(Settings)
        s.accent = self._accent_row._ids[self._accent_row.get_selected()]
        s.radius = self._radius_preset_name()
        s.radius_custom = self._radius_values()
        # The tab that is showing is the mode being asked for, and every glass
        # field below is read off that tab's own controls — never off another
        # tab's, which hold that other mode's settings and are not what this
        # Apply is about.
        s.glass_mode = self._glass_mode()
        s.blur = s.glass_mode != "solid"
        if s.glass_mode == "solid":
            # This tab has no tint rows, no strength bar and no opacity, so the
            # applied values come through untouched rather than being read off
            # widgets that are not there — and what solid forces is what it
            # forces. flags_against returns on the mode flag alone for solid, so
            # none of this is ever sent.
            s.app_tint = self._applied.app_tint
            s.shell_tint = self._applied.shell_tint
            s.blur_strength = self._applied.blur_strength
            s.scope = "none"
            s.transparency = "0"
            s.popup_blur = False
        else:
            tints = self._tints[s.glass_mode]
            s.app_tint = tints["app"]
            s.shell_tint = tints["shell"]
            s.blur_strength = int(round(
                self._strength_scales[s.glass_mode].get_value()))
            if s.glass_mode == "transparent":
                # No scope and no off switch. Not blurring behind a window is
                # what this mode is, and a level of 0 is not a state it has.
                s.scope = "none"
                s.transparency = percent_to_level(
                    round(self._t_transparency_scale.get_value()))
                s.popup_blur = self._t_popup_row.get_active()
            else:
                s.scope = self._scope()
                s.transparency = (
                    percent_to_level(
                        round(self._transparency_scale.get_value()))
                    if self._transparency_on.get_active() else "0")
                s.popup_blur = self._popup_row.get_active()
        s.allow = list(self._allow)
        s.block = list(self._block)
        s.icons = join_icons(
            self._icons_row._ids[self._icons_row.get_selected()],
            self._icon_color_row._ids[self._icon_color_row.get_selected()])
        s.cursors = self._cursors_row._ids[self._cursors_row.get_selected()]
        s.window_buttons = self._window_buttons_row._ids[
            self._window_buttons_row.get_selected()]
        s.panel_blur_fix = self._panel_blur_row.get_active()
        s.update_check = self._update_check_row.get_active()
        # Not settings, so they never differ and never produce a flag. Carried so
        # flags_against sees a complete object either way.
        s.update_available = self._applied.update_available
        return s

    def _sync_sensitivity(self):
        """Only the rows that depend on another row in the same tab.

        Every glass row here is the frosted tab's, and is named as that tab's
        rather than looked up through whichever tab is showing. They exist
        whatever the mode is, so keeping them in step costs nothing and is
        right whenever the tab comes back into view; the transparent tab has no
        row that dims another, because its translucency is the mode rather than
        a switch; and solid has no controls at all. Returning early on solid —
        the obvious way to keep this off a tab with nothing in it — would have
        taken the icon row at the bottom with it, and that one has nothing to
        do with glass.

        What this used to do as well was dim four rows to say "solid mode is
        on, so none of this applies". Solid is a tab now, and a control that
        does not apply is in another one.
        """
        # Nothing to widen when there is no window blur to widen.
        self._blur_all_row.set_sensitive(self._window_blur_row.get_active())
        # Nothing to set a level on when translucency itself is off.
        live = self._transparency_on.get_active()
        self._transparency_row.set_sensitive(live)
        self._transparency_bar.set_sensitive(live)

        # The app tint lives in the transparency sheet, which is removed rather
        # than switched off when the windows are opaque — so with translucency
        # off there is nothing for a colour to tint. The shell's own surfaces
        # are translucent in their stylesheets whatever this switch says, so
        # that row stays live.
        self._tint_rows["frosted"]["app"].set_sensitive(live)
        self._tint_rows["frosted"]["link"].set_sensitive(live)

        # Neither "keep" nor "original" is a pack with colours to pick from.
        self._icon_color_row.set_sensitive(
            self._icons_row._ids[self._icons_row.get_selected()]
            not in ("keep", "original"))

    def _mark_dirty(self):
        dirty = bool(self._current().flags_against(self._applied))
        self._apply.set_sensitive(dirty and self._repo is not None)

    def _sync_transparency_value(self, scale):
        scale._readout.set_label("%d%%" % round(scale.get_value()))

    def _on_scale_changed(self, scale):
        # Outside the loading guard: the readout has to follow the bar even when
        # the bar was moved by _reload rather than by a hand. The bar that moved
        # rather than a bar this method names: two tabs have one each.
        self._sync_transparency_value(scale)
        # The tint preview draws its surfaces at whatever the bar says, so it
        # follows the bar as well as the two colour buttons.
        self._sync_tint_preview()
        if self._loading:
            return
        self._mark_dirty()

    def _on_changed(self, row, _param, key):
        if self._loading:
            return
        if isinstance(row, Adw.ComboRow):
            self._sync_subtitle(row)
        # Each pack names its own colours, so choosing one changes what the
        # colour row may offer. Guarded, because refilling moves that row's
        # selection and would otherwise re-enter here.
        if key == "icons":
            family = self._icons_row._ids[self._icons_row.get_selected()]
            color = self._icon_color_row._ids[
                self._icon_color_row.get_selected()]
            self._loading = True
            self._refill_combo(self._icon_color_row, ICON_COLORS[family], color)
            self._loading = False

        if key == "radius":
            self._sync_radius_state()

        if key in ("transparency", "scope", "icons"):
            self._sync_sensitivity()
        # The scope decides which list is consulted, so it decides which badge
        # is lit. The mode does too, and _on_mode_switched says so there.
        if key == "scope":
            self._rebuild_app_list()
        self._mark_dirty()

    def _reload(self):
        """Re-read the disk and put the widgets back in step with it."""
        self._applied = Settings()
        self._loading = True
        self._accent_row.set_selected(
            self._accent_row._ids.index(self._applied.accent))
        self._load_radius(self._applied)

        # The tab first, then every tab's controls — not only the showing one's.
        # Each was seeded from its own mode's drawer when it was built, Apply
        # can have rewritten any of them, and Revert is a promise about the
        # whole window rather than about the page in front of it.
        self._mode_stack.set_visible_child_name(self._applied.glass_mode)
        # Again by hand, because the line above only emits when the name
        # actually changes and the common reload is the one that lands back on
        # the tab it started on.
        self._sync_mode_badge()

        frosted = self._applied.modes["frosted"]
        self._window_blur_row.set_active(frosted["scope"] != "none")
        self._blur_all_row.set_active(frosted["scope"] == "all")
        self._transparency_on.set_active(frosted["transparency"] != "0")
        # Only when it is on: off is stored as a flat "0", and moving the bar to
        # 70% because of that would lose the level to come back to.
        if frosted["transparency"] != "0":
            self._transparency_scale.set_value(
                level_to_percent(frosted["transparency"]))
        self._popup_row.set_active(frosted["popup_blur"])

        transparent = self._applied.modes["transparent"]
        # No such guard here: this mode has no off, so its level is always a
        # level and there is nothing to come back to.
        self._t_transparency_scale.set_value(
            level_to_percent(transparent["transparency"]))
        self._t_popup_row.set_active(transparent["popup_blur"])

        for mode, tints in self._tints.items():
            drawer = self._applied.modes[mode]
            tints["app"] = drawer["app_tint"]
            tints["shell"] = drawer["shell_tint"]
            rows = self._tint_rows[mode]
            rows["app"]._button.set_rgba(parse_hex(tints["app"]))
            rows["shell"]._button.set_rgba(parse_hex(tints["shell"]))
            rows["link"].set_active(tints["app"] == tints["shell"])
            self._strength_scales[mode].set_value(drawer["blur_strength"])

        self._allow = list(self._applied.allow)
        self._block = list(self._applied.block)
        family, color = split_icons(self._applied.icons)
        self._icons_row.set_selected(self._icons_row._ids.index(family))
        self._refill_combo(self._icon_color_row, ICON_COLORS[family], color)
        self._cursors_row.set_selected(
            self._cursors_row._ids.index(self._applied.cursors))
        self._window_buttons_row.set_selected(
            self._window_buttons_row._ids.index(self._applied.window_buttons))
        self._panel_blur_row.set_active(self._applied.panel_blur_fix)
        self._update_check_row.set_active(self._applied.update_check)
        self._loading = False
        self._rebuild_app_list()
        self._sync_sensitivity()
        self._sync_tint_preview()
        self._apply.set_sensitive(False)

    # ---- updates ----------------------------------------------------------

    def _sync_updates(self):
        """Put the version row and the Install button in step with the disk."""
        version = installed_version(self._repo)
        pending = self._applied.update_available
        blockers = update_blockers(self._repo) if pending else []

        # Which line this is says what a version even means here, so it is said
        # plainly rather than left to be inferred from a version string that
        # happens to have an @ in it. Someone testing a branch should be able to
        # tell at a glance that they are not running a release, and how to stop.
        if is_test_build(self._repo):
            self._version_row.set_title("Test build")
            self._updates_group.set_description(
                "This checkout is on the branch %s, not the released line, so "
                "the check asks the git remote whether that branch has moved "
                "rather than which releases exist. To go back to releases, run "
                "git checkout main in the checkout once the branch has been "
                "merged." % current_branch(self._repo))
        else:
            self._version_row.set_title("Version")
            self._updates_group.set_description(
                "The check asks the git remote which release tags exist. "
                "It never installs anything on its own.")

        if version is None:
            self._version_row.set_subtitle(
                "This checkout is not on a release tag")
        elif pending:
            # On a test build both sides carry the same branch@ prefix, and the
            # branch is already named in the title and the description above. Two
            # more copies of it in one line is the same fact four times over, so
            # the one being offered is shown as the commit it is.
            offered = pending
            if version.rpartition("@")[0] and \
                    pending.startswith(version.rpartition("@")[0] + "@"):
                offered = pending.rpartition("@")[2]
            self._version_row.set_subtitle("%s — %s is available"
                                           % (version, offered))
        else:
            self._version_row.set_subtitle("%s — up to date" % version)

        self._check_button.set_sensitive(self._repo is not None)
        self._update_button_row.set_visible(bool(pending))

        if pending and blockers:
            # Shown rather than hidden. Someone who edited the checkout should
            # find out why the button is off, not wonder whether the update
            # notification was wrong.
            self._update_button_row.set_subtitle(blockers[0])
            self._update_button.set_sensitive(False)
        elif pending:
            self._update_button_row.set_subtitle(
                "Pulls %s and runs the full installer" % pending)
            self._update_button.set_sensitive(True)

    def _on_check_updates(self, _button):
        self._check_button.set_sensitive(False)
        self._check_button.set_label("Checking…")

        checker = os.path.join(os.path.expanduser("~/.local/bin"),
                               "aura-glass-update-check")
        if not os.path.exists(checker):
            checker = os.path.join(self._repo or "", "bin",
                                   "aura-glass-update-check")

        def done(proc, res):
            try:
                proc.wait_finish(res)
            except GLib.Error:
                pass
            self._check_button.set_label("Check now")
            # Re-read rather than trust an exit code: the checker's whole output
            # for the window is the state file it leaves behind.
            self._applied = Settings()
            self._sync_updates()
            self._check_button.set_sensitive(True)
            self._toasts.add_toast(Adw.Toast(
                title=("%s is available" % self._applied.update_available)
                if self._applied.update_available else "Up to date"))

        try:
            proc = Gio.Subprocess.new(
                ["bash", checker],
                Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE)
        except GLib.Error as exc:
            self._check_button.set_label("Check now")
            self._check_button.set_sensitive(True)
            self._toasts.add_toast(Adw.Toast(title="Could not check: %s"
                                             % exc.message))
            return
        proc.wait_async(None, done)

    def _on_install_update(self, _button):
        blockers = update_blockers(self._repo)
        if blockers:
            self._sync_updates()
            self._toasts.add_toast(Adw.Toast(title=blockers[0]))
            return

        # --ff-only so an update can never create a merge commit in someone's
        # checkout, and never rewrites anything: if the branch has diverged this
        # stops with git's own message rather than trying to be clever.
        #
        # The full installer, not --settings-only: a release can bump the
        # upstream theme ref, add an extension or add a stylesheet, and none of
        # those reach the desktop through the settings-only path.
        script = ("set -e\n"
                  "git -C %s pull --ff-only\n"
                  "bash %s --yes\n"
                  % (GLib.shell_quote(self._repo),
                     GLib.shell_quote(os.path.join(self._repo, "install.sh"))))

        def done(ok):
            if ok:
                self._applied = Settings()
                self._reload()
                self._sync_updates()
                self._toasts.add_toast(Adw.Toast(
                    title="Updated — log out and back in to finish"))

        ApplyDialog(
            self._repo, [], done,
            title="Updating",
            description=("Pulling the newest commit on %s, then running the "
                         "installer." % current_branch(self._repo))
                        if is_test_build(self._repo) else
                        "Pulling the new release, then running the installer.",
            argv=["bash", "-c", script],
        ).present(self)

    # ---- actions ----------------------------------------------------------

    def _banner_missing_repo(self):
        self._toasts.add_toast(Adw.Toast(
            title="The aura-glass checkout is gone — nothing to apply with",
            timeout=0))

    def _open_gnome_appearance(self, _button):
        # The panel that actually owns the accent. If gnome-control-center is not
        # there the launch simply fails, which is the same outcome as any other
        # missing app and needs no special case.
        Gio.AppInfo.launch_default_for_uri("gnome-control-center://background",
                                           None)

    def _on_apply(self, _button):
        args = self._current().flags_against(self._applied)
        if not args:
            return
        self._apply.set_sensitive(False)

        def done(ok):
            if ok:
                self._reload()
                self._toasts.add_toast(Adw.Toast(title="Settings applied"))
            else:
                self._apply.set_sensitive(True)

        ApplyDialog(self._repo, args, done).present(self)


class Application(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID,
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_activate(self):
        win = self.get_active_window()
        if win is None:
            # Before the first widget, not after: a provider added later would
            # restyle the preset cards in front of the user.
            install_css()
            win = Window(self, find_repo())
        win.present()


def main():
    if not os.path.isdir(CONF_DIR):
        print("aura-glass is not installed — %s does not exist.\n"
              "Run ./install.sh first." % CONF_DIR, file=sys.stderr)
        return 1
    return Application().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
