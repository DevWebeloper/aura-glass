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

`welcome` (Complete Experience / Customize) → `accent` → `glass` (scope: every
app window or GTK and GNOME apps; the settings app's Opacity bar, 70–100 % with
its deep, balanced and subtle marks) → `icons` → `cursors` (+ size) →
`extensions` → `gdm` (only with `--gdm-present`, both switches on by default) →
`summary`. Choices are cards rather than radio rows.

There is no blur page: every wizard install is frosted with popups blurred.
Performance needs nothing a frosted install lacks (its sheet and drawer are made
when the mode is switched to), so it stays the settings window's mode switch.
Adwaita isn't among the wizard's pointers, though `--cursors adwaita` and the
settings app still offer it.

Pointer sizes are 24 (1080p), 32 (1440p), 48 (4K) and 64 (extra large). The one
recommended and preselected follows the largest screen's physical lines, one
class down from a scale of 1.75: up to 1200 gives 24, up to 1800 gives 32, and
above that 48 (`recommended_cursor_size`, in the window off Gdk and in
`lib/common.sh` off Mutter).

### Previews

The window shows what each choice will look like before any of it is on the
machine, and it does so without a network, a download or anything to clean up:

- **Fonts**: `gui/samples/fonts/<font>.json` holds the outline of each
  `FONT_SAMPLES` string as an SVG path. `TextOutline` fills it in the CSS colour
  around it (`Gsk.Path`, GTK 4.14), so it is as sharp as a label at any scale, which
  no PNG managed at 133%. **System default** is a real
  `Gtk.Label` in the family `--font system` lands on: `apply_font`'s backup of
  `font-name`, else the current key. Each font card shows its own font. The mock
  above follows the answer through `Window.sample_font`, which `sync_look` sets.
  Fetching the fonts instead was rejected: 90 MB, a network before the first
  question, and private fontconfig registration, for three cards.
- **Pointers**: `gui/samples/pointers/*.xcursor.gz` holds each pack's own
  `cursors/default`, one per accent for Moga. `read_pointer` reads Xcursor, and
  the **Default** pointer theme is read the same way, from the theme
  `cursor-theme` names (`pointer_theme_file`, following `Inherits`). `PointerSample`
  does Mutter's sum (image nearest size × the scale rounded up, drawn at image size
  × size / nominal, in logical px), so a tile is the size that pointer will be on
  the display the window is on. The **Default** size tile draws at `cursor-size`.
  Both keys are read, never written.
- **Icons**: under the cards, eight of the pack's own drawings from
  `gui/samples/icons/<pack>/`, in the accent's colour, swapped on each pick.
  **Default** asks `Gtk.IconTheme` instead, and leaves out what that theme lacks.
  The System icons question (`--system-icons`, the settings window's wording) sits
  below it and is hidden for **Default**, since `--no-icons` ignores the answer.
- **OSD**: the page's new question, **Capsule** or **Top bar tab** (`--osd-style`,
  the settings window's `OSD_STYLES` wording), drawn life size from `OSD_DESIGNS`,
  which copies the fixed pixels in `css/shell-00-flat.css`. Colours come from
  `[custom-osd]` in `dconf/core.ini` (`osd_colours`), the icon from `symbols/lucide/`.
  The capsule sits near the foot of the screen, the tab flush under the top bar. With
  the popup off it shows GNOME's own instead. Every answer updates it at once. It
  can't blur, so the wall's soft blobs stand in. The mocks on the welcome and summary
  pages carry a smaller copy (`osd_scene`).

`gui/samples/render_samples.py` rebuilds the files, by hand, after a change to
`FONT_SAMPLES`, `ICON_SAMPLES`, a pack's pin or an accent table. `gui/samples/NOTICE.md` says
whose each one is: the repository's MIT licence doesn't cover them.
`check-wizard-flags.py` fails on a missing one, and on OSD numbers that no longer
match the stylesheet.

`Answers.to_argv` emits a **full** flag list rather than a diff, because there's
nothing on disk yet to clobber: `--glass-mode frosted`, the scope flag,
`--app-transparency`, `--popup-blur`. It never sends `--no-blur` or
`--no-window-blur`. `Answers.best()` is "Complete Experience": every catalogued
extension, GDM where present, and monitor sync only on multi-monitor machines.

### Parity with the text wizard

Every question has a twin in `install.sh`'s text wizard (search for
`Step 0: Quick Start`). The rule is that options, defaults and recommendations
match, and the window is the canonical side (decided 2026-10-15, KI-24): the
text wizard asks the same scope and opacity (the three marks by number, or any
level from 70 to 100 typed), offers Full or Minimal for the pack, and its
Complete Experience states the same blur, transparency and pointer size answers
as `Answers.best()`. It's **stated in comments, not enforced**, and it
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
         <run dir>/window-layout  WINDOW_LAYOUT (2); an update swaps a window without it, or with less (below)
runs     install.sh --verify --progress-dir <run dir>   ("Check again")
         gnome-session-quit --logout --no-prompt         ("Log out now")
```

It has the update window's layout (below): two columns over a log drawer, opened
by **Show log**, stacking below 760sp. The left column, **Your setup**, comes
from the `choices` event `progress_choices` sends for a run the wizard started:
what `install.sh` resolved (look, glass, icons, pointer, extensions, login
screen) and what happens next. A run without that event, such as the settings
window's GDM run, is the right column alone, 640 wide instead of 1040. The right
column is a progress bar (always green, whatever the accent), the step running
now and the last log line, then the steps sliding in as each one starts (ok,
warning, failed, skipped; the ones a stopped run never reached show at the end)
and, under them, `verify_install`'s checks. A
step with problems has **Why?**: what it reported (its `warn`/`die` lines) and
its slice of the log, by the byte offsets in its `start`/`end` events. A failed
check has **Why?** with the reason and a command that fixes it. If the
installer's pid disappears without a `finish` event (terminal closed), the run
is shown as stopped.

### Update mode (`--update`)

The settings window's **Install** (on the version row) opens it at once, with no confirm
dialog (a version picked from the Releases list still asks). The settings
window makes a run directory under `$XDG_RUNTIME_DIR`, writes
`changelog.json` there (`update_changelog`: one section per release between
the installed commit and the target, newest first, each with its GitHub notes
and every commit it brought in, then the commits after the last release), opens
the terminal with `AURA_GLASS_PROGRESS_DIR=<dir> aura-glass-update <target>`
and starts this window. The layout is two columns: the changelog on the left
(one card per release, newest first), the bar and the steps on the right. Each
step slides in as it starts and the column follows the newest unless scrolled
up. The log is followed live but hidden in a drawer under both columns, opened
by **Show log**. Below 760sp the columns stack. Status badges are green for
done (an "already in place" skip too), yellow for a warning, red for a failure,
grey for a step the run chose not to do. `aura-glass-update` reports its fetch and switch steps
and owns `begin`; the `install.sh` it runs sees the variable, adds its own
steps and the finish, and opens no second window, except for one case. The
window was started from beside the settings window, so it is the release being
updated *from*. When that is older than the checkout just switched to (no
`window-layout`, or a lower one than this file's `WINDOW_LAYOUT`), the
installer's `progress_replace_update_window` opens this checkout's window on the
same run directory and closes the old one once the new one has written
`window-layout`. The new one replays `events` from the start, so the fetch and
switch steps are still there. An update from v0.3.8 shows the new layout from
the installer's first step on, not only from the next update.

---

## 2. `gui/aura_glass_settings.py`: retuning afterwards

Launched from the app grid (`io.github.DevWebeloper.AuraGlassSettings`) or
`aura-glass-settings`. It refuses to start without `$CONF_DIR`. It finds the
checkout through `$CONF_DIR/repo-path`, which is recorded rather than guessed.
If that path is gone, Apply and the repair actions do nothing except show a
"The Aura Glass folder is missing" toast. It's a
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
| Glass | Appearance | The mode in force shows at the top of every page, in the window's header bar: a button at its right (an icon for frosted, performance, or frosted under the adaptive overlay; the tooltip names the mode and any overlay reason) that switches to the other mode through the ordinary Apply, plus the title's subtitle. Both are watched live (`$C`, `$C/adaptive-performance`). The adaptive profile isn't offered here: the panel menu and `aura-glass-adaptive profile` switch it, and only the command while the top bar icon is hidden. Then the two modes in a `Gtk.Stack` inside one scroller (their pages are `GlassColumn`s, not `Adw.PreferencesPage`s, which would each scroll on their own), with a "Switch now" banner when the mode showing differs from the installed one. Each mode's page is a `GlassStudio`: three clickable thumbnails (desktop, overview, maximized app, which follow opacity, bar height and shade as they move) and six chips pick a surface, and that surface's colour button and settings show below. The colour button opens a non-modal palette window: three rows of eight suggestions, a hex entry and GTK's chooser (see [Tint suggestions](#tint-suggestions)). It follows the surface chosen while open, and a mode switch closes it. **Everything**: colour; the main sliders (Blur amount, Brightness, Opacity 70–100 %, where 100 % also stands for an opaque `0` install) and the glass style in frosted, one opacity scale in performance. **Windows**: blur behind windows (All apps / GTK apps only / Off), glass style behind app windows, fullscreen blur, static blur on maximized windows (with a Maximized windows group of bars, shown only while static, that follow the windows' own bars until moved), and its own blur amount and brightness. **Shell**: the popup blur switch, which covers notifications, and its own blur amount, brightness and opacity. **Dock & search**: colour only. **Top bar**: the lock screen's blur (the bar shares it) and the height. **Maximized top bar**: the shade. A surface bar follows its main slider until moved; then it keeps its value, and a reset button hands it back (`main`). Height and shade aren't per mode, so `_place_top_bar_groups` moves them to the mode showing. |
| Appearance | Appearance | Three tabs. **Look**: accent (nine names plus a link to GNOME Settings; there's no hex picker, by design), font. **Icons & pointer**: icon pack and colour, pointer and size. **Titlebar & top bar**: titlebar buttons and style; the Aura Glass icon in the top bar (`--no-top-bar-icon`, whose subtitle says where the adaptive profile goes while hidden) |
| Corner rounding | Appearance | Seven preset cards drawn with their own corners, reset, or eight per-surface spin rows with a live drawing |
| Per-app blur | Appearance | Three tabs. **Apps**: a search and filter held above the scroller, which cover both lists; two cards for the default for unchosen apps, with **Start from** (starting points) beside them; a switch for **Blur This App** in the window menu (`--window-menu`; a full retune on Apply, since the classifier has no narrow action for it); live "Open now" windows (D-Bus) as a grid of toggle tiles (`AppTile`: icon, name, the window class in its tooltip); every other installed app as a list (`AppRow`: click the row, a check when blurred, the window class as its subtitle) with a count of how many are blurred. An open app is only in the grid. Either shows a `via <pattern>` badge when a pattern decides it. **Patterns**: add a window class or wildcard, examples, a switch per pattern. **Games**: **fullscreen performance games** (written straight to `adaptive-fullscreen-apps`) and adding from open windows |
| Extensions | System | Every catalogued extension: switch, install/remove, settings button (when it has `prefs.js`), recommended and full packs, via `bin/aura-glass-ext` |
| Packages | System | Disk cost per pack and removal (`$HOME` packs deleted in place, `/usr` packs handed to a terminal) |
| System | System | **Login screen**, shown only with GDM or when something here was already done: theme it, with Reinstall when `gdm-gresource` or `gdm-look` no longer match (`gdm_theme_stale`, the same comparisons as `aura-glass-gdm-sync`), and monitor sync, shown only with more than one monitor or when already synced. **Installation**: Check installation (`--verify`, in a terminal) |
| Updates | System | Two tabs. **Updates**: version, check, and one Install on the version row for the update on offer; one list, newest first by date, of main's tip as a **Tag** (`v0.3.5+N`, its changelog every commit since the newest release; older tags are not listed) and **Releases** (`vX.Y.Z`, with notes): the 5 newest plus the installed one when older. One badge per row. Only the newest (main's tip, a release if tagged, else a tag) has Install, and not when it is the update the version row already offers; older rows are read-only. History graph of everything. **Maintenance**: daily update check; command line dependencies (`--deps-only`, shown only while one is missing); reapply settings; reset theme to defaults (`--reset --force --gui --interactive`). No channel row: the line follows what was installed from the list; `--update-channel` stays for the CLI |
| Uninstall | none | Built into the stack (other code needs its widgets), opened from the primary menu, not the sidebar |

The order matters: Glass is built before Blur, because the Blur page's banner
asks the mode tabs which mode is being asked for, and Blur before Per-app blur,
because the app list asks the blur rows which list is active. `SEARCH_INDEX` is
a hand-kept set of extra search words per page; titles are matched before it.
`SEARCH_TABS` says which tab of a tabbed page a word is on, so the search opens
that tab too. `FLAG_LABELS` maps flags to pages and labels for the
"N changes pending" popover and the sidebar dots. The popover's first row is
what Apply will run: `_ask_plan` sends the same flags to `install.sh
--settings-only --incremental --dry-run --plan-json` 300 ms after the last edit,
drops an answer for flags that have since changed, and `plan_summary` words it
as a quick apply and its steps or a full reapply and why. A quick apply also names
any part it refreshes because Aura Glass changed underneath it, and anything only an
update can install (`parts`, `pending_update`; ARCHITECTURE, "Parts"). Under the list, **Discard changes** puts every row back to what is installed (reverting a live preview first), the same as closing and choosing Discard but without closing. **Ctrl+S** presses Apply when Apply is sensitive.

### The header bar scrolls away

The content pane's header leaves once the page has scrolled past the header's own height and comes back only at the top of the page, not on any scroll up (`_sync_top_bar`, through `Adw.ToolbarView`'s `reveal-top-bars`, on the outermost scroller of the page or tab showing). It slides on the toolbar's animation rather than following the scroll pixel for pixel, which would take one scroller shared by every page. So the mode button, the title with its subtitle, the preview toggle and the main menu are at the top of each page, not always in view. What stays:

- the bottom bar (Apply, the log, "Previewing" with Revert) and the sidebar with its search, whose header is also the window's drag handle,
- the window buttons: a `Gtk.WindowControls` floats top right while the header is gone. A layout with them on the left has them in the sidebar's header already, so nothing floats,
- the whole header below 700sp: collapsed, it holds the back button and no sidebar is showing, so it stays pinned.

### What doesn't ride on Apply

- **Extension switches** apply immediately through `aura-glass-ext`, streamed into the same log.
- **Packages**: a filesystem delete under `$HOME`, or the package manager in a terminal for `/usr`.
- **Anything needing root** (deps `--deps-only`, GDM, monitor sync, uninstall scopes) and the long operations (reapply settings, reset to defaults, update) **open a real terminal** from `TERMINALS` (ptyxis, kgx, gnome-terminal, konsole, alacritty, kitty, foot, wezterm, x-terminal-emulator, xterm). `sudo` down a pipe would block forever. If no terminal is found, the command is shown to copy. Terminals aren't waited on, so those rows show the last state read.
- **Games list** writes `$CONF_DIR/adaptive-fullscreen-apps`, then `aura-glass-adaptive refresh`.

### Live preview

A colour pick previews at once, where sliders wait 400 ms (and per-app switches 200 ms) to see whether they've stopped. The toggles behind a reload run with no gap in a preview (`PREVIEW_MODE` in `aura-glass-apply`), so the shell and open apps don't sit on the default theme, and a tint-only tick skips the dconf half (`$BACKUP/dconf-args`), because a tint reaches no dconf key.

Backed by `bin/aura-glass-preview` and serialized by `gui/preview_queue.py`
(one active operation, one replaceable pending one; Apply, Revert and Close
take precedence):

```
aura-glass-preview begin                       snapshot sheets + BMS dconf dump + memos into $CONF_DIR/preview-backup, mark preview-active
aura-glass-preview set [--maximized-blur static|dynamic] [--app-tint HEX] [--shell-tint HEX] [--dock-tint HEX|main] [--panel-tint HEX|main] [--maximized-panel-tint HEX|main] [--transparency L] [--radius-preset P]
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

### Tint suggestions

The rows are `wallpaper_palette.suggest()`, for the surface chosen and the sliders as they stand. A pick is the same flag as a typed hex, so nothing here reaches the theme except through the resolver.

1. **From your wallpaper**: its most telling hues (clustered in OKLab, ranked for colour as much as area, so near-black, near-white and grey pixels and near-duplicates don't fill the row), then its own neutral.
2. **In harmony with it**: analogous, split-complementary, triadic and complementary hues of the main one. A hue the blur would cancel to grey is dropped.
3. **Classics**: black as shipped, graphite, the GNOME accent, then fixed deep tints.

Each colour is searched for by the result on the surface, not by its hex: the app tint's mix, the shell's hue-and-saturation on a dark ground, or the dock and top bar's exact colour at their alpha, over the wallpaper as a blur leaves it (`GlassModel`). The search aims at a depth and chroma per surface (`GOALS`) and keeps white text at 7:1 on windows and 4.5:1 on bars against the brightest part of that blur. Swatches paint that same result, so a suggestion's hex is in its tooltip and not on its face. The same swatch can therefore have a different hex under another chip.

**Brightness** and **Intensity** under the rows adjust the colour in use and keep its hue, in OKLCH. Intensity is a share of the most chroma sRGB can show at that lightness, so 100 % is always this colour at its strongest. They're off for a surface with no colour, and Brightness is off for Shell, which keeps its own lightness. Each pause in a drag is an ordinary pick. These colours aren't fitted to the glass, so readability there is yours to judge.

`WallpaperWatch` reads `picture-uri-dark`, then `picture-uri`, on a thread. An XML slideshow means the frame showing now, `picture-options=none` or no URI means `primary-color` (and `secondary-color` when shaded), and anything unreadable or colourless means rows 1 and 2 become fixed tints and the accent's harmonies. It's the same three rows of eight in every case. The wizards don't ask for a tint, so there's nothing there to keep in parity.

The model reads Opacity, the maximized shade and the mode from the window. Blur brightness and per-surface opacity (`--popup-opacity`) aren't modelled: the shipped values stand in for them.

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
