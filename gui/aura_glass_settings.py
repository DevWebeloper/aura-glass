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
dconf preset, the CSS and the gsettings, and skips everything that fetches
(theme, extensions, icon and cursor packs) or wants root (the rounded-blur
library, GDM). So Apply needs no network, no password, and no terminal to answer
a prompt in.

What is deliberately NOT here:

  Accent is here, but as one of nine names install.sh understands rather than a
  colour picker, because it is not this project's setting to own — the shell CSS
  reads -st-accent-color and the GTK CSS reads @accent_bg_color, so
  Settings -> Appearance already recolours the desktop live. The row exists to
  keep the remembered value in step; the button beside it goes to the real thing.

  Icons, cursors and GDM. Each one downloads a pack or needs root, which is the
  line --settings-only draws. They stay CLI flags.
"""
import os
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

# install.sh normalises --app-transparency into exactly these three buckets, plus
# 0 for off. A memo holding anything else is shown as Custom and left alone.
TRANSPARENCY = [
    ("0", "Off", "Opaque app windows"),
    ("0.82", "82% — deep glass", "Most transparent, softest text"),
    ("0.90", "90% — balanced", "The default when blur is on"),
    ("0.95", "95% — subtle", "Crispest text, least see-through"),
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

        return args


class ApplyDialog(Adw.Dialog):
    """install.sh's output, while it runs.

    Streamed rather than collected: --settings-only is quick but not instant,
    and a window that goes blank for ten seconds is indistinguishable from one
    that has hung.
    """

    def __init__(self, repo, args, on_done):
        super().__init__(title="Applying", content_width=560,
                         content_height=420, can_close=False)
        self._on_done = on_done
        self._failed = False

        self._status = Adw.StatusPage(
            title="Applying",
            description="Reapplying the dconf preset, the CSS and the gsettings.")
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
        argv = ["bash", os.path.join(repo, "install.sh"),
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
        self._finish(True, "Applied",
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

        transparency = list(TRANSPARENCY)
        if self._applied.transparency not in [t[0] for t in transparency]:
            # A level set from the CLI that is not one of the buckets. Shown so
            # it can be read, and kept selectable so that opening this window
            # and pressing Apply cannot quietly round it to something else.
            pct = round(float(self._applied.transparency) * 100)
            transparency.append((self._applied.transparency,
                                 "Custom — %d%%" % pct,
                                 "Set from the command line"))
        self._transparency_row = self._combo(
            "Window transparency", "", transparency,
            self._applied.transparency, "transparency")
        glass.add(self._transparency_row)

        self._popup_row = Adw.SwitchRow(
            title="Blur behind menus and the top bar",
            subtitle="Popups, Quick Settings and the panel",
            active=self._applied.popup_blur)
        self._popup_row.connect("notify::active", self._on_changed, "popup_blur")
        glass.add(self._popup_row)
        page.add(glass)

        cli = Adw.PreferencesGroup(
            title="Command line only",
            description="Icon and cursor packs download a theme, and the GDM "
                        "login screen needs root — neither fits a window that "
                        "cannot ask for a password. Use ./install.sh --icons, "
                        "--cursors or --gdm for those.")
        page.add(cli)

        self._sync_sensitivity()
        return page

    # ---- state ------------------------------------------------------------

    def _current(self):
        """What the widgets are asking for."""
        s = Settings.__new__(Settings)
        s.accent = self._accent_row._ids[self._accent_row.get_selected()]
        s.radius = self._radius_row._ids[self._radius_row.get_selected()]
        s.blur = self._blur_row.get_active()
        s.scope = self._scope_row._ids[self._scope_row.get_selected()]
        s.transparency = \
            self._transparency_row._ids[self._transparency_row.get_selected()]
        s.popup_blur = self._popup_row.get_active()
        return s

    def _sync_sensitivity(self):
        """Solid mode is the absence of all of it, so the blur rows go dim."""
        on = self._blur_row.get_active()
        for row in (self._scope_row, self._transparency_row, self._popup_row):
            row.set_sensitive(on)

    def _on_changed(self, row, _param, key):
        if self._loading:
            return
        if isinstance(row, Adw.ComboRow):
            self._sync_subtitle(row)
        if key == "blur":
            self._sync_sensitivity()
        dirty = bool(self._current().flags_against(self._applied))
        self._apply.set_sensitive(dirty and self._repo is not None)

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
        if self._applied.transparency in self._transparency_row._ids:
            self._transparency_row.set_selected(
                self._transparency_row._ids.index(self._applied.transparency))
        self._popup_row.set_active(self._applied.popup_blur)
        self._loading = False
        self._sync_sensitivity()
        self._apply.set_sensitive(False)

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
