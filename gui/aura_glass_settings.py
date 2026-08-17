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
TRANSPARENCY_MARKS = [
    (82, "82%\ndeep"),
    (90, "90%\nbalanced"),
    (95, "95%\nsubtle"),
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
ICON_PACKS = [
    ("colloid", "Colloid", "Follows your accent colour"),
    ("reversal", "Reversal", "macOS-style circular icons, in your accent"),
    ("keep", "Keep current", "Leave the icon theme alone"),
]

CURSOR_PACKS = [
    ("adwaita", "Adwaita", "Ships with GNOME. Crisper at every size"),
    ("mactahoe", "MacTahoe", "The macOS pointer set"),
    ("keep", "Keep current", "Leave the cursor theme alone"),
]

BLUR_SCOPES = [
    ("gtk", "GTK / GNOME apps only", "Files, Settings, Terminal. Low cost"),
    ("all", "All apps", "Includes browsers and Electron. Heavy on the GPU"),
    ("none", "No window blur", "Windows stay translucent without a blur behind"),
]


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
        if self.radius not in [p[0] for p in RADIUS_PRESETS]:
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
        if self.scope not in [s[0] for s in BLUR_SCOPES]:
            self.scope = "gtk"

        self.popup_blur = read_memo("popup-blur", "1") != "0"

        # Which windows the applications component treats. Blur My Shell reads
        # one or the other depending on enable-all, which is the same choice
        # `scope` makes — so the allow list belongs to gtk mode and the block
        # list to all mode. apply_app_blur writes both memos every run, so an
        # empty one here means an empty list rather than a missing file.
        self.allow = read_memo_lines("app-blur-allow")
        self.block = read_memo_lines("app-blur-block")

        # Reversal is remembered as reversal-<colour>; the row offers the family
        # and install.sh pairs it with the accent, so only the family is kept
        # here. There is no memo for "keep" — --no-icons is a choice not to have
        # touched anything, which leaves nothing behind to read.
        icons = read_memo("icon-pack", "colloid") or "colloid"
        self.icons = "reversal" if icons.startswith("reversal") else "colloid"
        self.cursors = read_memo("cursor-pack", "adwaita") or "adwaita"
        if self.cursors not in [c[0] for c in CURSOR_PACKS]:
            self.cursors = "adwaita"

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

        # The family, bare. accent_to_reversal in lib/steps-assets.sh turns it
        # into a colour Reversal actually ships, which is not the accent's own
        # name for three of the nine — there is no teal, yellow or slate. Naming
        # the colour here would mean keeping a second copy of that mapping, and
        # the copy that used to exist in the wizard was wrong.
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
        if self.radius != other.radius:
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

        # Only the list the chosen mode actually consults. Sending the other one
        # too would be harmless — apply_app_blur writes both keys either way —
        # but it would put a list the user never saw into an argument line they
        # might read, which is the sort of thing that makes a GUI untrustworthy.
        if self.allow != other.allow and self.scope == "gtk":
            args += ["--app-blur-allow", ",".join(self.allow)]
        if self.block != other.block and self.scope == "all":
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
        add_button = Gtk.Button(icon_name="list-add-symbolic",
                                valign=Gtk.Align.CENTER,
                                tooltip_text="Add this pattern")
        add_button.add_css_class("flat")
        add_button.connect("clicked", self._on_entry)
        self._entry.add_suffix(add_button)

        manual = Adw.PreferencesGroup(
            description="Matched against a window's class, and * is a wildcard "
                        "— *chrome* covers every spelling Chrome uses. Commas "
                        "are not allowed, they separate entries.")
        manual.add(self._entry)

        self._search = Gtk.SearchEntry(placeholder_text="Search installed apps")
        self._search.connect("search-changed", lambda _e: self._refill())

        self._list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        self._list.add_css_class("boxed-list")
        self._list.set_margin_start(12)
        self._list.set_margin_end(12)
        self._list.set_margin_bottom(12)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        manual.set_margin_top(12)
        manual.set_margin_start(12)
        manual.set_margin_end(12)
        box.append(manual)
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

    def _on_entry(self, *_a):
        text = self._entry.get_text().strip().replace(",", "")
        if not text or text in self._existing:
            return
        self._on_add(text)
        self.close()


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
                         default_width=580, default_height=720)
        self._repo = repo
        self._applied = Settings()   # what is on disk
        self._loading = True

        self._apply = Gtk.Button(label="Apply", sensitive=False)
        self._apply.add_css_class("suggested-action")
        self._apply.connect("clicked", self._on_apply)

        header = Adw.HeaderBar()
        header.pack_end(self._apply)

        self._toasts = Adw.ToastOverlay(child=self._build_page())
        view = Adw.ToolbarView(content=self._toasts)
        view.add_top_bar(header)
        self.set_content(view)

        self._loading = False
        if repo is None:
            self._apply.set_sensitive(False)
            self._banner_missing_repo()

    # ---- construction -----------------------------------------------------

    def _combo(self, title, subtitle, options, current, key):
        """A ComboRow over (id, title, subtitle) options.

        The ids are kept beside the row rather than derived from the position, so
        reordering a list here cannot silently change which flag a row sends.
        """
        model = Gtk.StringList()
        for _, label, _sub in options:
            model.append(label)
        row = Adw.ComboRow(title=title, subtitle=subtitle, model=model)
        ids = [o[0] for o in options]
        row.set_selected(ids.index(current) if current in ids else 0)
        row._ids = ids
        row._subs = [o[2] for o in options]
        row.connect("notify::selected", self._on_changed, key)
        self._sync_subtitle(row)
        return row

    def _sync_subtitle(self, row):
        i = row.get_selected()
        if 0 <= i < len(row._subs):
            row.set_subtitle(row._subs[i])

    def _build_page(self):
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

        self._radius_row = self._combo(
            "Corner rounding", "", RADIUS_PRESETS, self._applied.radius, "radius")
        look.add(self._radius_row)
        page.add(look)

        # Separate group, because these two are the only settings in the window
        # that can reach the network. Switching to a pack already on disk is
        # instant — install_icons and install_cursors both skip when the theme is
        # there — and a pack that is not gets fetched, which the Apply log shows.
        packs = Adw.PreferencesGroup(
            title="Icons and pointer",
            description="A pack you have already installed applies instantly. "
                        "One you have not is downloaded first, so Apply can take "
                        "a minute and needs the network.")
        self._icons_row = self._combo(
            "Icon pack", "", ICON_PACKS, self._applied.icons, "icons")
        packs.add(self._icons_row)
        self._cursors_row = self._combo(
            "Pointer", "", CURSOR_PACKS, self._applied.cursors, "cursors")
        packs.add(self._cursors_row)
        page.add(packs)

        glass = Adw.PreferencesGroup(
            title="Glass",
            description="Blur costs GPU time. Solid mode turns all of it off.")
        self._blur_row = Adw.SwitchRow(
            title="Frosted glass",
            subtitle="Off means solid mode: opaque surfaces, no blur anywhere",
            active=self._applied.blur)
        self._blur_row.connect("notify::active", self._on_changed, "blur")
        glass.add(self._blur_row)

        self._scope_row = self._combo(
            "Blur behind windows", "", BLUR_SCOPES, self._applied.scope, "scope")
        glass.add(self._scope_row)

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

        self._transparency_scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, TRANSPARENCY_MIN, TRANSPARENCY_MAX, 1)
        self._transparency_scale.set_hexpand(True)
        self._transparency_scale.set_draw_value(True)
        self._transparency_scale.set_value_pos(Gtk.PositionType.LEFT)
        for at, label in TRANSPARENCY_MARKS:
            self._transparency_scale.add_mark(at, Gtk.PositionType.BOTTOM, label)
        # Percent, not the 0-255 actor opacity install.sh also understands: the
        # window is what the user is looking at, and 90% opaque is a thing you
        # can picture in a way that 230 is not.
        self._transparency_scale.set_format_value_func(
            lambda _s, value: "%d%%" % round(value))
        self._transparency_scale.set_value(
            level_to_percent(self._applied.transparency))
        self._transparency_scale.connect("value-changed", self._on_scale_changed)

        self._transparency_row = Adw.ActionRow(
            title="Opacity",
            subtitle="Lower is more see-through. Below 70% the text stops "
                     "holding up over a bright wallpaper, so that is the floor")
        self._transparency_row.add_suffix(self._transparency_scale)
        self._transparency_row.set_activatable_widget(self._transparency_scale)
        glass.add(self._transparency_row)

        self._popup_row = Adw.SwitchRow(
            title="Blur behind menus and the top bar",
            subtitle="Popups, Quick Settings and the panel",
            active=self._applied.popup_blur)
        self._popup_row.connect("notify::active", self._on_changed, "popup_blur")
        glass.add(self._popup_row)
        page.add(glass)

        # The per-app list. Which one is shown follows the mode above, because
        # that is how Blur My Shell reads them: enable-all off consults the allow
        # list, on consults the block list. Showing both at once would imply they
        # combine, and they never do.
        self._allow = list(self._applied.allow)
        self._block = list(self._applied.block)

        self._apps_add = Gtk.Button(icon_name="list-add-symbolic",
                                    valign=Gtk.Align.CENTER,
                                    tooltip_text="Add an app")
        self._apps_add.add_css_class("flat")
        self._apps_add.connect("clicked", self._on_add_app)

        self._apps_group = Adw.PreferencesGroup()
        self._apps_group.set_header_suffix(self._apps_add)
        page.add(self._apps_group)
        self._rebuild_app_list()

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

        self._sync_sensitivity()
        return page

    # ---- state ------------------------------------------------------------

    # ---- the per-app list -------------------------------------------------

    def _active_list(self):
        """The list the chosen mode consults, and the label for it."""
        if self._scope_row._ids[self._scope_row.get_selected()] == "all":
            return self._block, "block"
        return self._allow, "allow"

    def _rebuild_app_list(self):
        """Redraw the rows. Cheap, and the list is short by nature."""
        entries, which = self._active_list()

        if which == "block":
            self._apps_group.set_title("Apps never blurred")
            self._apps_group.set_description(
                "Everything else gets the blur and the window opacity. These are "
                "the exceptions — browsers and Electron apps redraw constantly, "
                "so a blur behind them is rebuilt constantly.")
        else:
            self._apps_group.set_title("Apps to blur")
            self._apps_group.set_description(
                "Only these get the blur and the window opacity. The same list "
                "governs both — Blur My Shell applies them together, so an app "
                "cannot be translucent without also being blurred.")

        for row in getattr(self, "_app_rows", []):
            self._apps_group.remove(row)
        self._app_rows = []

        if not entries:
            row = Adw.ActionRow(
                title="Nothing listed",
                subtitle=("No app will be blurred" if which == "allow"
                          else "No app is excluded"))
            row.set_sensitive(False)
            self._apps_group.add(row)
            self._app_rows.append(row)

        for pattern in entries:
            row = Adw.ActionRow(title=pattern)
            if "*" in pattern:
                row.set_subtitle("Pattern — matches any window class containing it")
            remove = Gtk.Button(icon_name="user-trash-symbolic",
                                valign=Gtk.Align.CENTER,
                                tooltip_text="Remove")
            remove.add_css_class("flat")
            remove.connect("clicked", self._on_remove_app, pattern)
            row.add_suffix(remove)
            self._apps_group.add(row)
            self._app_rows.append(row)

        on = (self._blur_row.get_active()
              and self._scope_row._ids[self._scope_row.get_selected()] != "none")
        self._apps_group.set_sensitive(on)
        self._apps_add.set_sensitive(on)

    def _on_add_app(self, _button):
        entries, _ = self._active_list()

        def add(pattern):
            entries.append(pattern)
            self._rebuild_app_list()
            self._mark_dirty()

        AppPickerDialog(entries, add).present(self)

    def _on_remove_app(self, _button, pattern):
        entries, _ = self._active_list()
        if pattern in entries:
            entries.remove(pattern)
            self._rebuild_app_list()
            self._mark_dirty()

    # ---- state ------------------------------------------------------------

    def _current(self):
        """What the widgets are asking for."""
        s = Settings.__new__(Settings)
        s.accent = self._accent_row._ids[self._accent_row.get_selected()]
        s.radius = self._radius_row._ids[self._radius_row.get_selected()]
        s.blur = self._blur_row.get_active()
        s.scope = self._scope_row._ids[self._scope_row.get_selected()]
        s.transparency = (
            percent_to_level(round(self._transparency_scale.get_value()))
            if self._transparency_on.get_active() else "0")
        s.popup_blur = self._popup_row.get_active()
        s.allow = list(self._allow)
        s.block = list(self._block)
        s.icons = self._icons_row._ids[self._icons_row.get_selected()]
        s.cursors = self._cursors_row._ids[self._cursors_row.get_selected()]
        s.update_check = self._update_check_row.get_active()
        # Not settings, so they never differ and never produce a flag. Carried so
        # flags_against sees a complete object either way.
        s.update_available = self._applied.update_available
        return s

    def _sync_sensitivity(self):
        """Solid mode is the absence of all of it, so the blur rows go dim."""
        on = self._blur_row.get_active()
        for row in (self._scope_row, self._transparency_on, self._popup_row):
            row.set_sensitive(on)
        # The bar needs both: there is nothing to set a level on in solid mode,
        # and nothing to set it on when translucency itself is off.
        self._transparency_row.set_sensitive(
            on and self._transparency_on.get_active())

    def _mark_dirty(self):
        dirty = bool(self._current().flags_against(self._applied))
        self._apply.set_sensitive(dirty and self._repo is not None)

    def _on_scale_changed(self, _scale):
        if self._loading:
            return
        self._mark_dirty()

    def _on_changed(self, row, _param, key):
        if self._loading:
            return
        if isinstance(row, Adw.ComboRow):
            self._sync_subtitle(row)
        if key in ("blur", "transparency"):
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
        self._radius_row.set_selected(
            self._radius_row._ids.index(self._applied.radius))
        self._blur_row.set_active(self._applied.blur)
        if self._applied.scope in self._scope_row._ids:
            self._scope_row.set_selected(
                self._scope_row._ids.index(self._applied.scope))
        self._transparency_on.set_active(self._applied.transparency != "0")
        # Only when it is on: off is stored as a flat "0", and moving the bar to
        # 70% because of that would lose the level to come back to.
        if self._applied.transparency != "0":
            self._transparency_scale.set_value(
                level_to_percent(self._applied.transparency))
        self._popup_row.set_active(self._applied.popup_blur)
        self._allow = list(self._applied.allow)
        self._block = list(self._applied.block)
        self._icons_row.set_selected(
            self._icons_row._ids.index(self._applied.icons))
        self._cursors_row.set_selected(
            self._cursors_row._ids.index(self._applied.cursors))
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
