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
what lib/distro.sh probes for is what this is allowed to need.
"""
import argparse
import json
import os
import subprocess
import sys

import gi

gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

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
}

# How each pack spells its own name, for the summary. .capitalize() was doing
# this and gets two of the five wrong — "Mactahoe" and "Aosp" are neither what
# the projects call themselves nor what the pages above say.
PACK_NAMES = {
    "colloid": "Colloid",
    "reversal": "Reversal",
    "hatter": "Hatter",
    "adwaita": "Adwaita",
    "aosp": "AOSP",
    "mactahoe": "MacTahoe",
}

# The pages, in order. Two of them do not always apply — see Window._applies.
PAGES = ["welcome", "accent", "blur", "blur-details", "icons", "cursors",
         "extensions", "gdm", "summary"]

# What Skip on each page puts back. Skip is not "leave whatever I clicked", it
# is "I did not want to decide this" — so it restores the defaults for the
# fields that page owns and moves on.
PAGE_FIELDS = {
    "accent": ("accent", "font"),
    "blur": ("blur",),
    "blur-details": ("popup_blur", "scope", "transparency"),
    "icons": ("want_icons", "icons"),
    "cursors": ("want_cursors", "cursors"),
    "extensions": ("want_osd", "extensions"),
    "gdm": ("gdm", "gdm_monitors"),
}

CSS = b"""
.accent-swatch {
    min-width: 40px;
    min-height: 40px;
    padding: 0;
    border-radius: 50%;
    background-image: none;
    box-shadow: none;
    border: 3px solid transparent;
}
.accent-swatch:checked {
    border-color: alpha(currentColor, 0.55);
}
.wizard-swatches {
    padding: 6px 0;
}
"""


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
    Gio.AppInfo.launch_default_for_uri(uri, None)


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
        self.blur = True
        self.popup_blur = True
        self.scope = "gtk"          # gtk | all | none
        self.transparency = "0.90"
        self.want_icons = True
        # The recommended pair, and the wizard's defaults. Both go out as an
        # explicit --icons/--cursors, so install.sh's own flagless defaults
        # (colloid and adwaita) are untouched by this — the wizard states its
        # answer rather than relying on one.
        self.icons = "hatter"
        self.want_cursors = True
        self.cursors = "aosp"
        self.want_osd = True
        # None means "say nothing about extensions", which leaves install.sh on
        # the recommended pack. Only a readable catalogue turns this into a list.
        self.extensions = extensions
        self.gdm = False
        self.gdm_monitors = False

    def copy(self):
        clone = Answers.__new__(Answers)
        clone.__dict__.update(self.__dict__)
        if isinstance(self.extensions, list):
            clone.extensions = list(self.extensions)
        return clone

    def to_argv(self, gdm_present):
        args = ["--accent", self.accent, "--font", self.font]

        if not self.blur:
            # Solid mode is the absence of every blur and has to go out alone:
            # install.sh rejects --no-blur beside any blur flag by design, and
            # it sets the transparency to opaque itself.
            args.append("--no-blur")
        else:
            if self.scope == "none":
                args.append("--no-window-blur")
            elif self.scope == "all":
                args.append("--all-apps-blur")
            else:
                args.append("--gtk-apps-blur")
            # After the scope flag, not before: --no-window-blur picks a
            # transparency of its own only when nothing explicit has said one.
            args += ["--app-transparency", self.transparency]
            args.append("--popup-blur" if self.popup_blur else "--no-popup-blur")

        if self.want_icons:
            args += ["--icons", self.icons]
        else:
            args.append("--no-icons")

        if self.want_cursors:
            args += ["--cursors", self.cursors]
        else:
            args.append("--no-cursors")

        args.append("--osd" if self.want_osd else "--no-osd")

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
    def __init__(self, app, repo, gdm_present):
        super().__init__(application=app, title="aura-glass Setup",
                         default_width=680, default_height=620)
        self.repo = repo
        self.gdm_present = gdm_present
        self.catalogue = ext_catalogue(repo)

        recommended = [e["uuid"] for e in self.catalogue
                       if e["tier"] == "recommended"] or None
        self.answers = Answers(recommended)
        self.defaults = self.answers.copy()

        self.nav = Adw.NavigationView()
        self.nav.add(self.build_page("welcome"))
        self.set_content(self.nav)

    # ---- navigation ---------------------------------------------------------

    def applies(self, tag):
        if tag == "blur-details":
            # Nothing to detail about a blur that is not there.
            return self.answers.blur
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
        self.advance(tag)

    def build_page(self, tag):
        return getattr(self, "page_" + tag.replace("-", "_"))()

    def finish(self):
        self.get_application().result = self.answers.to_argv(self.gdm_present)
        self.close()

    # ---- page furniture -----------------------------------------------------

    def shell(self, tag, title, content, *, skippable=True, next_label="Next",
              on_next=None):
        """One page: a header, the content, and the buttons along the bottom."""
        view = Adw.ToolbarView()
        view.add_top_bar(Adw.HeaderBar())
        view.set_content(content)

        bar = Gtk.ActionBar()
        if skippable:
            button = Gtk.Button(label="Skip")
            button.add_css_class("flat")
            button.set_tooltip_text("Keep the default and move on")
            button.connect("clicked", lambda _b: self.skip(tag))
            bar.pack_start(button)

        nxt = Gtk.Button(label=next_label)
        nxt.add_css_class("suggested-action")
        nxt.connect("clicked",
                    lambda _b: (on_next or self.advance)(tag))
        bar.pack_end(nxt)
        view.add_bottom_bar(bar)

        return Adw.NavigationPage(child=view, title=title, tag=tag)

    def radio_rows(self, group, options, current, on_pick):
        """A radio list. options: (value, title, subtitle, link or None)."""
        first = None
        for value, title, subtitle, link in options:
            row = plain_row(Adw.ActionRow(), title, subtitle)
            check = Gtk.CheckButton(valign=Gtk.Align.CENTER)
            if first is None:
                first = check
            else:
                check.set_group(first)
            check.set_active(value == current)

            def picked(button, value=value):
                if button.get_active():
                    on_pick(value)
            check.connect("toggled", picked)

            row.add_prefix(check)
            row.set_activatable_widget(check)

            if link:
                button = Gtk.Button(label="View on GitHub",
                                    valign=Gtk.Align.CENTER)
                button.add_css_class("flat")
                button.set_tooltip_text(link)
                button.connect("clicked", lambda _b, uri=link: open_link(uri))
                row.add_suffix(button)

            group.add(row)

    # ---- the pages ----------------------------------------------------------

    def page_welcome(self):
        # Not preferences-desktop-theme-symbolic, which reads like the obvious
        # choice and does not exist: no icon theme ships it, so GTK falls back
        # to the full-colour preferences-desktop-theme and the welcome page
        # opens on a tuxedo. This one is in stock Adwaita's categories rather
        # than its legacy set, which is what a machine has before any of this
        # is installed.
        status = Adw.StatusPage(
            icon_name="applications-graphics-symbolic",
            title="aura-glass",
            description="A few questions about how you want the desktop to "
                        "look, and then the terminal takes it from there.\n\n"
                        "None of this is permanent. Every choice here — and a "
                        "good many that are not — can be changed afterwards in "
                        "the aura-glass settings window, without reinstalling "
                        "anything.")

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                      halign=Gtk.Align.CENTER)
        start = Gtk.Button(label="Get Started")
        start.add_css_class("suggested-action")
        start.add_css_class("pill")
        start.connect("clicked", lambda _b: self.advance("welcome"))
        box.append(start)

        defaults = Gtk.Button(label="Skip all, use defaults")
        defaults.add_css_class("flat")
        defaults.set_tooltip_text(
            "Install the recommended look without answering anything")
        defaults.connect("clicked", lambda _b: self.finish())
        box.append(defaults)
        status.set_child(box)

        page = Adw.NavigationPage(child=Adw.ToolbarView(), title="Welcome",
                                  tag="welcome")
        view = page.get_child()
        view.add_top_bar(Adw.HeaderBar())
        view.set_content(status)
        return page

    def page_accent(self):
        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup(
            title="Accent colour",
            description="The colour the panel, the highlights and the icon "
                        "theme are built around. GNOME offers these nine and "
                        "no others — a colour of your own would repaint every "
                        "app window and none of the shell.")

        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE,
                           homogeneous=True, column_spacing=10,
                           row_spacing=10, min_children_per_line=5,
                           max_children_per_line=9, halign=Gtk.Align.CENTER)
        flow.add_css_class("wizard-swatches")

        first = None
        for name, label, hexcolour in ACCENTS:
            button = Gtk.ToggleButton(tooltip_text=label)
            button.add_css_class("accent-swatch")
            if first is None:
                first = button
            else:
                button.set_group(first)

            provider = Gtk.CssProvider()
            provider.load_from_data(
                ("button.accent-swatch { background-color: %s; }" % hexcolour
                 ).encode("utf-8"))
            button.get_style_context().add_provider(
                provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

            mark = Gtk.Image(icon_name="object-select-symbolic")
            mark.set_visible(name == self.answers.accent)
            button.set_child(mark)
            button.set_active(name == self.answers.accent)

            def picked(toggle, name=name, mark=mark):
                mark.set_visible(toggle.get_active())
                if toggle.get_active():
                    self.answers.accent = name
            button.connect("toggled", picked)

            flow.append(button)

        row = Adw.PreferencesRow(activatable=False, child=flow)
        group.add(row)
        page.add(group)

        # On this page rather than one of its own: it is the second half of the
        # same question — what the desktop is built out of — and a page holding
        # one radio list would be a click for its own sake. The three fonts are
        # fetched during the install, not here.
        fonts = Adw.PreferencesGroup(
            title="Interface font",
            description="The font the whole desktop is set in: labels, menus, "
                        "titlebars and documents. Whichever one you pick keeps "
                        "the text size already set on this machine, and the "
                        "settings window can change it back afterwards.")
        self.radio_rows(fonts, [(v, t, sub, None) for v, t, sub in FONTS],
                        self.answers.font, self.set_font)
        page.add(fonts)

        return self.shell("accent", "Accent", page)

    def set_font(self, value):
        self.answers.font = value

    def page_blur(self):
        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup(
            title="Frosted glass, or solid",
            description="The blur is the look, and it is also the part that "
                        "costs a GPU something. Solid mode installs the same "
                        "theme with opaque surfaces instead of translucent "
                        "ones.")
        self.radio_rows(group, [
            ("frosted", "Frosted glass",
             "Blur behind the top bar, popups, menus and the volume pill",
             None),
            ("solid", "Solid",
             "No blur anywhere — lighter on older GPUs and on battery", None),
        ], "frosted" if self.answers.blur else "solid",
            lambda value: setattr(self.answers, "blur", value == "frosted"))
        page.add(group)
        return self.shell("blur", "Blur", page)

    def page_blur_details(self):
        page = Adw.PreferencesPage()

        popup = Adw.PreferencesGroup(title="Popups and menus")
        row = Adw.SwitchRow(
            title="Blur behind popups, menus and the top bar",
            subtitle="Off leaves them flat and translucent instead",
            active=self.answers.popup_blur)
        row.connect("notify::active", lambda r, _p: setattr(
            self.answers, "popup_blur", r.get_active()))
        popup.add(row)
        page.add(popup)

        scope = Adw.PreferencesGroup(
            title="Blur behind app windows",
            description="Every blurred window is work the compositor does on "
                        "every frame, which is why this is a separate question "
                        "from the one above.")
        self.radio_rows(scope, [
            ("gtk", "GTK and GNOME apps",
             "Files, Settings, Console and the rest — light on the CPU", None),
            ("all", "Every app window",
             "Browsers, Electron apps and games too — heavy on the CPU and GPU",
             None),
            ("none", "No window blur",
             "Windows stay crisp, with a touch of transparency and no cost",
             None),
        ], self.answers.scope, self.on_scope)
        page.add(scope)

        self.transparency_group = Adw.PreferencesGroup(
            title="Window transparency",
            description="How much of the desktop shows through a window.")
        self.radio_rows(self.transparency_group, [
            ("0.90", "90%", "The balanced look, and the default", None),
            ("0.82", "82%", "Deeper glass, more of the wallpaper", None),
            ("0.95", "95%", "Subtle, and the easiest to read text on", None),
        ], self.answers.transparency,
            lambda value: setattr(self.answers, "transparency", value))
        self.transparency_group.set_visible(self.answers.scope != "none")
        page.add(self.transparency_group)

        return self.shell("blur-details", "Blur detail", page)

    def on_scope(self, value):
        self.answers.scope = value
        # Without blur behind them, windows carry a lighter transparency than
        # any of the three levels — the same 95% the text wizard picks here,
        # and for the same reason: it is what stays readable unblurred.
        if value == "none":
            self.answers.transparency = "0.95"
        else:
            self.answers.transparency = self.defaults.transparency
        if hasattr(self, "transparency_group"):
            self.transparency_group.set_visible(value != "none")

    def page_icons(self):
        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup(
            title="Icon theme",
            description="All three are other people's work, fetched from "
                        "GitHub at a pinned commit. Have a look before you "
                        "pick one.")
        current = self.answers.icons if self.answers.want_icons else "keep"
        self.radio_rows(group, [
            ("hatter", "Hatter — recommended",
             "Rounded squares, follows your accent colour. By Mibea",
             PACK_LINKS["hatter"]),
            ("colloid", "Colloid",
             "Follows your accent colour. By vinceliuice",
             PACK_LINKS["colloid"]),
            ("reversal", "Reversal",
             "Round, flatter, a colour of its own. By yeyushengfan258",
             PACK_LINKS["reversal"]),
            ("keep", "Default",
             "Leaves your current icon theme alone, whatever set it", None),
        ], current, self.on_icons)
        page.add(group)
        return self.shell("icons", "Icons", page)

    def on_icons(self, value):
        self.answers.want_icons = value != "keep"
        if value != "keep":
            self.answers.icons = value

    def page_cursors(self):
        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup(
            title="Pointer theme",
            description="Adwaita is already on your machine — GNOME ships it. "
                        "AOSP and MacTahoe are fetched from GitHub.")
        current = self.answers.cursors if self.answers.want_cursors else "keep"
        self.radio_rows(group, [
            ("aosp", "AOSP — recommended",
             "Android's pointers, scalable with a soft shadow. By Tech-Tac",
             PACK_LINKS["aosp"]),
            ("adwaita", "Adwaita",
             "GNOME's own pointers, sharp at any size", None),
            ("mactahoe", "MacTahoe",
             "macOS Tahoe style pointers. By vinceliuice",
             PACK_LINKS["mactahoe"]),
            ("keep", "Default",
             "Leaves your current pointer theme alone, whatever set it", None),
        ], current, self.on_cursors)
        page.add(group)
        return self.shell("cursors", "Pointer", page)

    def on_cursors(self, value):
        self.answers.want_cursors = value != "keep"
        if value != "keep":
            self.answers.cursors = value

    def page_extensions(self):
        page = Adw.PreferencesPage()

        osd = Adw.PreferencesGroup(title="Volume and brightness")
        row = Adw.SwitchRow(
            title="Replace the volume and brightness popup with a pill",
            subtitle="A slim bar rather than GNOME's large square OSD",
            active=self.answers.want_osd)
        row.connect("notify::active", lambda r, _p: setattr(
            self.answers, "want_osd", r.get_active()))
        osd.add(row)
        page.add(osd)

        if not self.catalogue:
            group = Adw.PreferencesGroup(
                title="Extensions",
                description="The catalogue could not be read, so the "
                            "recommended set will be installed. You can change "
                            "it afterwards in the settings window.")
            group.add(Adw.ActionRow(
                title="bin/aura-glass-ext did not answer", sensitive=False))
            page.add(group)
            return self.shell("extensions", "Extensions", page)

        core = Adw.PreferencesGroup(
            title="Always installed",
            description="What the look is built out of. These are not "
                        "optional — without them there is no theme to see.")
        for entry in self.catalogue:
            if entry["tier"] != "core":
                continue
            core.add(plain_row(Adw.ActionRow(sensitive=False),
                               entry["description"], entry["uuid"]))
        page.add(core)

        actions = Adw.PreferencesGroup(
            title="Optional extensions",
            description="Everything below is a switch. The recommended set is "
                        "on to begin with; none of it is required, and all of "
                        "it can be changed later.")
        row = Adw.ActionRow(title="Select", subtitle="All at once")
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6,
                      valign=Gtk.Align.CENTER)
        for label, tiers in (("Recommended", ("recommended",)),
                             ("Everything", ("recommended", "full")),
                             ("None", ())):
            button = Gtk.Button(label=label)
            button.connect("clicked", self.on_ext_preset, tiers)
            box.append(button)
        row.add_suffix(box)
        actions.add(row)
        page.add(actions)

        self.ext_switches = []
        for tier, title, description in (
            ("recommended", "Recommended",
             "The set install.sh fits by default."),
            ("full", "Everything else",
             "Installed on request, one at a time."),
        ):
            group = Adw.PreferencesGroup(title=title, description=description)
            for entry in self.catalogue:
                if entry["tier"] != tier:
                    continue
                switch = plain_row(
                    Adw.SwitchRow(
                        active=entry["uuid"] in (self.answers.extensions or [])),
                    entry["description"], entry["uuid"])
                switch.connect("notify::active", self.on_ext_toggled,
                               entry["uuid"])
                self.ext_switches.append((entry["uuid"], switch))
                group.add(switch)
            page.add(group)

        return self.shell("extensions", "Extensions", page)

    def on_ext_toggled(self, row, _param, uuid):
        chosen = list(self.answers.extensions or [])
        if row.get_active():
            if uuid not in chosen:
                chosen.append(uuid)
        elif uuid in chosen:
            chosen.remove(uuid)
        self.answers.extensions = chosen

    def on_ext_preset(self, _button, tiers):
        chosen = [e["uuid"] for e in self.catalogue if e["tier"] in tiers]
        self.answers.extensions = chosen
        for uuid, row in self.ext_switches:
            row.set_active(uuid in chosen)

    def page_gdm(self):
        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup(
            title="Login screen",
            description="Both of these are system-wide rather than yours "
                        "alone, so the terminal will ask for your password "
                        "once it gets to them. Neither is needed for the "
                        "desktop itself.")

        theme = Adw.SwitchRow(
            title="Theme the GDM login screen",
            subtitle="Frosted glass at the login prompt, following your "
                     "desktop wallpaper",
            active=self.answers.gdm)
        theme.connect("notify::active", lambda r, _p: setattr(
            self.answers, "gdm", r.get_active()))
        group.add(theme)

        monitors = Adw.SwitchRow(
            title="Match the login screen to your monitor layout",
            subtitle="Worth having on a multi-monitor machine, where GDM "
                     "otherwise picks its own primary display",
            active=self.answers.gdm_monitors)
        monitors.connect("notify::active", lambda r, _p: setattr(
            self.answers, "gdm_monitors", r.get_active()))
        group.add(monitors)

        page.add(group)
        return self.shell("gdm", "Login screen", page)

    def page_summary(self):
        answers = self.answers
        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup(
            title="Ready to install",
            description="The window closes and the terminal takes over. It "
                        "will fetch a few things, so give it a minute.")

        if answers.blur:
            scope = {"gtk": "GTK and GNOME apps",
                     "all": "every app window",
                     "none": "no window blur"}[answers.scope]
            blur = "Frosted — %s, popups %s" % (
                scope, "blurred" if answers.popup_blur else "flat")
            transparency = "%d%%" % round(float(answers.transparency) * 100)
        else:
            blur = "Solid — no blur anywhere"
            transparency = "Opaque"

        if answers.extensions is None:
            extras = "The recommended set"
        elif answers.extensions:
            extras = "%d selected" % len(answers.extensions)
        else:
            extras = "None"

        rows = [
            ("Accent", answers.accent.capitalize()),
            ("Blur", blur),
            ("Window transparency", transparency),
            ("Icons", PACK_NAMES.get(answers.icons, answers.icons)
             if answers.want_icons else "Kept as they are"),
            ("Pointer", PACK_NAMES.get(answers.cursors, answers.cursors)
             if answers.want_cursors else "Kept as they are"),
            ("Volume pill", "Yes" if answers.want_osd else "GNOME's own OSD"),
            ("Optional extensions", extras),
        ]
        if self.gdm_present:
            rows.append(("Login screen",
                         "Themed" if answers.gdm else "Left alone"))
            rows.append(("Login screen monitors",
                         "Matched to yours" if answers.gdm_monitors
                         else "Left alone"))

        for title, value in rows:
            group.add(plain_row(Adw.ActionRow(), title, value))
        page.add(group)

        later = Adw.PreferencesGroup()
        later.add(plain_row(
            Adw.ActionRow(sensitive=False),
            "All of this can be changed later",
            "aura-glass Settings, from the Activities overview, without "
            "reinstalling anything"))
        page.add(later)

        return self.shell("summary", "Summary", page, skippable=False,
                          next_label="Install",
                          on_next=lambda _tag: self.finish())


class Application(Adw.Application):
    def __init__(self, repo, gdm_present):
        super().__init__(application_id=APP_ID,
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.repo = repo
        self.gdm_present = gdm_present
        # None until Install is pressed. Closing the window any other way
        # leaves it None, which is how cancelling is reported.
        self.result = None

    def do_activate(self):
        window = self.get_active_window()
        if window is None:
            provider = Gtk.CssProvider()
            provider.load_from_data(CSS)
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(), provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
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

    app = Application(opts.repo, opts.gdm_present)
    app.run([sys.argv[0]])

    if app.result is None:
        return 2
    for token in app.result:
        print(token)
    return 0


if __name__ == "__main__":
    sys.exit(main())
