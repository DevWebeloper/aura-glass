# The GUI layer

Two GTK4 + libadwaita windows. Both are optional and both are **front ends for
flags `install.sh` already has**. Neither writes a theme file. If the toolkit is
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
match. It's **stated in comments, not enforced**, and it has drifted on the
recommended pointer (KI-05). `check-wizard-flags.py` checks only that every
command line the window can produce is accepted.

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

- the top-level memos (accent, radius, scope, popup and notification blur, packs, font, buttons, style, panel fix, update check),
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
- The app tint is sent only while transparency is on (its sheet doesn't exist otherwise).
- Blur strength and brightnesses are compared against `other`, not the drawer, and aren't sent in Performance.
- Both app-blur lists are sent whenever either changed.

Which Applies stay narrow (`accent`, `cursor-*`, `window-buttons`,
`window-brightness`, `app-blur`, `css`) and which fall back to the full retune
is decided by `select_apply_actions`. See
[CONFIG-REFERENCE.md](CONFIG-REFERENCE.md) §1.4.

### Pages (`NAV_SECTIONS`; builders run in this order)

| Page | Group | Holds |
|---|---|---|
| Glass | Appearance | A status group on top: the mode in force plus any adaptive overlay and its reason, a "Switch to X" button (the ordinary Apply), and an "Adaptive performance" combo running `aura-glass-adaptive profile` like the panel menu. It's watched live (`$C`, `$C/adaptive-performance`), and the header subtitle repeats it on every page. Then two mode tabs (Frosted, Performance) in an `Adw.ViewStack`, with a "Switch now" banner when the tab differs from the installed mode. **Frosted**: tints, transparency (an off switch plus a 70–100 % scale), blur strength, window and popup blur brightness, notification ground, popup and notification blur switches, and the scope as two switches ("Blur behind app windows", then "all application windows", which defaults on). **Performance**: tints and one opacity scale. |
| Appearance | Appearance | Accent (nine names plus a link to GNOME Settings; there's no hex picker, by design), icon pack and colour, pointer and size, font, titlebar buttons and style |
| Corner rounding | Appearance | Seven preset cards drawn with their own corners, reset, or eight per-surface spin rows with a live drawing |
| Per-app blur | Appearance | A switch per installed app, live "Open now" windows (D-Bus), a default for unchosen apps, **fullscreen performance games** (written straight to `adaptive-fullscreen-apps`), wildcard patterns |
| Extensions | System | Every catalogued extension: switch, install/remove, recommended and full packs, via `bin/aura-glass-ext` |
| Packages | System | Disk cost per pack and removal (`$HOME` packs deleted in place, `/usr` packs handed to a terminal) |
| System | System | Dependencies, rounded-blur, panel-blur fix, login screen, monitor sync |
| Updates | System | Version and channel, check, install update, reapply settings, full reinstall |
| Uninstall | none | Built into the stack (other code needs its widgets), opened from the primary menu, not the sidebar |

The order matters: Glass is built before Per-app blur, because the app list asks
the blur rows which list is active. `SEARCH_INDEX` is a hand-kept set of extra
search words per page. `FLAG_LABELS` maps flags to pages and labels for the
"N changes pending" popover and the sidebar dots.

### What doesn't ride on Apply

- **Extension switches** apply immediately through `aura-glass-ext`, streamed into the same log.
- **Packages**: a filesystem delete under `$HOME`, or the package manager in a terminal for `/usr`.
- **Anything needing root** (deps `--deps-only`, rounded-blur, GDM, monitor sync, uninstall scopes) and the long operations (reapply settings, full reinstall, update) **open a real terminal** from `TERMINALS` (ptyxis, kgx, gnome-terminal, konsole, alacritty, kitty, foot, wezterm, x-terminal-emulator, xterm). `sudo` down a pipe would block forever. If no terminal is found, the command is shown to copy. Terminals aren't waited on, so those rows show the last state read.
- **Reapply CSS** runs `aura-glass-apply --force-reload` in a terminal.
- **Games list** writes `$CONF_DIR/adaptive-fullscreen-apps`, then `aura-glass-adaptive refresh`.

### Live preview

Backed by `bin/aura-glass-preview` and serialized by `gui/preview_queue.py`
(one active operation, one replaceable pending one; Apply, Revert and Close
take precedence):

```
aura-glass-preview begin                       snapshot sheets + BMS dconf dump + memos into $CONF_DIR/preview-backup, mark preview-active
aura-glass-preview set [--app-tint HEX] [--shell-tint HEX] [--transparency L] [--radius-preset P]
                       [--radius-custom …] [--blur-strength P] [--popup-blur 0|1] [--popup-brightness P] [--window-brightness P]
                       [--notification-opacity P] [--window-blur 0|1] [--scope gtk|all, default all]
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
