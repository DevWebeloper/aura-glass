#!/usr/bin/env python3
"""aura-glass — a full install's progress, in a window beside its terminal.

lib/progress.sh opens this, detached, when the setup wizard started the run or
--progress-window asked for it. The terminal stays the installer: sudo and
every question are still asked there, and this window says so whenever the
terminal is waiting. What it adds is the overview:

  while the install runs   the setup the wizard settled on, a progress bar, the
                           step running now and the last line it printed, and
                           the steps sliding in as each one starts
  when it ends             the steps with verify_install's checks under them,
                           a "Why?" on everything that did not go cleanly (what
                           the step reported, and its part of the log), "Check
                           again", and the log out screen

With --update it is the settings window's update window: the same columns, with
the changelog the settings window wrote to changelog.json on the left instead
of the setup (docs/GUI.md §2b). A run the wizard did not start, such as the
settings window's login screen run, has no setup to show and stays one column.

The contract is the two files in --dir, described at the top of
lib/progress.sh. This reads them and writes two files of its own: `window`, its
pid, which is how prompt_logout knows to leave the logout to this window, and
`window-layout`, which is how an update's install.sh knows whether the window
already open is this one or an older release's (progress_begin). It
installs and configures nothing; "Check again" runs `install.sh --verify`, and
"Log out now" runs gnome-session-quit, the same command prompt_logout runs.

Like the setup wizard, it needs PyGObject with Gtk 4 and libadwaita and nothing
else: progress_begin only opens it where gui_toolkit_present says those exist.
"""
import argparse
import json
import os
import re
import subprocess
import sys

import gi

gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")
from gi.repository import Adw, Gdk, Gio, GLib, GObject, Gtk, Pango  # noqa: E402

APP_ID = "io.github.DevWebeloper.AuraGlassInstall"

# How often the two files are read. Appended to by a shell script a few times a
# second at most, so polling is simpler than a file monitor and as quick.
POLL_MS = 250

# Written to window-layout. 2 is the two-column update window, 3 the one whose
# changelog bullets hang (notes_view). Raise it when the layout changes enough
# that an update should swap an open older window for this one (progress_begin
# compares it).
WINDOW_LAYOUT = 4

# The most of a step's log a "Why?" shows. A font or icon pack download can
# print a lot; the end of it is where the failure is.
LOG_TAIL_BYTES = 200_000

# The bar is green whatever the accent: it says "this is going well", and a red
# accent made a healthy install read like a failing one.
#
# Each step and check is a card with a round status badge: green for done
# (an "already in place" skip is done too), yellow for a warning, red for a
# failure, grey only for a step this run chose not to do. Cards fade in as
# their revealer slides them open, and a finished badge's icon pops in.
CSS = b"""
progressbar.install-progress > trough > progress {
    background-color: @success_color;
}
.step-card {
    padding: 8px 8px 8px 10px;
    min-height: 36px;
    border-radius: 12px;
    background-color: alpha(currentColor, 0.05);
}
.step-card button {
    min-height: 26px;
    padding: 2px 12px;
    font-size: smaller;
}
.step-card.appear { animation: aura-appear 420ms ease-out; }
.step-card.warn { background-color: alpha(@warning_color, 0.10); }
.step-card.fail { background-color: alpha(@error_color, 0.12); }
.step-card.running { background-color: alpha(currentColor, 0.09); }
.status-badge {
    min-width: 28px;
    min-height: 28px;
    border-radius: 999px;
}
.status-badge.ok { background-color: alpha(@success_color, 0.18); color: @success_color; }
.status-badge.warn { background-color: alpha(@warning_color, 0.20); color: @warning_color; }
.status-badge.fail { background-color: alpha(@error_color, 0.20); color: @error_color; }
.status-badge.running { background-color: alpha(currentColor, 0.10); }
.status-badge.skip, .status-badge.pending {
    background-color: alpha(currentColor, 0.08);
    color: alpha(currentColor, 0.45);
}
.status-badge image.pop, image.hero-pop { animation: aura-pop 360ms ease-out; }
.release-card {
    padding: 14px 16px;
    border-radius: 14px;
    background-color: alpha(currentColor, 0.06);
}
.changelog-pane, .changelog-pane-narrow { border-radius: 0; }
.changelog-pane { border-right: 1px solid alpha(currentColor, 0.10); }
.changelog-pane-narrow { border-bottom: 1px solid alpha(currentColor, 0.10); }
.version-pill {
    padding: 3px 10px;
    border-radius: 999px;
    background-color: alpha(currentColor, 0.10);
    font-weight: bold;
}
.setup-badge {
    min-width: 32px;
    min-height: 32px;
    border-radius: 999px;
    background-color: alpha(currentColor, 0.09);
}
.setup-dot {
    min-width: 14px;
    min-height: 14px;
    border-radius: 999px;
}
.next-number {
    min-width: 22px;
    min-height: 22px;
    border-radius: 999px;
    background-color: alpha(currentColor, 0.09);
    font-size: smaller;
    font-weight: bold;
}
.latest-pill {
    padding: 1px 8px;
    border-radius: 999px;
    background-color: alpha(@success_color, 0.18);
    color: @success_color;
    font-size: smaller;
    font-weight: bold;
}
@keyframes aura-appear {
    from { opacity: 0; }
    to { opacity: 1; }
}
@keyframes aura-pop {
    from { -gtk-icon-transform: scale(0.3); opacity: 0; }
    70% { -gtk-icon-transform: scale(1.15); opacity: 1; }
    to { -gtk-icon-transform: scale(1); }
}
"""

# How long a card takes to slide open, and the bar to move to its new value.
REVEAL_MS = 350
BAR_MS = 400

ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\x1b[()][A-Z0-9]")

STATUS_ICONS = {
    "pending": ("content-loading-symbolic", "dim-label"),
    "ok": ("object-select-symbolic", "success"),
    "warn": ("dialog-warning-symbolic", "warning"),
    "fail": ("dialog-error-symbolic", "error"),
    "skip": ("action-unavailable-symbolic", "dim-label"),
}

# What a badge shows for a status: a skip with no reason was "already in
# place", which is as good as done.
BADGE_ICONS = {
    "pending": "content-loading-symbolic",
    "ok": "object-select-symbolic",
    "warn": "dialog-warning-symbolic",
    "fail": "process-stop-symbolic",
    "skip": "action-unavailable-symbolic",
}

FINISHED = {
    "ok": ("object-select-symbolic", "success", "Aura Glass is installed",
           "Log out and back in to see it. Extensions only load into a new "
           "session."),
    "warn": ("dialog-warning-symbolic", "warning",
             "Installed, with a few problems",
             "Everything marked below has a Why? button that shows what went "
             "wrong. The rest is in place: log out and back in to see it."),
    "fail": ("dialog-error-symbolic", "error", "The install stopped",
             "Nothing after the failed step was installed. Why? shows what "
             "went wrong — fix that and run ./install.sh again."),
}


# How each pack and font spells its own name, for the setup cards. A name that
# is not here came in as a typed --icons or --cursors and is shown as it is.
PACK_NAMES = {
    "colloid": "Colloid",
    "reversal": "Reversal",
    "hatter": "Hatter",
    "mactahoe": "MacTahoe",
    "adwaita": "Adwaita",
    "aosp": "AOSP",
    "moga": "Aura Moga Neon",
    "original": "What you had before",
}
FONT_NAMES = {
    "misans": "MiSans",
    "inter": "Inter",
    "sf-pro": "San Francisco",
}
SCOPE_NAMES = {
    "all": "All apps",
    "gtk": "GTK apps",
    "none": "No window blur",
}

# Width of an install's window with the setup column, and without it.
WIDE_WIDTH = 1040
SINGLE_WIDTH = 640


def clean(text):
    return ANSI.sub("", text).replace("\r", "")


def notes_view(markup):
    """Changelog markup as widgets, each bullet's text in a column of its own.

    A wrapped "  •  text" line in one label runs its second line back under
    the bullet. Here the bullet is its own label and the text wraps beside it,
    so every line of an entry starts at the same edge. Lines that are not
    bullets (the New / Fixed headings, a note's prose) stay plain labels, and a
    blank line is a gap. gui/aura_glass_settings.py keeps the same helper; the two windows are
    separate processes and do not import each other.
    """
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    plain = []

    def label(text, **kw):
        widget = Gtk.Label(xalign=0, wrap=True, selectable=True, **kw)
        widget.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
        try:
            widget.set_markup(text)
        except GLib.Error:
            widget.set_text(re.sub(r"<[^>]+>", "", text))
        return widget

    def flush():
        if plain:
            box.append(label("\n".join(plain)))
            del plain[:]

    for line in markup.split("\n"):
        bullet = re.match(r"^(\s*)•\s+(.*)$", line)
        if bullet:
            flush()
            # Leading spaces are the markdown's nesting: two per level, past
            # the two every bullet line opens with.
            depth = max(0, len(bullet.group(1)) - 2) // 2
            row = Gtk.Box(spacing=8, margin_start=8 + 16 * depth)
            row.append(Gtk.Label(label="•", valign=Gtk.Align.START))
            row.append(label(bullet.group(2), hexpand=True))
            box.append(row)
        elif not line.strip():
            flush()
            box.append(Gtk.Box(height_request=8))
        else:
            plain.append(line)
    flush()
    return box


def read_range(path, start, end=None):
    """The log between two byte offsets, as text, the end of it if long."""
    try:
        with open(path, "rb") as handle:
            if end is None:
                handle.seek(0, os.SEEK_END)
                end = handle.tell()
            start = max(start, end - LOG_TAIL_BYTES)
            handle.seek(start)
            data = handle.read(max(0, end - start))
    except OSError:
        return ""
    return clean(data.decode("utf-8", "replace"))


def status_icon(status):
    name, css = STATUS_ICONS.get(status, STATUS_ICONS["pending"])
    image = Gtk.Image.new_from_icon_name(name)
    image.add_css_class(css)
    return image


def open_uri(uri):
    try:
        Gio.AppInfo.launch_default_for_uri(uri, None)
    except GLib.Error as exc:
        print("aura-glass: could not open %s: %s" % (uri, exc.message),
              file=sys.stderr)


class Step:
    def __init__(self, ident, title):
        self.id = ident
        self.title = title
        self.status = "pending"
        self.start = None
        self.end = None
        self.notes = []          # (level, text)
        self.card = None
        self.button = None


class Card(Gtk.Revealer):
    """One step or check: a status badge, a title, a line under it, a button.

    It is a revealer so it can slide open when it first appears; reveal()
    does that, fading the card in as it opens.
    """

    def __init__(self, title, button_label=None, on_button=None):
        super().__init__(transition_type=Gtk.RevealerTransitionType.SLIDE_DOWN,
                         transition_duration=REVEAL_MS)
        self.box = Gtk.Box(spacing=12)
        self.box.add_css_class("step-card")
        self.badge = Gtk.Box(halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        self.badge.add_css_class("status-badge")
        # The stack fills the badge so the icon is centred in the circle; the
        # badge's own expand is set so it does not pass that on to the card.
        self.badge.set_hexpand(False)
        self.badge.set_vexpand(False)
        self.stack = Gtk.Stack(hexpand=True, vexpand=True)
        self.stack.add_named(Adw.Spinner(width_request=18, height_request=18,
                                         halign=Gtk.Align.CENTER,
                                         valign=Gtk.Align.CENTER), "running")
        self.image = None
        self.badge.append(self.stack)
        self.box.append(self.badge)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2,
                       hexpand=True, valign=Gtk.Align.CENTER)
        self.title = Gtk.Label(label=title, xalign=0, wrap=True,
                               halign=Gtk.Align.START)
        text.append(self.title)
        self.subtitle = Gtk.Label(xalign=0, wrap=True, visible=False,
                                  halign=Gtk.Align.START)
        self.subtitle.add_css_class("caption")
        self.subtitle.add_css_class("dim-label")
        text.append(self.subtitle)
        self.box.append(text)

        self.button = Gtk.Button(label=button_label or "", visible=False,
                                 valign=Gtk.Align.CENTER)
        self.button.add_css_class("flat")
        if on_button is not None:
            self.button.connect("clicked", lambda _b: on_button())
        self.box.append(self.button)
        self.set_child(self.box)
        self.status = None

    def reveal(self):
        if self.get_reveal_child():
            return
        self.box.add_css_class("appear")
        # Opened on the next idle, once the card is in the tree, so the slide
        # is drawn instead of the card simply being there.
        GLib.idle_add(lambda: self.set_reveal_child(True) and False)

    def set_status(self, status, look=None):
        """status picks the card's tint; look (default status) the badge."""
        look = look or status
        if (status, look) == self.status:
            return
        self.status = (status, look)
        for name in ("ok", "warn", "fail", "skip", "pending", "running"):
            self.badge.remove_css_class(name)
            self.box.remove_css_class(name)
        self.badge.add_css_class(look)
        self.box.add_css_class(status)
        if status == "running":
            self.stack.set_visible_child_name("running")
            return
        # A new image each time, so its pop animation plays from the start.
        image = Gtk.Image.new_from_icon_name(
            BADGE_ICONS.get(look, BADGE_ICONS["pending"]))
        image.set_halign(Gtk.Align.CENTER)
        image.set_valign(Gtk.Align.CENTER)
        if look != "pending":
            image.add_css_class("pop")
        self.stack.add_child(image)
        self.stack.set_visible_child(image)
        if self.image is not None:
            self.stack.remove(self.image)
        self.image = image

    def set_subtitle(self, text):
        self.subtitle.set_label(text)
        self.subtitle.set_visible(bool(text))


class Window(Adw.ApplicationWindow):
    def __init__(self, app, run_dir, update=False):
        super().__init__(application=app, title="Aura Glass",
                         default_width=WIDE_WIDTH if update else SINGLE_WIDTH,
                         default_height=720,
                         width_request=360, height_request=480)
        self.update = update
        self.dir = run_dir
        self.events_path = os.path.join(run_dir, "events")
        self.log_path = os.path.join(run_dir, "log")
        self.events_pos = 0
        self.events_buf = b""
        self.steps = {}
        self.order = []
        self.checks = []
        self.pid = None
        self.repo = None
        self.dry = False
        self.finished = None
        self.verifying = False
        self.log_pos = 0
        self.log_view = None
        self.setup_shown = False
        self.follow = True
        self.bar_target = 0.0
        self.bar_animation = None
        self.changelog = self._read_changelog() if update else {}

        self._write_pid()
        self._build()
        self.poll()
        self._timer = GLib.timeout_add(POLL_MS, self.poll)
        self.connect("close-request", self._on_close)

    # ---- files ---------------------------------------------------------------

    def _write_pid(self):
        # window-layout after window: progress_begin waits for it to know this
        # window is up, and an update window without it (v0.3.8 and before)
        # is the old single-column one it replaces with this one.
        try:
            with open(os.path.join(self.dir, "window"), "w") as handle:
                handle.write("%d\n" % os.getpid())
            with open(os.path.join(self.dir, "window-layout"), "w") as handle:
                handle.write("%s\n" % WINDOW_LAYOUT)
        except OSError:
            pass

    def _on_close(self, _window):
        for name in ("window", "window-layout"):
            try:
                os.unlink(os.path.join(self.dir, name))
            except OSError:
                pass
        if self._timer:
            GLib.source_remove(self._timer)
            self._timer = 0
        return False

    def _read_changelog(self):
        """changelog.json, as the settings window wrote it (update_changelog)."""
        try:
            with open(os.path.join(self.dir, "changelog.json")) as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            return {}
        return data if isinstance(data, dict) else {}

    def _follow_log(self):
        """Append what the log gained since the last poll to the live view."""
        try:
            with open(self.log_path, "rb") as handle:
                handle.seek(self.log_pos)
                chunk = handle.read()
                self.log_pos = handle.tell()
        except OSError:
            return
        if not chunk:
            return
        buffer = self.log_view.get_buffer()
        adj = self.log_scroller.get_vadjustment()
        at_end = adj.get_value() >= adj.get_upper() - adj.get_page_size() - 24
        buffer.insert(buffer.get_end_iter(),
                      clean(chunk.decode("utf-8", "replace")))
        # A long run's log is long; the view keeps its last part.
        extra = buffer.get_char_count() - LOG_TAIL_BYTES
        if extra > 0:
            buffer.delete(buffer.get_start_iter(),
                          buffer.get_iter_at_offset(extra))
        if at_end:
            GLib.idle_add(self._scroll_to_end, self.log_view)

    def poll(self):
        self._follow_log()
        try:
            with open(self.events_path, "rb") as handle:
                handle.seek(self.events_pos)
                chunk = handle.read()
                self.events_pos = handle.tell()
        except OSError:
            chunk = b""
        if chunk:
            self.events_buf += chunk
            *lines, self.events_buf = self.events_buf.split(b"\n")
            for line in lines:
                try:
                    event = json.loads(line.decode("utf-8", "replace"))
                except ValueError:
                    continue
                self.handle(event)

        if self.finished is None:
            self._show_last_line()
            if self.pid and not self._alive(self.pid):
                # No finish event and no installer: the terminal was closed,
                # or the run was killed before its exit trap could say so.
                self.handle({"t": "finish", "status": "fail", "rc": "?",
                             "lost": True})
        return True

    @staticmethod
    def _alive(pid):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        except PermissionError:
            return True
        return True

    def _show_last_line(self):
        tail = read_range(self.log_path, 0)[-4000:]
        lines = [line.strip() for line in tail.split("\n") if line.strip()]
        self.last_line.set_label(lines[-1] if lines else "")

    # ---- events --------------------------------------------------------------

    def handle(self, event):
        kind = event.get("t")
        if kind == "begin":
            try:
                self.pid = int(event.get("pid", "0")) or None
            except ValueError:
                self.pid = None
            self.repo = event.get("repo") or None
            self.dry = event.get("dry") == "1"
        elif kind == "choices":
            self._show_setup(event)
        elif kind == "plan":
            self._add_step(event.get("id", ""), event.get("title", ""))
        elif kind == "start":
            step = self._step(event)
            step.status = "running"
            step.start = self._int(event.get("offset"))
            self.current.set_label(step.title + "…")
            self._refresh_step(step)
        elif kind == "note":
            step = self.steps.get(event.get("id", ""))
            if step is not None:
                step.notes.append((event.get("level", ""), event.get("text", "")))
                self._refresh_step(step)
        elif kind == "end":
            step = self._step(event)
            step.status = event.get("status", "ok")
            step.end = self._int(event.get("offset"))
            self._refresh_step(step)
        elif kind == "wait":
            self.banner.set_title("The terminal is asking: %s"
                                  % event.get("text", "a question"))
            self.banner.set_revealed(True)
            self.title.set_subtitle("Waiting for you in the terminal")
        elif kind == "resume":
            self.banner.set_revealed(False)
            self.title.set_subtitle("")
        elif kind == "verify-begin":
            for check in self.checks:
                self.checks_list.remove(check["row"])
            self.checks = []
        elif kind == "check":
            self._add_check(event)
        elif kind == "finish":
            self._finish(event)
        self._update_progress()

    @staticmethod
    def _int(value):
        try:
            return int(value)
        except (TypeError, ValueError):
            return None

    def _step(self, event):
        ident = event.get("id", "")
        if ident not in self.steps:
            self._add_step(ident, ident)
        return self.steps[ident]

    # ---- layout --------------------------------------------------------------

    def _build(self):
        view = Adw.ToolbarView()
        header = Adw.HeaderBar()
        self.title = Adw.WindowTitle(
            title="Updating Aura Glass" if self.update
            else "Installing Aura Glass",
            subtitle=self._update_span() if self.update else "")
        header.set_title_widget(self.title)
        view.add_top_bar(header)

        self.banner = Adw.Banner(title="", revealed=False)
        view.add_top_bar(self.banner)

        # The bar, the step running now and, when it ends, the outcome, at the
        # head of the right-hand column, above the steps.
        size = 40
        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.hero_icon = Gtk.Stack(
            transition_type=Gtk.StackTransitionType.CROSSFADE,
            transition_duration=250)
        spinner = Adw.Spinner(width_request=size, height_request=size)
        self.hero_icon.add_named(spinner, "running")
        self.hero_image = Gtk.Image(pixel_size=size)
        self.hero_icon.add_named(self.hero_image, "done")
        hero.append(self.hero_icon)

        self.heading = Gtk.Label(
            label="Updating Aura Glass" if self.update
            else "Installing Aura Glass",
            wrap=True, justify=Gtk.Justification.CENTER)
        self.heading.add_css_class("title-3")
        hero.append(self.heading)

        self.current = Gtk.Label(label="Starting…", wrap=True,
                                 justify=Gtk.Justification.CENTER)
        self.current.add_css_class("dim-label")
        hero.append(self.current)

        self.bar = Gtk.ProgressBar(show_text=True, margin_top=8)
        self.bar.add_css_class("install-progress")
        hero.append(self.bar)

        self.last_line = Gtk.Label(label="", xalign=0.5,
                                   ellipsize=Pango.EllipsizeMode.END)
        self.last_line.add_css_class("monospace")
        self.last_line.add_css_class("caption")
        self.last_line.add_css_class("dim-label")
        hero.append(self.last_line)

        hint = Gtk.Label(
            label="Questions and passwords are asked in the terminal this "
                  "was started from.",
            wrap=True, justify=Gtk.Justification.CENTER)
        hint.add_css_class("caption")
        hint.add_css_class("dim-label")
        self.hint = hint
        hero.append(hint)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18,
                       margin_top=16, margin_bottom=18,
                       margin_start=20, margin_end=20)

        steps_section, self.steps_list = self._section("Steps")
        body.append(steps_section)

        self.check_again = Gtk.Button(label="Check again",
                                      valign=Gtk.Align.CENTER)
        self.check_again.add_css_class("flat")
        self.check_again.connect("clicked", self._on_check_again)
        self.checks_section, self.checks_list = self._section(
            "Checks", "What is on disk and in your settings now.",
            self.check_again)
        self.checks_section.set_visible(False)
        body.append(self.checks_section)

        scroller = Gtk.ScrolledWindow(
            child=Adw.Clamp(maximum_size=560, child=body), vexpand=True,
            hscrollbar_policy=Gtk.PolicyType.NEVER)
        self._build_columns(view, hero, scroller)

        bottom = Gtk.Box(spacing=12, margin_top=12, margin_bottom=12,
                         margin_start=12, margin_end=12)
        log_button = Gtk.ToggleButton(label="Show log")
        log_button.connect("toggled", self._on_toggle_log)
        bottom.append(log_button)
        bottom.append(Gtk.Box(hexpand=True))
        self.later = Gtk.Button(label="Later", visible=False)
        self.later.connect("clicked", lambda _b: self.close())
        bottom.append(self.later)
        self.logout = Gtk.Button(label="Log out now", visible=False)
        self.logout.add_css_class("suggested-action")
        self.logout.connect("clicked", self._on_logout)
        bottom.append(self.logout)
        view.add_bottom_bar(bottom)

        self.set_content(view)

    def _build_columns(self, view, hero, scroller):
        """Two columns: what's new or the setup on the left, how it is going on
        the right.

        The steps appear one by one as they start, and the right column keeps
        the newest in view unless it was scrolled up to read. The log is
        followed all along but hidden in a drawer under both columns, opened
        by Show log: the steps already say what is happening, and the log is
        there for when one of them did not go cleanly. Narrower than 760sp
        the columns stack, the left one first.

        An install's left column stays hidden until a choices event fills it,
        and a run that sends none is the right column alone.
        """
        # Equal halves whatever each holds, so neither column jumps in width
        # as the steps and checks come in. A hidden child takes no half.
        columns = Gtk.Box(vexpand=True, homogeneous=True)

        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                       margin_top=20, margin_bottom=20,
                       margin_start=20, margin_end=20)
        if self.update:
            self._build_changelog(side)
        self.side = side
        self.left = Gtk.ScrolledWindow(
            child=Adw.Clamp(maximum_size=560, child=side), vexpand=True,
            hscrollbar_policy=Gtk.PolicyType.NEVER, visible=self.update)
        self.left.add_css_class("changelog-pane")
        columns.append(self.left)

        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        right.append(Adw.Clamp(maximum_size=560, child=hero,
                               margin_top=20, margin_bottom=14,
                               margin_start=20, margin_end=20))
        right.append(Gtk.Separator())
        right.append(scroller)
        self.steps_scroller = scroller
        adj = scroller.get_vadjustment()
        adj.connect("value-changed", self._on_steps_scrolled)
        adj.connect("notify::upper", self._on_steps_grew)

        columns.append(right)

        self.log_view = Gtk.TextView(
            editable=False, cursor_visible=False, monospace=True,
            wrap_mode=Gtk.WrapMode.WORD_CHAR, top_margin=6,
            bottom_margin=6, left_margin=10, right_margin=10)
        self.log_view.add_css_class("caption")
        self.log_scroller = Gtk.ScrolledWindow(child=self.log_view,
                                               min_content_height=220)
        self.log_scroller.add_css_class("view")
        drawer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        drawer.append(Gtk.Separator())
        drawer.append(self.log_scroller)
        self.log_drawer = Gtk.Revealer(
            child=drawer, reveal_child=False,
            transition_type=Gtk.RevealerTransitionType.SLIDE_UP,
            transition_duration=REVEAL_MS)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        content.append(columns)
        content.append(self.log_drawer)
        view.set_content(content)

        narrow = Adw.Breakpoint.new(
            Adw.BreakpointCondition.parse("max-width: 760sp"))
        narrow.add_setter(columns, "orientation", Gtk.Orientation.VERTICAL)
        narrow.add_setter(self.left, "css-classes", GObject.Value(
            GObject.TYPE_STRV, ["changelog-pane-narrow"]))
        self.add_breakpoint(narrow)

    def _section(self, title, description=None, suffix=None):
        """A heading, an optional line under it, and a list of cards."""
        section = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        head = Gtk.Box(spacing=12)
        words = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True,
                        valign=Gtk.Align.CENTER)
        label = Gtk.Label(label=title, xalign=0)
        label.add_css_class("heading")
        words.append(label)
        if description:
            line = Gtk.Label(label=description, xalign=0, wrap=True)
            line.add_css_class("caption")
            line.add_css_class("dim-label")
            words.append(line)
        head.append(words)
        if suffix is not None:
            head.append(suffix)
        section.append(head)
        cards = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        section.append(cards)
        return section, cards

    def _update_span(self):
        old, new = self.changelog.get("from"), self.changelog.get("to")
        if old and new:
            return "%s → %s" % (old, new)
        return new or ""

    def _build_changelog(self, body):
        """What's new, then one card per release the update brings, newest
        first."""
        sections = self.changelog.get("sections") or []
        heading = Gtk.Label(label="What's new", xalign=0)
        heading.add_css_class("title-2")
        body.append(heading)
        span = self._update_span()
        if span:
            pill = Gtk.Label(label=span, halign=Gtk.Align.START)
            pill.add_css_class("version-pill")
            body.append(pill)
        intro = Gtk.Label(
            label=("%d release%s and the commits after them."
                   % (len(sections), "" if len(sections) == 1 else "s")
                   if sections else
                   "Nothing new between the installed version and this one — "
                   "the update reinstalls it, or goes back to it."),
            xalign=0, wrap=True)
        intro.add_css_class("dim-label")
        body.append(intro)
        for index, section in enumerate(sections):
            count = section.get("count") or 0
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            card.add_css_class("release-card")
            top = Gtk.Box(spacing=8)
            title = Gtk.Label(label=section.get("title", ""), xalign=0)
            title.add_css_class("title-4")
            top.append(title)
            if index == 0:
                latest = Gtk.Label(label="Newest", valign=Gtk.Align.CENTER)
                latest.add_css_class("latest-pill")
                top.append(latest)
            top.append(Gtk.Box(hexpand=True))
            date = Gtk.Label(label=section.get("date", ""))
            date.add_css_class("caption")
            date.add_css_class("dim-label")
            top.append(date)
            card.append(top)
            commits = Gtk.Label(
                label="%d commit%s" % (count, "" if count == 1 else "s"),
                xalign=0)
            commits.add_css_class("caption")
            commits.add_css_class("dim-label")
            card.append(commits)
            notes = notes_view(section.get("markup", ""))
            notes.set_margin_top(6)
            card.append(notes)
            body.append(card)

    def _show_setup(self, event):
        """The left column of a wizard's install: what it is about to set up.

        Every value is what install.sh resolved, not what the wizard asked for,
        so this is true of a re-run that kept a remembered answer too.
        """
        if self.setup_shown or self.update:
            return
        self.setup_shown = True
        body = self.side

        heading = Gtk.Label(label="Your setup", xalign=0)
        heading.add_css_class("title-2")
        body.append(heading)
        version = event.get("version", "")
        if version:
            pill = Gtk.Label(label=version, halign=Gtk.Align.START)
            pill.add_css_class("version-pill")
            body.append(pill)
        intro = Gtk.Label(
            label="What this install is putting in place. All of it can be "
                  "changed later.",
            xalign=0, wrap=True)
        intro.add_css_class("dim-label")
        body.append(intro)

        # A grid rather than a FlowBox: a FlowBox falls to one column as soon as
        # the longest line's natural width stops fitting twice, so the same six
        # cards came out in two shapes depending on the answers.
        grid = Gtk.Grid(column_homogeneous=True, row_homogeneous=True,
                        column_spacing=8, row_spacing=8)
        for index, card in enumerate(self._setup_cards(event)):
            grid.attach(self._setup_card(*card), index % 2, index // 2, 1, 1)
        body.append(grid)
        body.append(self._next_card())

        self.left.set_visible(True)
        # Before the window is shown this is simply its size. A window already
        # up, because this event lost the race to the first poll, grows to it.
        self.set_default_size(WIDE_WIDTH, self.get_default_size()[1])

    def _setup_cards(self, event):
        """(icon or an accent's hex, label, value, detail), one per card."""
        accent = event.get("accent", "")
        hexcolour = event.get("accent_hex", "")
        if not re.fullmatch(r"[0-9a-fA-F]{6}", hexcolour):
            hexcolour = None
        font = event.get("font", "")
        look = (hexcolour or "applications-graphics-symbolic", "Look",
                accent.capitalize(),
                "%s font" % FONT_NAMES[font] if font in FONT_NAMES
                else "Your current font")

        if event.get("glass") == "performance":
            glass = "Performance"
            detail = "No blur"
        else:
            glass = "Frosted glass"
            scope = event.get("scope", "")
            detail = "%s · %s%% opacity" % (
                SCOPE_NAMES.get(scope, scope), event.get("opacity", ""))

        def pack(name, kept):
            return PACK_NAMES.get(name.split("-")[0], name) if name else kept

        size = event.get("cursor_size", "")
        try:
            extras = int(event.get("extensions", "0"))
        except ValueError:
            extras = 0
        themed = event.get("gdm") == "1"
        matched = event.get("gdm_monitors") == "1"
        return [
            look,
            ("video-display-symbolic", "Glass", glass, detail),
            ("view-app-grid-symbolic", "Icons",
             pack(event.get("icons", ""), "Left as they are"), ""),
            ("input-mouse-symbolic", "Pointer",
             pack(event.get("cursors", ""), "Left as it is"),
             "%spx" % size if size else "Size left as it is"),
            ("application-x-addon-symbolic", "Extensions",
             "%d optional" % extras if extras else "Foundation only",
             "With the volume pill" if event.get("osd") == "1"
             else "GNOME's own volume popup"),
            ("system-lock-screen-symbolic", "Login screen",
             "Themed" if themed else "Left as it is",
             "Monitor layout matched" if matched
             else "Monitor layout left alone"),
        ]

    def _setup_card(self, icon, label, value, detail):
        card = Gtk.Box(spacing=12)
        card.add_css_class("release-card")
        # Its own expand set, so the centred child does not pass one on to the
        # card and push the words away from the badge.
        badge = Gtk.Box(halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER,
                        hexpand=False, vexpand=False)
        badge.add_css_class("setup-badge")
        if icon.endswith("-symbolic"):
            badge.append(Gtk.Image(icon_name=icon, hexpand=True,
                                   halign=Gtk.Align.CENTER))
        else:
            # The accent's own colour, from install.sh's accent_hex, rather
            # than a copy of the nine here. Nothing is the accent yet: this
            # window can be open before the run has set it.
            dot = Gtk.Box(hexpand=True, vexpand=True, halign=Gtk.Align.CENTER,
                          valign=Gtk.Align.CENTER)
            dot.add_css_class("setup-dot")
            provider = Gtk.CssProvider()
            provider.load_from_data(
                (".setup-dot { background-color: #%s; }" % icon).encode())
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(), provider,
                Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)
            badge.append(dot)
        card.append(badge)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1,
                       hexpand=True, valign=Gtk.Align.CENTER)
        name = Gtk.Label(label=label, xalign=0)
        name.add_css_class("caption")
        name.add_css_class("dim-label")
        text.append(name)
        answer = Gtk.Label(label=value, xalign=0, wrap=True)
        answer.add_css_class("heading")
        text.append(answer)
        if detail:
            more = Gtk.Label(label=detail, xalign=0, wrap=True)
            more.add_css_class("caption")
            more.add_css_class("dim-label")
            text.append(more)
        card.append(text)
        return card

    def _next_card(self):
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        card.add_css_class("release-card")
        title = Gtk.Label(label="What happens next", xalign=0)
        title.add_css_class("title-4")
        card.append(title)
        for number, line in enumerate((
                "The terminal asks for your password if a step needs it.",
                "Log out and back in. Extensions only load into a new session.",
                "Retune anything in Aura Glass Settings, without reinstalling.",
        ), 1):
            row = Gtk.Box(spacing=10)
            badge = Gtk.Label(label=str(number), valign=Gtk.Align.START)
            badge.add_css_class("next-number")
            row.append(badge)
            words = Gtk.Label(label=line, xalign=0, wrap=True, hexpand=True,
                              valign=Gtk.Align.CENTER)
            row.append(words)
            card.append(row)
        return card

    def _add_step(self, ident, title):
        if ident in self.steps:
            return
        step = Step(ident, title)
        step.card = Card(title, "Details", lambda s=step: self._step_details(s))
        step.button = step.card.button
        self.steps_list.append(step.card)
        self.steps[ident] = step
        self.order.append(ident)
        # Not revealed yet: each step shows as it starts, so the column fills
        # in as the run goes, and _finish shows the ones it never reached.
        self._refresh_step(step)

    def _refresh_step(self, step):
        subtitle = ""
        problems = [text for level, text in step.notes
                    if level in ("warn", "error")]
        infos = [text for level, text in step.notes if level == "info"]
        look = step.status
        if step.status == "running":
            subtitle = "Running…"
        elif step.status == "fail":
            subtitle = problems[-1] if problems else "Stopped here"
        elif step.status == "warn":
            subtitle = problems[0] if problems else ""
            if len(problems) > 1:
                subtitle += " (and %d more)" % (len(problems) - 1)
        elif step.status == "skip":
            # Without a reason, every line it printed was a skip: what it
            # would install was already there, which is as good as done.
            subtitle = infos[0] if infos else "Already in place"
            if not infos:
                look = "ok"
        elif step.status == "pending" and self.finished == "fail":
            subtitle = "Not reached"
        step.card.set_status(step.status, look)
        step.card.set_subtitle(subtitle)
        if step.status != "pending" or self.finished is not None:
            step.card.reveal()

        step.button.set_visible(step.status not in ("pending", "running"))
        step.button.set_label("Why?" if step.status in ("warn", "fail")
                              else "Details")

    def _add_check(self, event):
        status = event.get("status", "ok")
        title = "%s — %s" % (event.get("group", ""), event.get("title", ""))
        card = Card(title, "Why?", lambda e=event: self._check_details(e))
        card.set_status(status if status in BADGE_ICONS else "fail")
        if status != "ok":
            card.set_subtitle(event.get("why", ""))
            card.button.set_visible(True)
        self.checks_list.append(card)
        self.checks_section.set_visible(True)
        card.reveal()
        self.checks.append({"row": card, "status": status})

    # ---- following the newest step -------------------------------------------

    def _on_steps_scrolled(self, adj):
        # Following until scrolled up to read; back at the bottom, again.
        self.follow = adj.get_value() >= adj.get_upper() - adj.get_page_size() - 24

    def _on_steps_grew(self, adj, _pspec):
        # A card sliding open grows the column a little every frame; keeping
        # the bottom in view each time makes the scroll as smooth as the slide.
        if self.follow:
            adj.set_value(adj.get_upper() - adj.get_page_size())

    def _on_toggle_log(self, button):
        shown = button.get_active()
        button.set_label("Hide log" if shown else "Show log")
        self.log_drawer.set_reveal_child(shown)
        if shown:
            GLib.idle_add(self._scroll_to_end, self.log_view)

    def _update_progress(self):
        total = len(self.order)
        # An update knows its own two steps before the installer has planned
        # its thirteen; counting those as still to come keeps the bar from
        # filling at "2 of 2" and then dropping back.
        if self.update and total <= 2 and self.finished is None:
            total += 13
        if not total:
            self.bar.pulse()
            return
        done = sum(1 for i in self.order
                   if self.steps[i].status not in ("pending", "running"))
        running = any(self.steps[i].status == "running" for i in self.order)
        fraction = (done + (0.5 if running else 0)) / total
        if self.finished is not None:
            fraction = 1.0 if self.finished != "fail" else fraction
        self.bar.set_text("%d of %d" % (done, total))
        fraction = min(fraction, 1.0)
        if abs(fraction - self.bar_target) < 1e-6:
            return
        # The bar glides to its new value rather than jumping.
        self.bar_target = fraction
        if self.bar_animation is not None:
            self.bar_animation.skip()
        self.bar_animation = Adw.TimedAnimation(
            widget=self.bar, value_from=self.bar.get_fraction(),
            value_to=fraction, duration=BAR_MS,
            target=Adw.PropertyAnimationTarget.new(self.bar, "fraction"))
        self.bar_animation.play()

    def _finish(self, event):
        if self.finished is not None:
            return
        status = event.get("status", "ok")
        if status not in FINISHED:
            status = "fail"
        if status == "ok" and any(c["status"] != "ok" for c in self.checks):
            status = "warn"
        self.finished = status
        # Every step is shown now, the ones a stopped run never reached too.
        for ident in self.order:
            step = self.steps[ident]
            if step.status == "running":
                step.status = "fail"
            self._refresh_step(step)

        icon, css, heading, text = FINISHED[status]
        if self.update:
            heading = {"ok": "Aura Glass is updated",
                       "warn": "Updated, with a few problems",
                       "fail": "The update stopped"}[status]
        live = event.get("logout") == "0"
        if live and status != "fail":
            text = "Everything is already live, so there is no need to log out."
        if event.get("lost"):
            text = ("The installer stopped without finishing — its terminal "
                    "was closed or the run was interrupted. Why? on the last "
                    "step shows how far it got. Run ./install.sh again.")
        if self.dry:
            heading = "Dry run finished"
            text = "Nothing was changed. The log shows what would have run."
        self.hero_image.set_from_icon_name(icon)
        for name in ("success", "warning", "error"):
            self.hero_image.remove_css_class(name)
        self.hero_image.add_css_class(css)
        self.hero_image.add_css_class("hero-pop")
        self.hero_icon.set_visible_child_name("done")
        self.heading.set_label(heading)
        self.current.set_label(text)
        self.last_line.set_visible(False)
        self.hint.set_visible(False)
        self.banner.set_revealed(False)
        self.title.set_title("Aura Glass")
        self.title.set_subtitle(self._update_span() if self.update else "")

        can_log_out = status != "fail" and not self.dry and not live
        self.logout.set_visible(can_log_out)
        self.later.set_label("Later" if can_log_out else "Close")
        self.later.set_visible(True)
        self.check_again.set_sensitive(bool(self.repo) and not self.dry)
        if can_log_out:
            self.set_default_widget(self.logout)

    # ---- actions -------------------------------------------------------------

    def _step_details(self, step):
        dialog = Adw.Dialog(title=step.title, content_width=560,
                            content_height=560)
        view = Adw.ToolbarView()
        view.add_top_bar(Adw.HeaderBar())
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                      margin_top=12, margin_bottom=12,
                      margin_start=12, margin_end=12)

        explain = {
            "ok": "This step finished without a problem.",
            "skip": "This step had nothing to do on this run.",
            "warn": "This step finished, but reported the problems below. "
                    "The install went on past them.",
            "fail": "The install stopped in this step. The end of its output "
                    "below is usually where the reason is.",
        }.get(step.status, "")
        label = Gtk.Label(label=explain, wrap=True, xalign=0)
        box.append(label)

        if step.notes:
            group = Adw.PreferencesGroup(title="What it reported")
            for level, text in step.notes:
                row = Adw.ActionRow(title=GLib.markup_escape_text(text),
                                    title_lines=0)
                row.add_prefix(status_icon(
                    {"warn": "warn", "error": "warn"}.get(level, "skip")))
                group.add(row)
            box.append(group)

        output = ""
        if step.start is not None:
            output = read_range(self.log_path, step.start, step.end)
        text = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                            wrap_mode=Gtk.WrapMode.WORD_CHAR,
                            top_margin=8, bottom_margin=8,
                            left_margin=8, right_margin=8)
        text.get_buffer().set_text(output.strip() or "(this step printed nothing)")
        scroller = Gtk.ScrolledWindow(child=text, vexpand=True,
                                      min_content_height=220)
        scroller.add_css_class("card")
        box.append(Gtk.Label(label="Output of this step", xalign=0,
                             css_classes=["heading"]))
        box.append(scroller)
        GLib.idle_add(self._scroll_to_end, text)

        buttons = Gtk.Box(spacing=12, halign=Gtk.Align.END)
        copy = Gtk.Button(label="Copy output")
        copy.connect("clicked", lambda _b: self.get_clipboard().set(output))
        buttons.append(copy)
        full = Gtk.Button(label="Open full log")
        full.connect("clicked", lambda _b: open_uri(
            GLib.filename_to_uri(self.log_path)))
        buttons.append(full)
        box.append(buttons)

        view.set_content(box)
        dialog.set_child(view)
        dialog.present(self)

    @staticmethod
    def _scroll_to_end(text):
        buffer = text.get_buffer()
        text.scroll_to_iter(buffer.get_end_iter(), 0, False, 0, 1)
        return False

    def _check_details(self, event):
        dialog = Adw.AlertDialog(
            heading="%s — %s" % (event.get("group", ""), event.get("title", "")),
            body=event.get("why", ""))
        fix = event.get("fix", "")
        if fix:
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            box.append(Gtk.Label(label="This should fix it, run in a terminal "
                                       "from the aura-glass folder:",
                                 wrap=True, xalign=0))
            entry = Gtk.Entry(text=fix, editable=False)
            entry.add_css_class("monospace")
            box.append(entry)
            dialog.set_extra_child(box)
            dialog.add_response("copy", "Copy command")
        dialog.add_response("close", "Close")
        dialog.set_default_response("close")
        dialog.set_close_response("close")

        def response(_d, answer):
            if answer == "copy":
                self.get_clipboard().set(fix)

        dialog.connect("response", response)
        dialog.present(self)

    def _on_check_again(self, button):
        if not self.repo or self.verifying:
            return
        self.verifying = True
        button.set_sensitive(False)
        button.set_label("Checking…")
        try:
            proc = Gio.Subprocess.new(
                ["bash", os.path.join(self.repo, "install.sh"), "--verify",
                 "--progress-dir", self.dir],
                Gio.SubprocessFlags.STDOUT_SILENCE
                | Gio.SubprocessFlags.STDERR_SILENCE
                | Gio.SubprocessFlags.STDIN_INHERIT)
        except GLib.Error as exc:
            print("aura-glass: --verify failed to start: %s" % exc.message,
                  file=sys.stderr)
            self._verified(button)
            return
        proc.wait_async(None, lambda _p, _r: self._verified(button))

    def _verified(self, button):
        self.verifying = False
        button.set_sensitive(True)
        button.set_label("Check again")
        self.poll()
        if self.finished in ("ok", "warn"):
            bad = any(c["status"] != "ok" for c in self.checks)
            failed_steps = any(self.steps[i].status in ("warn", "fail")
                               for i in self.order)
            status = "warn" if bad or failed_steps else "ok"
            icon, css, heading, text = FINISHED[status]
            self.heading.set_label(heading)
            self.current.set_label(text)
            self.hero_image.set_from_icon_name(icon)
            for name in ("success", "warning", "error"):
                self.hero_image.remove_css_class(name)
            self.hero_image.add_css_class(css)

    def _on_logout(self, _button):
        # The same command prompt_logout runs, and the same fallback.
        for argv in (["gnome-session-quit", "--logout", "--no-prompt"],
                     ["loginctl", "terminate-session",
                      os.environ.get("XDG_SESSION_ID", "self")]):
            try:
                subprocess.Popen(argv, start_new_session=True)
                return
            except OSError:
                continue


class Application(Adw.Application):
    def __init__(self, run_dir, update=False):
        # NON_UNIQUE for the setup wizard's reason: a window left over from an
        # earlier run must not swallow this one's activation.
        super().__init__(application_id=APP_ID,
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.run_dir = run_dir
        self.update = update

    def do_activate(self):
        window = self.get_active_window()
        if window is None:
            provider = Gtk.CssProvider()
            provider.load_from_data(CSS)
            # Above the user's gtk.css, which is Aura Glass's own and sizes
            # every button: the cards' small buttons would lose to it.
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(), provider,
                Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)
            window = Window(self, self.run_dir, self.update)
        window.present()


def main():
    parser = argparse.ArgumentParser(
        description="Shows a full aura-glass install's progress, checklist and "
                    "log out screen, from the files lib/progress.sh writes.")
    parser.add_argument("--dir", required=True,
                        help="the run's directory: events, log")
    parser.add_argument("--update", action="store_true",
                        help="an update: show changelog.json from --dir above "
                             "the progress, and the log live below it")
    opts = parser.parse_args()
    if not os.path.isdir(opts.dir):
        print("aura-glass: no such run directory: %s" % opts.dir,
              file=sys.stderr)
        return 1
    app = Application(opts.dir, opts.update)
    return app.run([sys.argv[0]])


if __name__ == "__main__":
    sys.exit(main())
