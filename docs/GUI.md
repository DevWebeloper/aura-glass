# The GUI layer

Two GTK4 / libadwaita windows, both optional, both pure front ends for flags
`install.sh` already has. Neither writes a theme file.

If PyGObject or libadwaita is missing, the installer says so, skips the windows
and installs everything else normally. Nothing in the GUI is reachable only from
the GUI.

---

## `gui/aura_glass_setup_wizard.py` — the opening questions

Run by `install.sh` **before anything is installed**, via
`lib/steps-wizard.sh`.

### The contract

```
stdout   the flags install.sh should run with, one token per line.
         Nothing else may EVER be printed there.
stderr   anything worth saying to a human.
exit 0   answered.
exit 2   cancelled — install.sh stops, having changed nothing.
other    something broke; install.sh asks the same questions in the terminal,
         so a traceback costs a nicer wizard rather than the install.
```

`install.sh` **blocks** on it. The exit code and stdout are the entire point —
do not make it asynchronous.

### Parity

Every question here has a twin in `install.sh`'s terminal wizard (search for
`Step 1: Choose Accent Color`), which is what runs over SSH, on a machine
without PyGObject, or for someone who would rather not install one. **Adding a
question to one and not the other is a setting half your users on half their
machines are never offered.** Parity is a stated rule, not something code
enforces.

### Constraints

- It runs before there is an install: it is handed `--repo` by the script that
  launched it, rather than reconstructing a checkout path from a memo the way
  the settings window does.
- It imports PyGObject and nothing else — not even pycairo. What
  `lib/distro.sh` probes for is what this window is allowed to need.

Checked by `tools/check-wizard-flags.py`, which composes every command line the
wizard can produce and asserts `install.sh` accepts each one — including the
`--extensions` list its per-extension switches send.

---

## `gui/aura_glass_settings.py` — retuning afterwards

Launched from the Activities overview or `aura-glass-settings`. Refuses to open
without `$CONF_DIR`, and finds the checkout through `$CONF_DIR/repo-path` —
recorded rather than guessed, because by the time anyone opens the window the
shell it was installed from is long gone, and a wrong guess would mean Apply
silently reconfiguring from some other copy of the project.

### How Apply works

```
install.sh --settings-only --yes <only the flags that changed>
```

`Settings.__init__` reads the current answers out of `$CONF_DIR`;
`Settings.flags_against(other)` produces the arguments that turn one state into
another. **Only differences are sent**, because `install.sh` resolves an absent
flag from the memo it wrote last time. Sending the full set every time would
work, but would make every Apply an assertion about settings the user never
touched — which is how a GUI ends up undoing a CLI choice it never showed.

`--settings-only` is what makes this safe to drive from a window: it reapplies
the dconf preset, the CSS and the gsettings, and skips the theme, the extensions
and everything wanting root. No password, no terminal to answer a prompt in, and
no network — unless an icon pack, pointer pack or font row was changed, since
asking for a different one is asking for it to be installed. Those three rows
say so.

### Pages

`NAV_SECTIONS` is the list, and **its order is not only presentation**: the
builders run in it, so a page whose widgets another builder reads must come
first (Glass before Per-app blur — the per-app list asks the blur rows which
list is active).

| Page | Group | What it holds |
|---|---|---|
| Glass | Appearance | The three modes as three tabs; each tab shows only its own mode's tuning, read from that mode's drawer |
| Appearance | Appearance | Accent, icon and pointer packs, titlebar buttons and their style, interface font |
| Corner rounding | Appearance | Seven presets drawn as little windows wearing their own corners, a reset, or eight per-surface spin rows with a live drawing |
| Per-app blur | Appearance | A switch per installed app, an **Open now** list of live windows, a default for everything unchosen, a **Fullscreen performance games** list to trigger Performance mode when gaming, and a Patterns tab for wildcards |
| Extensions | System | Every catalogued extension with a switch and install/remove, plus the recommended and full packs |
| Packages | System | What each pack on disk costs, and removal |
| System | System | Dependencies, rounded-blur, panel blur fix, login screen, monitor sync |
| Updates | System | Version, check, install |
| Uninstall | *(none)* | The same three scopes `uninstall.sh` has |

Uninstall is built into the stack — `_reload` and `_mark_dirty` need every
widget to exist — but carries no sidebar row: a destructive page has no business
sitting in the same list as the rest. The primary menu opens it.

`SEARCH_INDEX` gives each page extra words it answers to, hand-kept rather than
walked off the built widgets, because several pages are not
`Adw.PreferencesPage` at all.

### What does not ride on Apply

**Extension switches.** Instant, reversible and unprivileged, but not settings
`install.sh` resolves — so they apply as they are clicked, through
`bin/aura-glass-ext`, streamed into the same in-window log Apply uses. The page
is built from `aura-glass-ext list` rather than a second Python copy of the
arrays; `tools/check-ext-catalogue.sh` keeps that command complete.

**The Packages page.** Removing a pack under `$HOME` is a filesystem delete with
no flag or memo behind it. A pack under `/usr` belongs to a package: the window
names the owning package and hands the removal command to a terminal, because
deleting a package's files out from under it leaves its database describing
files that are gone.

**Anything needing root** — the dependency install, `gnome-rounded-blur`, the
login screen, the monitor sync, the uninstall scopes. These **open a real
terminal**. `sudo` down a pipe that nothing can type into blocks forever; the
answer is not to run it in-window but to open a terminal with a keyboard
attached, and to say so rather than starting something that would silently
decline. If none of the terminals it knows is installed, it hands over the
command. Those rows report the last state the window read, not a live one — a
spawned terminal is deliberately not waited on.

`tools/check-terminal-spawn.py` asserts each terminal gets a runnable argv.
Whether one actually stays open is a thing only a desktop can answer.

### Live preview

`bin/aura-glass-preview` backs the sliders:

```
aura-glass-preview begin
aura-glass-preview set [--app-tint HEX] [--shell-tint HEX] [--transparency L]
                       [--radius-preset NAME] [--radius-custom W,M,Q,N,D,P,O]
                       [--blur-strength PCT] [--popup-blur 0|1]
                       [--popup-brightness PCT] [--notification-opacity PCT]
                       [--window-blur 0|1] [--scope gtk|all]
                       [--app-blur-allow LIST] [--app-blur-block LIST]
aura-glass-preview apps --allow LIST --block LIST [--window-blur 0|1] [--scope …]
aura-glass-preview revert
aura-glass-preview status
```

`begin` snapshots the installed sheets, the Blur My Shell dconf subtree and the
memos the functions below would overwrite. `set` then calls the **same**
`apply_*` functions `install.sh --settings-only` uses, against a CSS baseline
reset from `css/` on every call — the same reset `install_css` does, which is
what keeps a relative rewrite (transparency, shell tint) from compounding while
a slider is dragged.

`apps` is `set`'s per-app-only sibling: four dconf writes through
`apply_app_blur` and nothing else. Flipping a switch is not a reason to rebuild
the whole CSS pipeline.

**The one hard rule:** a preview must never leave a `$CONF_DIR` memo different
from what it was before `begin`. `Settings()` and the next real install must see
what was last actually applied, never a preview that happened to be showing.
`PREVIEW_MODE=1` makes `remembering()` false, so nothing is written and there is
nothing to restore and nothing to race. `tools/check-preview.sh` asserts it.

### The D-Bus bridge

"Open now" needs to know what windows exist, and an unprivileged GTK app on
Wayland has no way to ask. `extensions/aura-glass-blur@aura-glass.local` exports
`io.github.DevWebeloper.AuraGlass` with `ListWindows` and a `WindowsChanged`
signal; `ShellBridge` in the window is the client. The service is exported
whenever the extension is enabled, independent of whether Blur My Shell is
present — the window decides whether to use it by whether the bridge answers at
all.

### Accent, and why there is no colour picker

The accent row offers nine names and a button through to
`Settings → Appearance`, because the accent is **not this project's setting to
own**: the shell CSS reads `-st-accent-color` and the GTK CSS reads
`@accent_bg_color`, so GNOME already recolours the desktop live. The row exists
to keep the remembered value in step.

A custom hex is not on offer, and that looks like an omission. `-st-accent-color`
is not a property St will let anything assign: it is a read-only keyword backed
by the C enum `StSystemAccentColor`, resolved from the gsetting. GTK4's
`@accent_bg_color` *is* an ordinary named colour and would override cleanly —
which is the trap. A custom hex is reachable for every app window and for none
of the shell. That is not a colour scheme, it is two of them.

---

## Rules for changing either window

- **Standard library plus PyGObject.** The wizard additionally may not import
  anything `lib/distro.sh` does not probe for.
- **Never write a theme file.** Compose a command line and run the installer.
- **Never reimplement precedence.** If a value must be known before
  `install.sh` runs, duplicate it *and* add a checker — that is what
  `tools/check-gui-radius.py` is.
- **Send only what changed.**
- Run all four GUI checks before committing:

```bash
python3 tools/check-gui-flags.py
python3 tools/check-wizard-flags.py
python3 tools/check-gui-radius.py
python3 tools/check-terminal-spawn.py
```
