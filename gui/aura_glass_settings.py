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

GDM is deliberately absent. It needs root, and a window with no way to ask for a
password has no business starting something that will silently decline.
"""
import os
import shutil
import subprocess
import sys

import gi

gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")
from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402

APP_ID = "io.github.DevWebeloper.AuraGlassSettings"

CONF_DIR = os.path.join(GLib.get_user_config_dir(), "aura-glass")

# Accents in the order install.sh lists them, with the default first so the row
# reads as "purple, and eight others" rather than as an alphabetical list.
ACCENTS = ["purple", "blue", "teal", "green", "yellow", "orange", "red", "pink",
           "slate"]

# (id, title, subtitle). The radius rows describe what moves rather than naming
# pixel values: the seven numbers per preset are not a thing to read in a
# subtitle, and tokens/tokens.sh is where they belong.
RADIUS_PRESETS = [
    ("sharp", "Sharp", "Barely rounded — 10px windows, 8px menus"),
    ("default", "Default", "What the theme ships — 30px windows, 26px menus"),
    ("rounded", "Rounded", "Softer than default — 38px windows, 32px menus"),
    ("pill", "Pill", "As round as the blur behind it allows — 46px windows"),
]

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
    ("window", "Windows", 10, 46,
     "Every app window, and the blur behind it"),
    ("menu", "Menus", 8, 40,
     "Right-click menus and app menus"),
    ("quick_settings", "Quick Settings", 10, 52,
     "The system menu and the calendar. Larger than a menu by design — Blur My "
     "Shell groups these two together"),
    ("notification", "Notifications", 6, 34,
     "Banners as they arrive, and the stack in the calendar"),
    ("dialog", "Dialogs", 6, 34,
     "Log out, restart, power off"),
    ("popup", "Other popups", 6, 34,
     "Anything the more specific ones above do not claim"),
    ("osd", "Volume and brightness", 4, 20,
     "The pill that appears on a volume key. Its ceiling is lower than the "
     "others — past it the corners meet and the pill turns into an ellipse"),
]

RADIUS_PRESET_VALUES = {
    "sharp":   (10, 8, 10, 6, 6, 6, 4),
    "default": (30, 26, 33, 20, 20, 20, 12),
    "rounded": (38, 32, 40, 26, 26, 26, 16),
    "pill":    (46, 40, 52, 34, 34, 34, 18),
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
    ("system", "System", "emblem-system-symbolic", "_build_system_page"),
    ("updates", "Updates", "software-update-available-symbolic",
     "_build_updates_page"),
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


def read_memo_lines(name):
    """A list memo — one wm_class pattern per line, blanks dropped."""
    raw = read_memo(name)
    return [line.strip() for line in raw.splitlines() if line.strip()]


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


def installed_version(repo):
    """The release this checkout sits on, or None if it is not on one."""
    if not repo:
        return None
    return git_out(repo, "describe", "--tags", "--abbrev=0")


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
        upstream = git_out(repo, "rev-parse", "--abbrev-ref",
                           "--symbolic-full-name", "@{upstream}")
        if upstream is None:
            reasons.append("The branch %s is not tracking a remote branch."
                           % branch)
        # A feature branch is someone working on the theme, not someone running
        # it. Pulling would update the wrong line and quietly leave them there.
        elif branch not in ("main", "master"):
            reasons.append("The checkout is on the branch %s rather than main. "
                           "Updating would pull that branch instead of the "
                           "released one." % branch)
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
        if self.radius not in [p[0] for p in RADIUS_PRESETS] + ["custom"]:
            self.radius = "default"

        # Only meaningful while radius is "custom", but read either way so the
        # seven spin rows have somewhere to start from when someone moves one.
        self.radius_custom = parse_radius_custom(read_memo("radius-custom"))
        if self.radius == "custom" and self.radius_custom is None:
            # A custom preset with no values behind it is not a state install.sh
            # would accept, so it is not one to carry around either.
            self.radius = "default"

        # Solid mode has no memo of its own. install_css encodes it by whether
        # the solid sheet is installed at all — the flag is not remembered on
        # purpose (see apply_popup_blur), so the installed file is the only
        # honest answer.
        self.blur = not os.path.exists(
            os.path.join(CONF_DIR, "shell-80-solid.css"))

        self.transparency = read_memo("app-transparency", "0") or "0"
        self.scope = read_memo("app-blur-scope", "gtk") or "gtk"
        if read_memo("window-blur", "1") == "0":
            self.scope = "none"
        if self.scope not in BLUR_SCOPES:
            self.scope = "gtk"

        self.popup_blur = read_memo("popup-blur", "1") != "0"

        # Which windows the applications component treats. Blur My Shell reads
        # one or the other depending on enable-all, which is the same choice
        # `scope` makes — so the allow list belongs to gtk mode and the block
        # list to all mode. apply_app_blur writes both memos every run, so an
        # empty one here means an empty list rather than a missing file.
        self.allow = read_memo_lines("app-blur-allow")
        self.block = read_memo_lines("app-blur-block")

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

        self.update_check = read_memo("update-check", "1") != "0"
        # Written by bin/aura-glass-update-check, so the window can say what is
        # waiting without going to the network itself. None means up to date.
        self.update_available = read_memo("update-available") or None

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

        if self.blur != other.blur:
            args.append("--blur" if self.blur else "--no-blur")

        # --no-blur already implies no window blur, no popup blur and opaque
        # windows, and install.sh rejects --no-blur alongside --window-blur
        # outright. So in solid mode the blur flags are not merely redundant,
        # they are a contradiction it would refuse to run.
        if not self.blur:
            return args

        if self.scope != other.scope or self.blur != other.blur:
            args.append({"gtk": "--gtk-apps-blur",
                         "all": "--all-apps-blur",
                         "none": "--no-window-blur"}[self.scope])

        # --no-window-blur moves transparency to 0.95 unless transparency is
        # given explicitly, so it goes after the scope flag and always states
        # the level the window is actually showing.
        if (self.transparency != other.transparency
                or self.scope != other.scope
                or self.blur != other.blur):
            if self.transparency == "0":
                args.append("--no-app-transparency")
            else:
                args += ["--app-transparency", self.transparency]

        if self.popup_blur != other.popup_blur or self.blur != other.blur:
            args.append("--popup-blur" if self.popup_blur else "--no-popup-blur")

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


class AppPickerDialog(Adw.Dialog):
    """Pick an installed app, or type a pattern.

    Two ways in, because neither covers the other. The list handles the common
    case without anyone having to know what a wm_class is; the entry handles
    wildcards, and apps that are not installed as desktop entries at all — which
    is most of the ones the shipped block list names.
    """

    def __init__(self, existing, on_add):
        super().__init__(title="Add an app", content_width=460,
                         content_height=520)
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
        self.set_child(view)

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
            row = Adw.ActionRow(title=name, subtitle=wm)
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


class AppListDialog(Adw.Dialog):
    """One of the two per-app lists, on its own.

    They used to share a single group in the main window that swapped which
    list it showed as the blur mode changed. That made the mode look like it
    owned the lists: switching modes read as the other list having been
    emptied, when in fact both are separate memos that survive every switch and
    are editable whatever the mode is. A window each says that instead.

    The list is mutated in place — it is the same object the main window keeps
    — and on_change is called after every edit so the summary behind this
    window and the Apply button stay in step with it.
    """

    def __init__(self, title, description, entries, on_change, active_note):
        super().__init__(title=title, content_width=480, content_height=560)
        self._entries = entries
        self._on_change = on_change

        self._group = Adw.PreferencesGroup(description=description)
        add = Gtk.Button(icon_name="list-add-symbolic",
                         valign=Gtk.Align.CENTER, tooltip_text="Add an app")
        add.add_css_class("flat")
        add.connect("clicked", self._on_add)
        self._group.set_header_suffix(add)
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

        scroller = Gtk.ScrolledWindow(child=box, vexpand=True)
        view = Adw.ToolbarView(content=scroller)
        view.add_top_bar(Adw.HeaderBar())
        self.set_child(view)

        self._rows = []
        self._rebuild()

    def _rebuild(self):
        for row in self._rows:
            self._group.remove(row)
        self._rows = []

        if not self._entries:
            row = Adw.ActionRow(title="Nothing listed",
                                subtitle="Use + to add an app or a pattern")
            row.set_sensitive(False)
            self._group.add(row)
            self._rows.append(row)

        for pattern in self._entries:
            row = Adw.ActionRow(title=pattern,
                                subtitle=describe_pattern(pattern))
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

        AppPickerDialog(self._entries, add).present(self)

    def _on_remove(self, _button, pattern):
        if pattern in self._entries:
            self._entries.remove(pattern)
            self._rebuild()
            self._on_change()


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
            description="The four that have been through a screenshot loop. "
                        "Each sets all seven surfaces below at once — move any "
                        "one of them afterwards and the rounding becomes yours "
                        "rather than one of these.")
        row = Adw.ActionRow(title="Presets")
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6,
                      valign=Gtk.Align.CENTER)
        self._radius_preset_buttons = {}
        for ident, title, subtitle in RADIUS_PRESETS:
            button = Gtk.Button(label=title, tooltip_text=subtitle)
            button.connect("clicked", self._on_radius_preset, ident)
            box.append(button)
            self._radius_preset_buttons[ident] = button
        row.add_suffix(box)
        presets.add(row)

        self._radius_state = Adw.ActionRow(title="Currently")
        presets.add(self._radius_state)
        page.add(presets)

        # One control per surface rather than one for all seven. The presets
        # stay because these numbers are not proportional to each other and a
        # single multiplier over them produces combinations nobody looked at —
        # but "pick one of four" was never the only alternative to that.
        surfaces = Adw.PreferencesGroup(
            title="Each surface",
            description="Pixels. Every range here is one the presets already "
                        "cover, so anything you can set is something that has "
                        "been seen on a screen.")
        self._radius_rows = {}
        for ident, title, low, high, subtitle in RADIUS_SURFACES:
            spin = Adw.SpinRow.new_with_range(low, high, 1)
            spin.set_title(title)
            spin.set_subtitle(subtitle)
            spin.connect("notify::value", self._on_changed, "radius")
            surfaces.add(spin)
            self._radius_rows[ident] = spin
        page.add(surfaces)

        self._load_radius(self._applied)
        return page

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
        self._radius_state.set_subtitle(
            titles[name] if name in titles
            else "Your own — " + ", ".join(
                "%s %d" % (s[1].lower(), v)
                for s, v in zip(RADIUS_SURFACES, self._radius_values())))
        for ident, button in self._radius_preset_buttons.items():
            # The active preset's button reads as pressed rather than going
            # insensitive: it is still the way back after moving a row.
            if ident == name:
                button.add_css_class("suggested-action")
            else:
                button.remove_css_class("suggested-action")

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
        page = Adw.PreferencesPage()

        glass = Adw.PreferencesGroup(
            title="Glass",
            description="Blur costs GPU time. Solid mode turns all of it off.")
        self._blur_row = Adw.SwitchRow(
            title="Frosted glass",
            subtitle="Off means solid mode: opaque surfaces, no blur anywhere",
            active=self._applied.blur)
        self._blur_row.connect("notify::active", self._on_changed, "blur")
        glass.add(self._blur_row)

        # Two switches, not the dropdown this was. They are two settings in
        # install.sh — WANT_WINDOW_BLUR and APP_BLUR_SCOPE — and the dropdown
        # was the only thing that ever made them one question. Asking for the
        # blur to reach every window is now a switch you can find, rather than
        # the middle entry of a list called something else.
        self._window_blur_row = Adw.SwitchRow(
            title="Blur behind app windows",
            subtitle="Off leaves windows translucent with no blur behind them",
            active=self._applied.scope != "none")
        self._window_blur_row.connect("notify::active", self._on_changed,
                                      "scope")
        glass.add(self._window_blur_row)

        self._blur_all_row = Adw.SwitchRow(
            title="Blur behind all application windows",
            subtitle="On covers browsers and Electron apps too, and is heavy on "
                     "the GPU. Off keeps it to GTK and GNOME apps",
            active=self._applied.scope == "all")
        self._blur_all_row.connect("notify::active", self._on_changed, "scope")
        glass.add(self._blur_all_row)

        # Off is its own switch rather than the bottom of the bar. They are not
        # the same thing: 100% leaves the transparency sheet installed and fully
        # opaque, while off removes it, and install_transparency_css treats those
        # differently. A single control would have to pretend otherwise.
        self._transparency_on = Adw.SwitchRow(
            title="Translucent app windows",
            subtitle="Let the blur and the wallpaper through GTK app windows",
            active=self._applied.transparency != "0")
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
        self._transparency_scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, TRANSPARENCY_MIN, TRANSPARENCY_MAX, 1)
        self._transparency_scale.set_hexpand(True)
        self._transparency_scale.set_draw_value(False)
        for at, label in TRANSPARENCY_MARKS:
            self._transparency_scale.add_mark(at, Gtk.PositionType.BOTTOM, label)
        self._transparency_scale.set_value(
            level_to_percent(self._applied.transparency))
        self._transparency_scale.connect("value-changed", self._on_scale_changed)

        # Percent, not the 0-255 actor opacity install.sh also understands: the
        # window is what the user is looking at, and 90% opaque is a thing you
        # can picture in a way that 230 is not.
        self._transparency_value = Gtk.Label(valign=Gtk.Align.CENTER)
        self._transparency_value.add_css_class("numeric")
        self._transparency_value.add_css_class("dim-label")
        self._sync_transparency_value()

        self._transparency_row = Adw.ActionRow(
            title="Opacity",
            subtitle="Lower is more see-through. Below 70% the text stops "
                     "holding up over a bright wallpaper, so that is the floor")
        self._transparency_row.add_suffix(self._transparency_value)
        glass.add(self._transparency_row)

        self._transparency_bar = Gtk.Box(margin_start=12, margin_end=12,
                                         margin_top=4, margin_bottom=4)
        self._transparency_bar.append(self._transparency_scale)
        glass.add(self._transparency_bar)

        self._popup_row = Adw.SwitchRow(
            title="Blur behind menus and the top bar",
            subtitle="Popups, Quick Settings and the panel",
            active=self._applied.popup_blur)
        self._popup_row.connect("notify::active", self._on_changed, "popup_blur")
        glass.add(self._popup_row)
        page.add(glass)
        return page

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
        page.add(group)

        self._sync_system()
        self._check_deps()
        return page

    def _sync_system(self):
        """Read the stamp files these buttons act on."""
        installed = os.path.exists(os.path.join(CONF_DIR, "rounded-blur"))
        self._rounded_row.set_subtitle(
            "Installed. Reinstall if a mutter update stopped it loading"
            if installed else
            "Lets the blur behind popups follow their rounded corners instead "
            "of falling back to a static one")
        self._rounded_button.set_label("Reinstall" if installed else "Install")
        for widget in (self._rounded_button,):
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
        # trace of the pack currently on screen would look broken. No Remove
        # button: they are the package manager's, and rm -rf under /usr on
        # someone's behalf is exactly what uninstall.sh refuses to do for
        # gnome-rounded-blur, for the same reason.
        self._packs_system = Adw.PreferencesGroup(
            title="Installed system-wide",
            description="Owned by your distribution's package manager, so "
                        "remove them with it rather than from here.")
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
                row = Adw.ActionRow(title=title)
                row._paths = entry["paths"]
                row._in_use = entry["in_use"]
                row._sized = False
                row.set_subtitle("In use" if entry["in_use"] else "Not in use")

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

        # Sizes come after the rows are up. Walking a full icon theme is tens of
        # thousands of stat calls, and doing it before the page exists would
        # make opening the window wait on all of them.
        GLib.idle_add(self._size_next_pack)

    def _size_next_pack(self):
        for _group, row in self._pack_rows:
            if getattr(row, "_sized", True):
                continue
            row._sized = True
            total = sum(dir_size(p) for p in row._paths)
            parts = ["In use" if row._in_use else "Not in use",
                     human_size(total)]
            if len(row._paths) > 1:
                parts.append("%d variants" % len(row._paths))
            row.set_subtitle(" — ".join(parts[:2]) + (
                " (%s)" % parts[2] if len(parts) > 2 else ""))
            return True     # one per idle turn, so the window stays responsive
        return False

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
        group = Adw.PreferencesGroup(title=title, description=description)
        row = Adw.ActionRow(title="Listed apps")
        row._badge = Gtk.Label(valign=Gtk.Align.CENTER)
        row._badge.add_css_class("dim-label")
        row._badge.add_css_class("caption")
        row.add_suffix(row._badge)
        edit = Gtk.Button(label="Edit", valign=Gtk.Align.CENTER)
        edit.connect("clicked", self._on_edit_list, which)
        row.add_suffix(edit)
        row.set_activatable_widget(edit)
        group.add(row)
        page.add(group)
        return row

    def _build_updates_page(self):
        page = Adw.PreferencesPage()

        updates = Adw.PreferencesGroup(
            title="Updates",
            description="The check asks the git remote which release tags exist. "
                        "It never installs anything on its own.")

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

        cli = Adw.PreferencesGroup(
            title="Command line only",
            description="The GDM login screen theme needs root, and this window "
                        "has no way to ask for a password — a run started here "
                        "would decline it silently. Use ./install.sh --gdm.")
        page.add(cli)
        return page

    # ---- state ------------------------------------------------------------

    # ---- the per-app list -------------------------------------------------

    def _scope(self):
        """The three-way install.sh value, from the two switches that make it."""
        if not self._window_blur_row.get_active():
            return "none"
        return "all" if self._blur_all_row.get_active() else "gtk"

    def _list_is_consulted(self, which):
        """Whether the blur mode as set right now reads this list."""
        scope = self._scope()
        if not self._blur_row.get_active() or scope == "none":
            return False
        return (scope == "all") == (which == "block")

    def _rebuild_app_list(self):
        """Put both summaries back in step with the two lists."""
        for which, row in (("allow", self._allow_row),
                           ("block", self._block_row)):
            entries = self._allow if which == "allow" else self._block
            _title, _desc, empty = self.LIST_TEXT[which]

            if entries:
                shown = ", ".join(entries[:3])
                if len(entries) > 3:
                    shown += " and %d more" % (len(entries) - 3)
            else:
                shown = empty
            row.set_subtitle(shown)

            # A mode switch changes the badge and nothing else: dimming the idle
            # list would put back the "your list is gone" reading the two groups
            # exist to fix. Solid mode is the one case that does dim them, and
            # it is not the same case — there is no blur at all to list apps
            # for, and flags_against sends nothing past --no-blur, so an edit
            # made there would be dropped rather than stored.
            if not self._blur_row.get_active():
                row.set_sensitive(False)
                row._badge.set_label("Solid mode — nothing is blurred")
                continue
            row.set_sensitive(True)
            row._badge.set_label("In use" if self._list_is_consulted(which)
                                 else "Not in use right now")

    def _on_edit_list(self, _button, which):
        title, description, _empty = self.LIST_TEXT[which]
        entries = self._allow if which == "allow" else self._block

        def changed():
            self._rebuild_app_list()
            self._mark_dirty()

        note = None
        if not self._list_is_consulted(which):
            other = "every app is blurred" if which == "allow" \
                else "the blur is limited to GTK and GNOME apps"
            note = ("Kept, but not consulted while %s. Edits are saved either "
                    "way." % other)

        AppListDialog(title, description, entries, changed, note).present(self)

    # ---- state ------------------------------------------------------------

    def _current(self):
        """What the widgets are asking for."""
        s = Settings.__new__(Settings)
        s.accent = self._accent_row._ids[self._accent_row.get_selected()]
        s.radius = self._radius_preset_name()
        s.radius_custom = self._radius_values()
        s.blur = self._blur_row.get_active()
        s.scope = self._scope()
        s.transparency = (
            percent_to_level(round(self._transparency_scale.get_value()))
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
        s.update_check = self._update_check_row.get_active()
        # Not settings, so they never differ and never produce a flag. Carried so
        # flags_against sees a complete object either way.
        s.update_available = self._applied.update_available
        return s

    def _sync_sensitivity(self):
        """Solid mode is the absence of all of it, so the blur rows go dim."""
        on = self._blur_row.get_active()
        for row in (self._window_blur_row, self._transparency_on,
                    self._popup_row):
            row.set_sensitive(on)
        # Nothing to widen when there is no window blur to widen.
        self._blur_all_row.set_sensitive(
            on and self._window_blur_row.get_active())
        # The bar needs both: there is nothing to set a level on in solid mode,
        # and nothing to set it on when translucency itself is off.
        live = on and self._transparency_on.get_active()
        self._transparency_row.set_sensitive(live)
        self._transparency_bar.set_sensitive(live)

        # Neither "keep" nor "original" is a pack with colours to pick from.
        self._icon_color_row.set_sensitive(
            self._icons_row._ids[self._icons_row.get_selected()]
            not in ("keep", "original"))

    def _mark_dirty(self):
        dirty = bool(self._current().flags_against(self._applied))
        self._apply.set_sensitive(dirty and self._repo is not None)

    def _sync_transparency_value(self):
        self._transparency_value.set_label(
            "%d%%" % round(self._transparency_scale.get_value()))

    def _on_scale_changed(self, _scale):
        # Outside the loading guard: the readout has to follow the bar even when
        # the bar was moved by _reload rather than by a hand.
        self._sync_transparency_value()
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

        if key in ("blur", "transparency", "scope", "icons"):
            self._sync_sensitivity()
        # The mode decides which list is consulted, so it decides which is shown.
        if key in ("scope", "blur"):
            self._rebuild_app_list()
        self._mark_dirty()

    def _reload(self):
        """Re-read the disk and put the widgets back in step with it."""
        self._applied = Settings()
        self._loading = True
        self._accent_row.set_selected(
            self._accent_row._ids.index(self._applied.accent))
        self._load_radius(self._applied)
        self._blur_row.set_active(self._applied.blur)
        self._window_blur_row.set_active(self._applied.scope != "none")
        self._blur_all_row.set_active(self._applied.scope == "all")
        self._transparency_on.set_active(self._applied.transparency != "0")
        # Only when it is on: off is stored as a flat "0", and moving the bar to
        # 70% because of that would lose the level to come back to.
        if self._applied.transparency != "0":
            self._transparency_scale.set_value(
                level_to_percent(self._applied.transparency))
        self._popup_row.set_active(self._applied.popup_blur)
        self._allow = list(self._applied.allow)
        self._block = list(self._applied.block)
        family, color = split_icons(self._applied.icons)
        self._icons_row.set_selected(self._icons_row._ids.index(family))
        self._refill_combo(self._icon_color_row, ICON_COLORS[family], color)
        self._cursors_row.set_selected(
            self._cursors_row._ids.index(self._applied.cursors))
        self._window_buttons_row.set_selected(
            self._window_buttons_row._ids.index(self._applied.window_buttons))
        self._update_check_row.set_active(self._applied.update_check)
        self._loading = False
        self._rebuild_app_list()
        self._sync_sensitivity()
        self._apply.set_sensitive(False)

    # ---- updates ----------------------------------------------------------

    def _sync_updates(self):
        """Put the version row and the Install button in step with the disk."""
        version = installed_version(self._repo)
        pending = self._applied.update_available
        blockers = update_blockers(self._repo) if pending else []

        if version is None:
            self._version_row.set_subtitle(
                "This checkout is not on a release tag")
        elif pending:
            self._version_row.set_subtitle("%s — %s is available"
                                           % (version, pending))
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
            description="Pulling the new release, then running the installer.",
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
