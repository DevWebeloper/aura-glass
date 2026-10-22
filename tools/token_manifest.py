"""Where every token in tokens/tokens.sh is written down.

This is the pairing list tokens.sh's per-token comments describe, in the form a
program can use. It exists as a module rather than inline in one script because
two tools need the same list and a second copy would be a second thing to
forget:

    tools/check-tokens.sh        reads it to assert the repo still agrees
    tools/apply-radius-preset.py reads it to rewrite an *installed* copy

The checker is why the list is trustworthy; the writer is why it has to be
complete. A radius site missing from here is not merely unchecked — it is a
corner that keeps the shipped value while every corner around it moves, which
is the exact "two stacked surfaces" fault tokens.sh was written to prevent.

Each entry is (token name, kind, *args).

  css: (file, regex) — every capture group of every match must equal the token.
       The regex MUST match at least once; a regex that has stopped matching
       because a selector was renamed is a silently-passing check, which is
       worse than no check, so that is a failure too.

       For the writer, each capture group's span is the text it substitutes, so
       a group must wrap the number and nothing else.

  ini: (file, section, key) — the key's value in that section must equal the
       token. Section-scoped because corner-radius and sigma both appear under
       several Blur My Shell components with different values.

  raw: (file, regex) — checked exactly like css, and deliberately not returned
       by css_entries(). It is for a value buried inside one dconf key rather
       than standing on its own as a key of its own: Blur My Shell keeps every
       pipeline in a single GVariant blob under `pipelines`, and a corner effect
       inside it is a radius the section/key form cannot reach. The writer for
       these is apply_radius_dconf, which reads the live key rather than a file
       in $CONF_DIR — which is why apply-radius-preset.py must not see them.

The `[^}]*?` in the CSS patterns cannot cross a closing brace, so each one stays
inside the rule its selector opened.
"""

MANIFEST = [
    ("TOKEN_RADIUS_WINDOW", "css", "css/gtk3-tweaks.css",
     r"^decoration \{[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_WINDOW", "css", "css/gtk3-tweaks.css",
     r"^\.titlebar,\n\.titlebar\.background \{[^}]*?"
     r"border-top-left-radius: (\d+)px;\s*border-top-right-radius: (\d+)px"),
    # GTK4's window corner. Upstream Tahoe-Dark already paints
    # `window { border-radius: 30px }`, which is why this sheet did not restate
    # it for a long time — at the shipped value it is a duplicate. It is stated
    # now because a radius preset that moves every other corner has to move this
    # one too, and the theme's copy is not ours to rewrite: our block is
    # appended after the theme's rule at equal specificity, so it wins there.
    # A maximized or fullscreen window is squared by the rule after it in the
    # same sheet, which this pattern deliberately does not reach.
    ("TOKEN_RADIUS_WINDOW", "css", "css/gtk4-70-surfaces.css",
     r"^window,\nwindow\.background,\nwindow\.csd \{[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_WINDOW", "ini", "dconf/core.ini",
     "blur-my-shell/applications", "corner-radius"),

    ("TOKEN_RADIUS_MENU", "css", "css/shell-20-popup-menus.css",
     r"^\.popup-menu-content(?:,[^{]*)? \{[^}]*?border-radius: (\d+)px"),
    # The popup-blur sheet restates the menu radius at !important. Its own header
    # said for a long time that it "deliberately sets no border-radius" — that
    # was true when it was written and stopped being true in 4790bfc, which is
    # precisely the drift this manifest exists to make impossible. It went
    # unnoticed because no entry here covered the file at all.
    ("TOKEN_RADIUS_MENU", "css", "css/shell-popup-blur.css",
     r"^\.popup-menu-content,\n\.background-menu \.popup-menu-content \{"
     r"[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_MENU", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "menu-corner-radius"),

    ("TOKEN_RADIUS_QUICK_SETTINGS", "css", "css/shell-20-popup-menus.css",
     r"^\.datemenu-popover,\n\.quick-toggle-menu \{[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_QUICK_SETTINGS", "css", "css/shell-20-popup-menus.css",
     r"^\.popup-menu-content\.quick-settings,[^}]*?border-radius: (\d+)px"),
    # The popup-blur sheet has to restate the date menu's, quick-toggle menu's
    # and Quick Settings' radius as well as the menu one: it is spliced last,
    # and its .popup-menu-content rule otherwise wins and repaints them at the
    # menu radius. Same drift the entry above this group describes, one selector over.
    ("TOKEN_RADIUS_QUICK_SETTINGS", "css", "css/shell-popup-blur.css",
     r"^\.datemenu-popover,\n\.quick-toggle-menu \{[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_QUICK_SETTINGS", "css", "css/shell-popup-blur.css",
     r"^\.popup-menu-content\.quick-settings,[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_QUICK_SETTINGS", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "quick-settings-corner-radius"),

    ("TOKEN_RADIUS_NOTIFICATION", "css", "css/shell-30-notifications.css",
     r"^(?:\.popup-menu \.message,\s*)?\.message \{[^}]*?border-radius: (\d+)px"),
    # The stacked cards that peek out behind the top one. They are the same card
    # shape, so they take the same corner — and unlike the two above, nothing
    # rounds a blur behind them, which is why they were missed here at first:
    # they have no dconf counterpart to disagree with. What they can disagree
    # with is .message itself, and a stack peeking out at the shipped 20 behind
    # a card at 8 reads as a rendering fault.
    ("TOKEN_RADIUS_NOTIFICATION", "css", "css/shell-30-notifications.css",
     r"^\.popup-menu \.message:second-in-stack,\n\.message:second-in-stack \{"
     r"[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_NOTIFICATION", "css", "css/shell-30-notifications.css",
     r"^\.popup-menu \.message:lower-in-stack,\n\.message:lower-in-stack \{"
     r"[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_NOTIFICATION", "css", "css/shell-30-notifications.css",
     r"^\.notification-banner \{[^}]*?border-radius: (\d+)px"),
    # Solid mode repaints both stacked states to give them an opaque ground, and
    # restates the radius while it is there. Same shape, same token — a stack
    # that squares off only when --no-blur is passed would be a fault that only
    # showed up on the machines least likely to be screenshotted.
    ("TOKEN_RADIUS_NOTIFICATION", "css", "css/shell-80-solid.css",
     r"^\.popup-menu \.message:second-in-stack,\n\.message:second-in-stack \{"
     r"[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_NOTIFICATION", "css", "css/shell-80-solid.css",
     r"^\.popup-menu \.message:lower-in-stack,\n\.message:lower-in-stack \{"
     r"[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_NOTIFICATION", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "notification-corner-radius"),

    ("TOKEN_RADIUS_DIALOG", "css", "css/shell-50-dialogs.css",
     r"^\.modal-dialog,[^}]*?border-radius: (\d+)px"),
    ("TOKEN_RADIUS_DIALOG", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "dialog-corner-radius"),

    ("TOKEN_RADIUS_POPUP", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "corner-radius"),
    ("TOKEN_RADIUS_OSD", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "osd-corner-radius"),

    # The blur behind an app window is rounded twice over: once by
    # [applications] corner-radius above, and once by the corner effect in the
    # `windows` pipeline that same component names. Only the first was ever
    # moved by a preset, so a soft desktop had its blur rounded at 16 by one and
    # at 30 by the other — the exact "two stacked surfaces at different radii"
    # fault this file exists to prevent, in one component. Matched by pipeline
    # name rather than by its generated id, which is a machine's own and not a
    # thing to hard-code.
    ("TOKEN_RADIUS_WINDOW", "raw", "dconf/core.ini",
     r"'name': <'windows'>, 'effects': <\[.*?'type': <'corner'>, "
     r"'id': <'[^']*'>, 'params': <\{'radius': <(\d+)>"),

    # No ini entry: buttons have no Blur My Shell component to disagree with,
    # the same way TOKEN_RADIUS_OSD has no css/ site — one direction each.
    ("TOKEN_RADIUS_BUTTON", "css", "css/gtk4-20-buttons.css",
     r"^button\.text-button,\nbutton\.flat\.text-button,\nbutton\.pill,\n"
     r"button\.suggested-action,\nbutton\.destructive-action \{"
     r"[^}]*?border-radius: (\d+)px"),

    ("TOKEN_SIGMA_PANEL", "ini", "dconf/core.ini",
     "blur-my-shell/panel", "sigma"),
    ("TOKEN_SIGMA_APPFOLDER", "ini", "dconf/core.ini",
     "blur-my-shell/appfolder", "sigma"),
    ("TOKEN_SIGMA_POPUP", "ini", "dconf/core.ini",
     "blur-my-shell/popup", "sigma"),
    ("TOKEN_SIGMA_WINDOW_LIST", "ini", "dconf/core.ini",
     "blur-my-shell/window-list", "sigma"),
    ("TOKEN_SIGMA_APPLICATIONS", "ini", "dconf/core.ini",
     "blur-my-shell/applications", "sigma"),
    ("TOKEN_SIGMA_DASH_TO_DOCK", "ini", "dconf/core.ini",
     "blur-my-shell/dash-to-dock", "sigma"),

    ("TOKEN_APP_TRANSPARENCY_SHIPPED", "css", "css/gtk4-transparency.css",
     r"alpha\(@tg_tint_window, ([0-9.]+)\)"),
    # Both spellings of the tint, and the mix() weight is the complement.
    ("TOKEN_APP_TINT", "css", "css/gtk4-transparency.css",
     r"var\(--window-bg-color\) (\d+)%, #000000"),
    # The prose in the sheet's own header states the baseline too. A stale
    # comment here is how the next person picks the wrong number by hand.
    ("TOKEN_APP_TRANSPARENCY_SHIPPED", "css", "css/gtk4-transparency.css",
     r"the shipped level, ([0-9.]+)\."),
]

# Sheets install_css installs conditionally, so a writer pointed at $CONF_DIR
# must tolerate their absence — while the checker, which reads css/, must not,
# because in the repo they are always there.
#
#   shell-80-solid.css         installed only for --no-blur
#   shell-popup-blur.css       installed only while popup blur is on
#   shell-notification-blur.css  installed only while notification blur is on
#
# Every other sheet the manifest names is installed unconditionally, so a missing
# one means an incomplete install and stays a hard error.
OPTIONAL_SHEETS = {
    "shell-80-solid.css",
    "shell-popup-blur.css",
    "shell-notification-blur.css",
}

# The radius tokens, in the order install.sh and the GUI pass them around. The
# writer takes its values positionally, so this order is the interface between
# radius_preset_values() in tokens/tokens.sh and apply-radius-preset.py.
RADIUS_TOKENS = [
    "TOKEN_RADIUS_WINDOW",
    "TOKEN_RADIUS_MENU",
    "TOKEN_RADIUS_QUICK_SETTINGS",
    "TOKEN_RADIUS_NOTIFICATION",
    "TOKEN_RADIUS_DIALOG",
    "TOKEN_RADIUS_POPUP",
    "TOKEN_RADIUS_OSD",
    "TOKEN_RADIUS_BUTTON",
]


def css_entries(tokens=None):
    """Every css entry, optionally narrowed to a set of token names.

    `raw` entries are not css entries and are not returned here on purpose: a
    stylesheet rewriter pointed at one would look for dconf/core.ini in
    $CONF_DIR and report an incomplete install. See the module docstring.
    """
    return [e for e in MANIFEST
            if e[1] == "css" and (tokens is None or e[0] in tokens)]


def raw_entries(tokens=None):
    """Every raw (file, regex) entry, optionally narrowed to token names."""
    return [e for e in MANIFEST
            if e[1] == "raw" and (tokens is None or e[0] in tokens)]


def ini_entries(tokens=None):
    """Every ini entry, optionally narrowed to a set of token names."""
    return [e for e in MANIFEST
            if e[1] == "ini" and (tokens is None or e[0] in tokens)]
