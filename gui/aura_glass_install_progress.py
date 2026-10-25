#!/usr/bin/env python3
"""aura-glass — a full install's progress, in a window beside its terminal.

lib/progress.sh opens this, detached, when the setup wizard started the run or
--progress-window asked for it. The terminal stays the installer: sudo and
every question are still asked there, and this window says so whenever the
terminal is waiting. What it adds is the overview:

  while the install runs   a progress bar, the step running now and the last
                           line it printed, and the checklist of steps filling
                           in as each one ends
  when it ends             the checklist with verify_install's checks under it,
                           a "Why?" on everything that did not go cleanly (what
                           the step reported, and its part of the log), "Check
                           again", and the log out screen

With --update it is the settings window's update window instead: the
changelog the settings window wrote to changelog.json above, the bar in the
middle, and the log live at the bottom (docs/GUI.md §2b).

The contract is the two files in --dir, described at the top of
lib/progress.sh. This reads them and writes one file of its own, `window`, its
pid, which is how prompt_logout knows to leave the logout to this window. It
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
from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

APP_ID = "io.github.DevWebeloper.AuraGlassInstall"

# How often the two files are read. Appended to by a shell script a few times a
# second at most, so polling is simpler than a file monitor and as quick.
POLL_MS = 250

# The most of a step's log a "Why?" shows. A font or icon pack download can
# print a lot; the end of it is where the failure is.
LOG_TAIL_BYTES = 200_000

# The bar is green whatever the accent: it says "this is going well", and a red
# accent made a healthy install read like a failing one.
CSS = b"""
progressbar.install-progress > trough > progress {
    background-color: @success_color;
}
"""

ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07|\x1b[()][A-Z0-9]")

STATUS_ICONS = {
    "pending": ("content-loading-symbolic", "dim-label"),
    "ok": ("object-select-symbolic", "success"),
    "warn": ("dialog-warning-symbolic", "warning"),
    "fail": ("dialog-error-symbolic", "error"),
    "skip": ("action-unavailable-symbolic", "dim-label"),
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


def clean(text):
    return ANSI.sub("", text).replace("\r", "")


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
        self.row = None
        self.prefix = None
        self.button = None


class Window(Adw.ApplicationWindow):
    def __init__(self, app, run_dir, update=False):
        super().__init__(application=app, title="Aura Glass",
                         default_width=640 if update else 600,
                         default_height=820 if update else 720)
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
        self.changelog = self._read_changelog() if update else {}

        self._write_pid()
        self._build()
        self.poll()
        self._timer = GLib.timeout_add(POLL_MS, self.poll)
        self.connect("close-request", self._on_close)

    # ---- files ---------------------------------------------------------------

    def _write_pid(self):
        try:
            with open(os.path.join(self.dir, "window"), "w") as handle:
                handle.write("%d\n" % os.getpid())
        except OSError:
            pass

    def _on_close(self, _window):
        try:
            os.unlink(os.path.join(self.dir, "window"))
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
        if self.log_view is not None:
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
                self.checks_group.remove(check["row"])
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

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18,
                       margin_top=18, margin_bottom=18,
                       margin_start=12, margin_end=12)

        # The bar, the step running now and, when it ends, the outcome. On
        # top of the checklist for an install; between the changelog and the
        # live log for an update, which is the layout that page asks for.
        size = 32 if self.update else 48
        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL,
                       spacing=6 if self.update else 8)
        self.hero_icon = Gtk.Stack()
        spinner = Adw.Spinner(width_request=size, height_request=size)
        self.hero_icon.add_named(spinner, "running")
        self.hero_image = Gtk.Image(pixel_size=size)
        self.hero_icon.add_named(self.hero_image, "done")
        hero.append(self.hero_icon)

        self.heading = Gtk.Label(
            label="Updating Aura Glass" if self.update
            else "Installing Aura Glass",
            wrap=True, justify=Gtk.Justification.CENTER)
        self.heading.add_css_class("title-4" if self.update else "title-2")
        hero.append(self.heading)

        self.current = Gtk.Label(label="Starting…", wrap=True,
                                 justify=Gtk.Justification.CENTER)
        self.current.add_css_class("dim-label")
        hero.append(self.current)

        self.bar = Gtk.ProgressBar(show_text=True, margin_top=6)
        self.bar.add_css_class("install-progress")
        hero.append(self.bar)

        self.last_line = Gtk.Label(label="", xalign=0,
                                   ellipsize=Pango.EllipsizeMode.END,
                                   visible=not self.update)
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

        if self.update:
            self._build_changelog(body)
        else:
            body.append(hero)

        self.steps_group = Adw.PreferencesGroup(title="Steps")
        body.append(self.steps_group)

        self.checks_group = Adw.PreferencesGroup(
            title="Checks",
            description="What is on disk and in your settings now.")
        self.check_again = Gtk.Button(label="Check again",
                                      valign=Gtk.Align.CENTER)
        self.check_again.add_css_class("flat")
        self.check_again.connect("clicked", self._on_check_again)
        self.checks_group.set_header_suffix(self.check_again)
        self.checks_group.set_visible(False)
        body.append(self.checks_group)

        clamp = Adw.Clamp(maximum_size=560, child=body)
        scroller = Gtk.ScrolledWindow(child=clamp, vexpand=True,
                                      hscrollbar_policy=Gtk.PolicyType.NEVER)
        if self.update:
            # Changelog above, progress in the middle, the log at the bottom,
            # live: the update window shows its output rather than hiding it
            # behind a button, since following it is the point of the window.
            column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            column.append(scroller)
            column.append(Gtk.Separator())
            column.append(Adw.Clamp(maximum_size=560, child=hero,
                                    margin_top=12, margin_bottom=12,
                                    margin_start=12, margin_end=12))
            self.log_view = Gtk.TextView(
                editable=False, cursor_visible=False, monospace=True,
                wrap_mode=Gtk.WrapMode.WORD_CHAR, top_margin=6,
                bottom_margin=6, left_margin=10, right_margin=10)
            self.log_view.add_css_class("caption")
            self.log_scroller = Gtk.ScrolledWindow(child=self.log_view,
                                                   min_content_height=170)
            self.log_scroller.add_css_class("view")
            column.append(Gtk.Separator())
            column.append(self.log_scroller)
            view.set_content(column)
        else:
            view.set_content(scroller)

        bottom = Gtk.Box(spacing=12, margin_top=12, margin_bottom=12,
                         margin_start=12, margin_end=12)
        log_button = Gtk.Button(label="Show log")
        log_button.connect("clicked", self._on_show_log)
        if self.update:
            log_button.set_label("Open log")
            log_button.disconnect_by_func(self._on_show_log)
            log_button.connect("clicked", lambda _b: open_uri(
                GLib.filename_to_uri(self.log_path)))
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

    def _update_span(self):
        old, new = self.changelog.get("from"), self.changelog.get("to")
        if old and new:
            return "%s → %s" % (old, new)
        return new or ""

    def _build_changelog(self, body):
        """One group per release the update brings, newest first."""
        sections = self.changelog.get("sections") or []
        intro = Adw.PreferencesGroup(
            title="What's new",
            description=(
                "%d release%s and the commits after them, from %s to %s."
                % (len(sections), "" if len(sections) == 1 else "s",
                   self.changelog.get("from") or "your version",
                   self.changelog.get("to") or "the newest")
                if sections else
                "Nothing new between the installed version and this one — "
                "the update reinstalls it, or goes back to it."))
        body.append(intro)
        for section in sections:
            count = section.get("count") or 0
            group = Adw.PreferencesGroup(
                title=GLib.markup_escape_text(section.get("title", "")),
                description="%s · %d commit%s" % (
                    section.get("date", ""), count, "" if count == 1 else "s"))
            label = Gtk.Label(xalign=0, wrap=True, selectable=True,
                              margin_top=12, margin_bottom=12,
                              margin_start=12, margin_end=12)
            try:
                label.set_markup(section.get("markup", ""))
            except GLib.Error:
                label.set_text(clean(section.get("markup", "")))
            card = Gtk.Box()
            card.add_css_class("card")
            card.append(label)
            group.add(card)
            body.append(group)

    def _add_step(self, ident, title):
        if ident in self.steps:
            return
        step = Step(ident, title)
        step.row = Adw.ActionRow(title=GLib.markup_escape_text(title))
        step.prefix = Gtk.Stack()
        step.prefix.add_named(Adw.Spinner(), "running")
        step.prefix.add_named(Gtk.Box(), "icon")
        step.row.add_prefix(step.prefix)
        step.button = Gtk.Button(label="Details", valign=Gtk.Align.CENTER,
                                 visible=False)
        step.button.add_css_class("flat")
        step.button.connect("clicked", lambda _b, s=step: self._step_details(s))
        step.row.add_suffix(step.button)
        self.steps_group.add(step.row)
        self.steps[ident] = step
        self.order.append(ident)
        self._refresh_step(step)

    def _refresh_step(self, step):
        if step.status == "running":
            step.prefix.set_visible_child_name("running")
        else:
            old = step.prefix.get_child_by_name("icon")
            step.prefix.remove(old)
            step.prefix.add_named(status_icon(step.status), "icon")
            step.prefix.set_visible_child_name("icon")

        subtitle = ""
        problems = [text for level, text in step.notes
                    if level in ("warn", "error")]
        if step.status == "running":
            subtitle = "Running…"
        elif step.status == "fail":
            subtitle = problems[-1] if problems else "Stopped here"
        elif step.status == "warn":
            subtitle = problems[0] if problems else ""
            if len(problems) > 1:
                subtitle += " (and %d more)" % (len(problems) - 1)
        elif step.status == "skip":
            infos = [text for level, text in step.notes if level == "info"]
            # Without a reason, every line it printed was a skip: what it
            # would install was already there.
            subtitle = infos[0] if infos else "Already in place"
        step.row.set_subtitle(GLib.markup_escape_text(subtitle))

        step.button.set_visible(step.status not in ("pending", "running"))
        step.button.set_label("Why?" if step.status in ("warn", "fail")
                              else "Details")

    def _add_check(self, event):
        status = event.get("status", "ok")
        title = "%s — %s" % (event.get("group", ""), event.get("title", ""))
        row = Adw.ActionRow(title=GLib.markup_escape_text(title))
        row.add_prefix(status_icon(status))
        if status != "ok":
            row.set_subtitle(GLib.markup_escape_text(event.get("why", "")))
            button = Gtk.Button(label="Why?", valign=Gtk.Align.CENTER)
            button.add_css_class("flat")
            button.connect("clicked", lambda _b, e=event: self._check_details(e))
            row.add_suffix(button)
        self.checks_group.add(row)
        self.checks_group.set_visible(True)
        self.checks.append({"row": row, "status": status})

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
        self.bar.set_fraction(min(fraction, 1.0))
        self.bar.set_text("%d of %d" % (done, total))

    def _finish(self, event):
        if self.finished is not None:
            return
        status = event.get("status", "ok")
        if status not in FINISHED:
            status = "fail"
        if status == "ok" and any(c["status"] != "ok" for c in self.checks):
            status = "warn"
        self.finished = status
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
        self.hero_icon.set_visible_child_name("done")
        self.heading.set_label(heading)
        self.current.set_label(text)
        self.last_line.set_visible(False)
        self.hint.set_visible(False)
        self.banner.set_revealed(False)
        self.title.set_title("Aura Glass")
        self.title.set_subtitle(self._update_span() if self.update else "")

        can_log_out = status != "fail" and not self.dry
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
                    {"warn": "warn", "error": "fail"}.get(level, "skip")))
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

    def _on_show_log(self, _button):
        dialog = Adw.Dialog(title="Install log", content_width=720,
                            content_height=600)
        view = Adw.ToolbarView()
        header = Adw.HeaderBar()
        opener = Gtk.Button(label="Open in editor")
        opener.connect("clicked", lambda _b: open_uri(
            GLib.filename_to_uri(self.log_path)))
        header.pack_start(opener)
        view.add_top_bar(header)
        text = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                            wrap_mode=Gtk.WrapMode.WORD_CHAR,
                            top_margin=8, bottom_margin=8,
                            left_margin=8, right_margin=8)
        text.get_buffer().set_text(read_range(self.log_path, 0))
        view.set_content(Gtk.ScrolledWindow(child=text, vexpand=True))
        dialog.set_child(view)
        dialog.present(self)
        GLib.idle_add(self._scroll_to_end, text)

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
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(), provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
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
