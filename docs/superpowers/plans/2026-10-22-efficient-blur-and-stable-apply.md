# Efficient frosted blur and stable apply — implementation plan

> **For agentic workers:** executed natively in the session that wrote it
> (the maintainer asked for it to be made, then checked before anything is
> pushed). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** cut Frosted's GPU cost without giving up dynamic blur, stop retunes
from waking the shell for settings that did not change, and make the settings
window quicker to use.

**Architecture:** one new remembered setting (`--blur-refresh`) owns Blur My
Shell's `hacks-level` in Frosted; the Aura Glass Helper repairs what clipped
redraws can leave behind with a rare full repaint; `run` skips a dconf or
gsettings write whose value is already in place; the settings window gets the
new row, a live GPU readout, Discard and Ctrl+S.

**Tech stack:** Bash installer, GJS (GNOME Shell 48–51 extension), Python +
PyGObject (GTK 4 / libadwaita settings window).

## Evidence (live session, 2026-10-22)

RX 7600, two monitors (3440×1440 @ 180 Hz + 1536×960), GNOME Shell 51.1,
Frosted, blur strength 200, window blur on all apps. `tools/gpu-sample.py` and
`tools/gpu-live.sh --quick`, `hacks-level` changed live between runs:

| hacks-level | idle median | idle p90 | overview toggle median | overview p90 |
|---|---|---|---|---|
| 2 (shipped) | 57 % | 58 % | 23 % | 58 % |
| 1 (upstream default) | 53 % | 54 % | — | — |
| 0 | 10 % | 14 % | 12 % | 28 % |

Level 2 sets `DISABLE_CLIPPED_REDRAWS` for the whole stage: any damage, a
cursor blink or a streaming window, repaints both monitors and every blur
actor on them. Level 1 queues a full blur-actor repaint from every paint of a
blurred actor, which on maximised windows is nearly the same. Level 0 keeps
clipped redraws; the blur stays dynamic.

What level 0 can get wrong: Shell's background blur blits the whole actor box
from the framebuffer, but only the redraw clip holds freshly painted pixels.
Inside a small damaged rectangle the blur can mix in a band of the previous
final composite, a faint patch that stays until something repaints the area
in full. It does not compound (the pixels outside the clip are not repainted),
so one full repaint clears it.

A no-op `./install.sh --settings-only -y` made **37** dconf/gsettings writes,
every one to the value already there (logged with wrapper scripts on `PATH`).
Each one wakes its listener: Blur My Shell rebuilds pipelines and effects, User
Themes reloads the shell theme, GTK re-reads icon, cursor and font settings.

The journal shows the helper throwing `ReferenceError: mode is not defined`
from `_updateOpacityFromConfig` (extension.js:758) on every enable and on every
Blur My Shell state change: the Performance-mode opacity branch never ran.

## Global constraints

- One resolver (CLAUDE.md rule 1): the flag is parsed in `install.sh`, resolved and written by an `apply_*` in `lib/steps-dconf.sh`, remembered under `remembering`.
- Precedence for the new memo: typed flag → `$CONF_DIR/blur-refresh` → default `efficient`. Top-level, mode independent, like `fullscreen-blur`.
- Performance and adaptive *active* keep `hacks-level=0` from `dconf/solid.ini`; the new writer does nothing while `WANT_BLUR` is not 1.
- Dry runs print every write as before (checks grep the `dry-run:` lines); only real runs compare.
- No new files under `tools/` (rule 6). Extend existing checks.
- No AI attribution in commits. Subjects `type(scope): lower-case sentence`.
- Nothing pushed or merged until the maintainer has looked.

## Review focus

1. A value written in a different textual form from what `dconf read` prints (`1.00` vs `1.0`, `0.70` vs `0.69999999999999996`) must still compare equal, and a genuinely different value must still be written.
2. Entering Frosted from Performance on an existing install must land on the remembered refresh level in one write, not core.ini's then the memo's (each `hacks-level` change restarts Blur My Shell).
3. The settle repaint must not loop: its own repaint must not count as new damage on any monitor.
4. No settle while a fullscreen window is focused, in Performance, while adaptive is active, or when `hacks-level` is not 0.
5. `--blur-refresh` alone stays a quick (incremental) Apply and keeps the mode drawer untouched.

---

### Task 1: skip writes whose value is already in place

**Files:** modify `lib/common.sh` (`run`).

- [ ] `run` gains `already_in_place "$@"`: for `dconf write KEY VALUE` compare with `dconf read KEY`; for `gsettings set SCHEMA KEY VALUE` compare with `gsettings get SCHEMA KEY` (also against `'VALUE'`, since gsettings takes a bare string). Equal text, or two numbers equal by value (awk), or two GVariant texts equal after `GLib.Variant.parse` when PyGObject is present. Any read failure means "write".
- [ ] Not under `DRY_RUN=1`.
- [ ] Verify: hermetic checks `check-glass-modes.sh`, `check-adaptive-installer.sh`, `check-app-blur-lists.sh`, `check-preview-queue.py` pass; live no-op retune with the logging wrappers makes 0 writes.

### Task 2: `--blur-refresh efficient|accurate`

**Files:** `install.sh` (vars, help, parse, narrow-action dispatch), `lib/steps-dconf.sh` (`apply_blur_refresh`, call from `load_dconf`, `sync_mode_owned_keys` leaves `hacks-level` to it in Frosted), `lib/steps-apply-plan.sh` (narrow action `blur-refresh`), `dconf/core.ini` (`hacks-level=0` and its comment rewritten with the table above), `uninstall.sh` (memo), `docs/CONFIG-REFERENCE.md`.

- [ ] `efficient` → `hacks-level 0`; `accurate` → `hacks-level 2`. Unknown value dies naming the two.
- [ ] Extend `tools/check-glass-modes.sh` (dry-run line for each value, memo default) and `tools/check-incremental-apply.py` (flag classified narrow).

### Task 3: helper — fix the crash, add the settle repaint

**Files:** `extensions/aura-glass-blur@aura-glass.local/extension.js`.

- [ ] `_updateOpacityFromConfig` reads `glass-mode` before using it.
- [ ] Settle: while `hacks-level` is 0, Frosted, adaptive not active and no fullscreen window focused, `global.stage` `after-paint` marks the stage dirty; 250 ms after the last paint, or at most 1 s into continuous activity, one `global.stage.queue_redraw()` repaints everything. The views that repaint for it are remembered and their next `after-paint` is not counted.
- [ ] Watches `changed::hacks-level` on Blur My Shell's root schema and the `glass-mode`/`active` files it already monitors. Everything disconnected in `disable()`.
- [ ] Verify: `node --check` style parse (`gjs -m` not needed); live after a re-login.

### Task 4: settings window

**Files:** `gui/aura_glass_settings.py`, `tools/check-gui-flags.py`.

- [ ] `Settings.blur_refresh` (memo, default `efficient`), `flags_against` sends `--blur-refresh X` on change, `FLAG_LABELS`, `_current`, `_reload`, `SEARCH_INDEX` (gpu, refresh, artifacts).
- [ ] Frosted tab: a "GPU" group with the combo ("Efficient", "Accurate") and a "GPU load now" row fed from the same sysfs source the adaptive worker reads, sampled every 2 s only while the window is visible on the Glass page; hidden when there is no counter. The closing tip card names the new row.
- [ ] Pending popover gets "Discard changes" (puts every row back to what is installed, reverting a live preview first). Ctrl+S runs Apply when it is sensitive.
- [ ] `check-gui-flags.py`: cases for both directions.

### Task 5: docs and verification

- [ ] `docs/KNOWN-ISSUES.md`: KI-33 (helper ReferenceError) and KI-34 (redundant writes on every retune), both under Fixed with this branch.
- [ ] Run the full hermetic suite (TESTING.md loop).
- [ ] Live: `./install.sh --settings-only -y`, GPU sample before/after, maintainer re-logs to load the helper and judges the look.
