# The GUI layer

Two GTK4 + libadwaita windows, plus a third that only watches an install (§2b).
All are optional and the first two are **front ends for flags `install.sh`
already has**. None writes a theme file. If the toolkit is
missing, the installer skips them and everything else installs normally.
Nothing is reachable only from the GUI.

Requirements: PyGObject, Gtk 4, libadwaita 1. The settings window also needs
**pycairo** (`import cairo`), which the installer's probe doesn't check yet
(KI-04).

---

## 1. `gui/aura_glass_setup_wizard.py`: the opening questions

Runs **before** anything is installed, from `run_setup_wizard`
(`lib/steps-wizard.sh`), when `install.sh` gets no flags (or `--interactive`)
in a TTY with a display.

### Contract

```
argv     --repo <checkout> [--gdm-present]
stdout   the flags, one token per line. NOTHING else may ever be printed here.
stderr   anything for a human.
exit 0   answered          → install.sh parses the flags (parse_flags again) and continues with --yes
exit 2   cancelled         → install.sh stops, nothing changed
other    broke             → install.sh asks the same questions in the terminal
```

`install.sh` **blocks** on it. Plain redirection, no pipe: the exit code is the
protocol.

### Pages

`welcome` (Complete Experience / Customize) → `accent` → `blur` ("Frosted
glass, or performance". "Performance" sends `--no-blur`) → `blur_details` (popup blur, scope,
transparency) → `icons` → `cursors` (+ size)
→ `extensions` → `gdm` (only with `--gdm-present`) → `summary`.

`Answers.to_argv` emits a **full** flag list rather than a diff, because there's
nothing on disk yet to clobber. `--no-blur` goes out alone. Otherwise it sends
the scope flag, then `--app-transparency`, then `--popup-blur` or
`--no-popup-blur`. `Answers.best()` is "Complete Experience": every catalogued
extension, GDM where present, and monitor sync only on multi-monitor machines.

### Parity with the text wizard

Every question has a twin in `install.sh`'s text wizard (search for
`Step 0: Quick Start`). The rule is that options, defaults and recommendations
match, and the window is the canonical side (decided 2026-10-15, KI-24): the
text wizard asks Frosted/Performance first (Performance goes out as a lone
`--no-blur`, as the window sends it), offers Full or Minimal for the pack, and
its Complete Experience states the same blur, transparency and 20px pointer
answers as `Answers.best()`. It's **stated in comments, not enforced**, and it
had drifted on the recommended pointer (KI-05). `check-wizard-flags.py` checks only that every
command line the window can produce is accepted.

---

## 2b. `gui/aura_glass_install_progress.py`: following a full install

Opened detached by `progress_begin` (`lib/progress.sh`) after the GTK wizard
answers, or for `--progress-window` (the settings window adds it to the GDM,
and monitor-sync runs it opens in a terminal). The terminal stays
the installer: sudo and every question are asked there, and the window shows a
banner while the terminal waits (`progress_wait`, called from `confirm`,
`confirm_always` and the sudo prompts).

### Contract

```
argv     --dir <run dir>          events + log, written by lib/progress.sh
reads    events (JSON lines, listed at the top of lib/progress.sh), log
writes   <run dir>/window         its pid; prompt_logout leaves the logout to it while it is open
runs     install.sh --verify --progress-dir <run dir>   ("Check again")
         gnome-session-quit --logout --no-prompt         ("Log out now")
```

It shows a progress bar (always green, whatever the accent), the step running
now and the last log line, then the checklist: one row per planned step
(ok, warning, failed, skipped) and, under it, `verify_install`'s checks. A
step with problems has **Why?**: what it reported (its `warn`/`die` lines) and
its slice of the log, by the byte offsets in its `start`/`end` events. A failed
check has **Why?** with the reason and a command that fixes it. If the
installer's pid disappears without a `finish` event (terminal closed), the run
is shown as stopped.

### Update mode (`--update`)

The settings window's **Install update** opens it at once, with no confirm
dialog (a version picked from the Releases list still asks). The settings
window makes a run directory under `$XDG_RUNTIME_DIR`, writes
`changelog.json` there (`update_changelog`: one section per release between
the installed commit and the target, newest first, each with its GitHub notes
and every commit it brought in, then the commits after the last release), opens
the terminal with `AURA_GLASS_PROGRESS_DIR=<dir> aura-glass-update <target>`
and starts this window. The layout is changelog above, bar in the middle, the
log live at the bottom. `aura-glass-update` reports its fetch and switch steps
and owns `begin`; the `install.sh` it runs sees the variable, adds its own
steps and the finish, and opens no second window.

---

## 2. `gui/aura_glass_settings.py`: retuning afterwards

Launched from the app grid (`io.github.DevWebeloper.AuraGlassSettings`) or
`aura-glass-settings`. It refuses to start without `$CONF_DIR`. It finds the
checkout through `$CONF_DIR/repo-path`, which is recorded rather than guessed.
If that path is gone, Apply and the repair actions do nothing except show a
"checkout is gone" toast. It's a
`HANDLES_COMMAND_LINE` app, so `--page IDENT` raises a running instance on a
page.

### State: `Settings`

`Settings.__init__` reads what is **installed**, not what the window last sent:

- the top-level memos (accent, radius, scope, popup blur, the main blur amount and brightness, each surface's own values and the popup opacity, packs, font, buttons, style, panel fix, update check). The per-surface memos are read the way `surface_memo_read` reads them, legacy `window-brightness`/`popup-brightness` included (`read_surface_memo`),
- the mode: `glass-mode`, else derived from whether `shell-80-solid.css` is installed,
- per mode, `self.modes[mode]` read from the drawers, so switching tabs shows a mode's own tuning without applying anything.

For the mode in force:

- **frosted**: transparency comes from the top-level memo, tints from the drawer.
- **performance**: transparency and tints come from the drawer.

> Because the installer's narrow `--incremental` path doesn't update drawers,
> the window can re-read stale tints or levels right after Apply (KI-01).
> **Rule C5:** read a field from wherever the installer will resolve it next
> time, and make sure every writer keeps that place current.

Missing-memo defaults must equal the installer's. Today `cursor-pack` defaults
to `moga` here but `adwaita` in the installer (KI-05).

### Apply: `flags_against`

```
_on_apply → PreviewQueue.request_terminal("apply")
         → _start_apply: install.sh --settings-only --incremental --yes <diff>
                         (wrapped in: aura-glass-preview commit --session S -- … when a preview is active)
         → on success: _reload() (Settings() again), toast; on failure the preview is reverted
```

`Settings.flags_against(other)` sends **only differences**, because the
installer resolves an absent flag from its memo. Sending everything would make
every Apply assert settings the user never touched. Details that matter:

- A mode change sends `--glass-mode` first. The baseline for the other fields is then the **target mode's drawer**, not the old state.
- `--radius-custom` stands in for `--radius-preset custom`.
- The scope flag goes before `--app-transparency`, because `--no-window-blur` sets 0.95 unless a level is given.
- The app tint is sent only while transparency is on (its sheet doesn't exist otherwise). An install at level `0` shows the opacity bar at 100%; a tint edit there sends `--app-transparency 1.00` with it.
- The main blur amount and brightness, each surface's own values and the popup opacity are compared against `other`, not the drawer, and aren't sent in Performance. A surface handed back to its main slider is sent as `main`.
- Both app-blur lists are sent whenever either changed.

Which Applies stay narrow (`accent`, `cursor-*`, `window-buttons`,
`blur-pipelines`, `app-blur`, `css`) and which fall back to the full retune
is decided by `select_apply_actions`. See
[CONFIG-REFERENCE.md](CONFIG-REFERENCE.md) §1.4.

### Pages (`NAV_SECTIONS`; builders run in this order)

| Page | Group | Holds |
|---|---|---|
| Glass | Appearance | A status group on top: the mode in force plus any adaptive overlay and its reason, a "Switch to X" button (the ordinary Apply), and an "Adaptive performance" combo running `aura-glass-adaptive profile` like the panel menu. It's watched live (`$C`, `$C/adaptive-performance`), and the header subtitle repeats it on every page. Then two mode tabs (Frosted, Performance) in an `Adw.ViewStack`, with a "Switch now" banner when the tab differs from the installed mode. **Frosted**: tints; a Glass group of three main sliders (Blur amount, Brightness, Opacity 70–100 %, where 100 % also stands for an opaque `0` install); "Blur behind windows" (All apps / GTK apps only / Off) and the popup blur switch, which covers notifications; the glass style; and a collapsed Advanced group with one expander per surface (Windows, Popups & notifications, Top bar, Lock screen) holding that surface's own blur amount and brightness (plus opacity for popups & notifications), and a More expander for glass style behind app windows and fullscreen blur. A surface bar follows its main slider until moved; then it keeps its value, and a reset button hands it back (`main`). **Performance**: tints and one opacity scale. |
| Appearance | Appearance | Accent (nine names plus a link to GNOME Settings; there's no hex picker, by design), icon pack and colour, pointer and size, font, titlebar buttons and style, and the top bar height (24–48 px, with a reset to GNOME's 32) |
| Corner rounding | Appearance | Seven preset cards drawn with their own corners, reset, or eight per-surface spin rows with a live drawing |
| Per-app blur | Appearance | A switch per installed app, live "Open now" windows (D-Bus), a default for unchosen apps, **fullscreen performance games** (written straight to `adaptive-fullscreen-apps`), wildcard patterns |
| Extensions | System | Every catalogued extension: switch, install/remove, settings button (when it has `prefs.js`), recommended and full packs, via `bin/aura-glass-ext` |
| Packages | System | Disk cost per pack and removal (`$HOME` packs deleted in place, `/usr` packs handed to a terminal) |
| System | System | Dependencies, login screen, monitor sync |
| Updates | System | Two tabs. **Updates**: version, check, install update; one list, newest first by date, of **Tags** (every commit on main, named `v0.3.5+N`) and **Releases** (`vX.Y.Z`, with notes): the 5 newest of each plus the installed one when older. One badge per row. Only the newest (main's tip, a release if tagged, else a tag) has Install; older rows are read-only. History graph of everything. **Maintenance**: daily update check; reapply settings; reset theme to defaults (`--reset --force --gui --interactive`). No channel row: the line follows what was installed from the list; `--update-channel` stays for the CLI |
| Uninstall | none | Built into the stack (other code needs its widgets), opened from the primary menu, not the sidebar |

The order matters: Glass is built before Per-app blur, because the app list asks
the blur rows which list is active. `SEARCH_INDEX` is a hand-kept set of extra
search words per page. `FLAG_LABELS` maps flags to pages and labels for the
"N changes pending" popover and the sidebar dots. The popover's first row is
what Apply will run: `_ask_plan` sends the same flags to `install.sh
--settings-only --incremental --dry-run --plan-json` 300 ms after the last edit,
drops an answer for flags that have since changed, and `plan_summary` words it
as a quick apply and its steps or a full reapply and why. Under the list, **Discard changes** puts every row back to what is installed (reverting a live preview first), the same as closing and choosing Discard but without closing. **Ctrl+S** presses Apply when Apply is sensitive.

### What doesn't ride on Apply

- **Extension switches** apply immediately through `aura-glass-ext`, streamed into the same log.
- **Packages**: a filesystem delete under `$HOME`, or the package manager in a terminal for `/usr`.
- **Anything needing root** (deps `--deps-only`, GDM, monitor sync, uninstall scopes) and the long operations (reapply settings, reset to defaults, update) **open a real terminal** from `TERMINALS` (ptyxis, kgx, gnome-terminal, konsole, alacritty, kitty, foot, wezterm, x-terminal-emulator, xterm). `sudo` down a pipe would block forever. If no terminal is found, the command is shown to copy. Terminals aren't waited on, so those rows show the last state read.
- **Reapply CSS** runs `aura-glass-apply --force-reload` in a terminal.
- **Games list** writes `$CONF_DIR/adaptive-fullscreen-apps`, then `aura-glass-adaptive refresh`.

### Live preview

Backed by `bin/aura-glass-preview` and serialized by `gui/preview_queue.py`
(one active operation, one replaceable pending one; Apply, Revert and Close
take precedence):

```
aura-glass-preview begin                       snapshot sheets + BMS dconf dump + memos into $CONF_DIR/preview-backup, mark preview-active
aura-glass-preview set [--app-tint HEX] [--shell-tint HEX] [--transparency L] [--radius-preset P]
                       [--radius-custom …] [--blur-strength P] [--blur-brightness P]
                       [--SURFACE-blur-strength P|main] [--SURFACE-brightness P|main] [--popup-opacity P|main]
                       [--popup-blur 0|1] [--window-blur 0|1] [--scope gtk|all, default all]
                       [--app-blur-allow L] [--app-blur-block L]
aura-glass-preview apps --allow L --block L [--window-blur 0|1] [--scope …]   per-app only (dconf, no CSS rebuild)
aura-glass-preview revert [--session S]       restore sheets + BMS subtree byte-for-byte, re-splice
aura-glass-preview commit --session S -- CMD  run CMD (the Apply); on success drop the journal, on failure revert
aura-glass-preview status
```

`set` calls the **same** `apply_*` functions as `install.sh`, with
`PREVIEW_MODE=1`, against a CSS baseline reset from `css/` on every call, so
relative rewrites don't compound. **Hard rule:** a preview never leaves a
`$CONF_DIR` memo different from what it found. `remembering()` is false, so
nothing is written in the first place. `check-preview.sh` (live) asserts it.
On startup the window recovers an interrupted preview through the backend and
reports the real result.

### The D-Bus bridge

`ShellBridge` talks to `io.github.DevWebeloper.AuraGlass` (exported by the Aura
Glass Helper extension whenever it's enabled). It uses `ListWindows` and
`WindowsChanged` for "Open now" and the games list, and `SetWindowOpacity` /
`RefreshOpacity` for live opacity while dragging. The window uses the bridge
only if it answers.

### Accent: why there's no colour picker

The shell CSS uses `-st-accent-color`, a read-only St keyword backed by the
`StSystemAccentColor` enum. GTK uses `@accent_bg_color`. A custom hex could
recolour every app window but none of the shell, which would make two colour
schemes, not one. So the row offers GNOME's nine accents and keeps the memo in
step.

---

## 3. Rules for changing either window

1. **Emit flags. Never write theme files or installer memos.** The exceptions are listed in [CONSISTENCY.md](CONSISTENCY.md) §1.1.
2. **Never reimplement precedence.** If you must know a value before `install.sh` runs, duplicate it **and** add a checker (like `check-gui-radius.py`).
3. **Send only what changed** (settings window). Send everything (setup wizard).
4. **Read where the installer reads** (C5), with the same missing-memo defaults.
5. **Root goes to a terminal.** Long jobs go to a terminal or the async log, never a blocking call on the main loop.
6. **Wizard parity**: same questions, options and recommendations as the text wizard.
7. Run `check-gui-flags.py`, `check-wizard-flags.py`, `check-gui-radius.py`, `check-terminal-spawn.py`, `check-preview-queue.py`, `check-apply-lifecycle.py` and `check-apply-feedback.py`.
