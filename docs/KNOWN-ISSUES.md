# Known issues

A working list of the bugs and inconsistencies found in the 2026-10-15 audit
of the working tree, and of those found while fixing them. Each entry gives the symptom, how to reproduce it, the
root cause by file and function, a fix direction, and how to verify the fix.

**Status key.** *Reproduced*: shown on a fixture install with stubbed
`dconf`/`gsettings`, nothing on a live desktop. *Code-read*: follows directly
from the code, not run. *Verify*: plausible, needs a live check first.

The CLI reproductions below **change the live desktop**. Note your current
values first (`head ~/.config/aura-glass/*`) and set them back afterwards.

When you fix one, move it to the bottom section with the commit that fixed it.

| ID | Severity | Status | One line |
|---|---|---|---|
| [KI-01](#ki-01) | High | **Fixed** (2026-10-15 batch, verified live 2026-10-20) | Settings-app Apply is silently reverted by the next full apply. The window shows stale tint/level |
| [KI-02](#ki-02) | High | **Fixed** (2026-10-15 batch, verified live 2026-10-20) | Adaptive restore breaks Performance mode (removes the opaque sheet, re-enables app blur) |
| [KI-03](#ki-03) | High | **Fixed** (2026-10-15 batch, verified live 2026-10-20) | Switching modes on an existing install toggles only 3 of 10 blur components |
| [KI-04](#ki-04) | Medium | **Fixed** (2026-10-15 batch) | Settings app crashes without pycairo, which the toolkit probe doesn't check |
| [KI-05](#ki-05) | Medium | **Fixed** | Four different "recommended/default" pointer answers. Text wizard can't pick Moga |
| [KI-06](#ki-06) | Low | **Fixed** | Stale prose and labels (Magic Lamp, "14 extras", scope and transparency defaults, wizard "Solid" = Performance) |
| [KI-07](#ki-07) | Medium | **Fixed** (2026-10-15 batch) | Uninstall leaves `aura-glass-operation` and `aura-glass-preview` in `~/.local/bin` |
| [KI-08](#ki-08) | Low | **Fixed** | `--dry-run` / `--plan-json` aren't side-effect free |
| [KI-09](#ki-09) | Low | **Fixed** (`07689ba`) | Launchers disagree on checkout vs installed copy |
| [KI-10](#ki-10) | Low | **Fixed** (`07689ba`) | Packages page doesn't know Moga packs |
| [KI-11](#ki-11) | Low | **Fixed** (`07689ba`, `620b699`) | Misleading success messages (BMS refresh on 51, rounded-blur compile) and an unneeded sudo prompt |
| [KI-12](#ki-12) | Medium | **Fixed** (`620b699`) | The rootless `~/.local/lib` rounded-blur build never loads in the shell |
| [KI-13](#ki-13) | Low | **Fixed** (`07689ba`) | AUR packaging is inconsistent with the repo |
| [KI-14](#ki-14) | Low | **Fixed** (`07689ba`) | Test-suite gaps: a non-hermetic check, checks missing from the hook, a fabricated fixture |
| [KI-15](#ki-15) | Info | **Fixed** (`07689ba`) | Legacy `solid`/`transparent` machinery removed, replaced by a one-time migration |
| [KI-16](#ki-16) | Info | By design (decided 2026-10-15) | Every full apply forces `color-scheme=prefer-dark` |
| [KI-17](#ki-17) | Info | **Fixed** (`07689ba`, v0.3.3) | Housekeeping: stray tags, `.claude/` not ignored, `--plan-json` unwired, `refresh` via PATH |
| [KI-18](#ki-18) | High | **Fixed** (2026-10-15 batch) | A fresh `--glass-mode frosted` (and the text wizard's Customize path) gives opaque windows. The wizard's transparency answer is discarded |
| [KI-19](#ki-19) | Low | **Fixed** (2026-10-15 batch, verified live 2026-10-20) | "Blur This App" writes to the destroyed window menu (journal stack traces), and its post-toggle checkmark uses a different rule than the menu |
| [KI-20](#ki-20) | Medium | **Fixed** (`903bb45`, verified live 2026-10-20) | A mode switch left open GTK windows on the old alpha until each app was reopened |
| [KI-21](#ki-21) | Medium | **Fixed** (`903bb45`, verified live 2026-10-20) | Tray Performance profile never showed the opaque shell sheet (shell theme not reloaded) |
| [KI-22](#ki-22) | Medium | **Fixed** | Settings app never showed the mode in force or the adaptive overlay, and missed changes made outside it |
| [KI-23](#ki-23) | Medium | **Fixed** | Install/update/uninstall audit: silent failures, lost memos, leftovers |
| [KI-24](#ki-24) | Low | **Fixed** | Update and full reinstall forgot the extension pack, `--no-osd`, `--no-bms-git`, `--no-rounded-blur`. Text wizard drifted from the GTK wizard |
| [KI-25](#ki-25) | Medium | **Fixed** (`6a3adc1`, verified live 2026-10-20) | Tray Performance profile left a different desktop from the app's Performance mode (raw shell sheet, no app tint sheet, `hacks-level` and OSD alpha on Frosted's values, restore not exact) |
| [KI-26](#ki-26) | Medium | **Fixed** (`07689ba`, verified live 2026-10-20) | Notification banners sometimes arrive with no visible blur, or washed out until hovered |
| [KI-27](#ki-27) | Low | **Fixed** (`07689ba`) | History cards never get rounded blur corners without gnome-rounded-blur (undefined constant in the notification patch) |
| [KI-28](#ki-28) | Low | **Fixed** (`07689ba`) | The helper never sees adaptive `active` change, so its window opacity misses adaptive transitions |
| [KI-29](#ki-29) | Low | **Fixed** (`07689ba`) | No check applies the Blur My Shell patches to the pin or catches undefined names in them (how KI-27 shipped) |
| [KI-31](#ki-31) | Medium | **Fixed** | The overview sometimes keeps a stale blur after leaving a settings-app preview |
| [KI-32](#ki-32) | Medium | **Fixed** | Updating from the settings app greys out Install or stops at a git error (detached HEAD, local edits, diverged history, re-cut tag) |
| [KI-33](#ki-33) | Medium | **Fixed** (`feat/efficient-blur-qol`) | The helper threw `ReferenceError: mode is not defined` on every enable, so Performance never got its window opacity |
| [KI-34](#ki-34) | Medium | **Fixed** (`feat/efficient-blur-qol`) | Every retune rewrote ~37 dconf/gsettings keys to the values already there, waking Blur My Shell, User Themes and GTK |
| [KI-35](#ki-35) | Info | By design (decided 2026-10-22) | Frosted repaints the whole stage every frame (`hacks-level=2`). Lower levels left visible patches and saved nothing once windows redraw; window blur is the real cost |

---

## KI-01

**Settings-app Apply is reverted by the next full apply.**

**Symptom.** In Frosted (or Performance) you change the app tint, shell tint,
transparency, notification ground or window blur brightness and press Apply.
It works. Then:

- Reopening the settings window shows the **old** tint, or the old level in Performance.
- The next Apply that takes the full path (blur strength, popup brightness, corner rounding, a mode switch, any "Reapply settings") or an adaptive *restore* puts the **old** values back on the desktop.

**Reproduce (CLI).** The first incremental run after any source change falls
back to full, so run once to record the fingerprint:

```bash
./install.sh --settings-only --incremental -y --app-tint-color '#112233'   # records fingerprint
./install.sh --settings-only --incremental -y --app-tint-color '#445566'   # prints "Applying changed settings only"
cat ~/.config/aura-glass/app-tint-color                 # #445566
cat ~/.config/aura-glass/modes/frosted/app-tint-color   # #112233  ← stale drawer
./install.sh --settings-only --incremental -y --blur-strength 120          # unclassified → full
cat ~/.config/aura-glass/app-tint-color                 # #112233  ← reverted
```

**Root cause.** `install.sh`, the `--settings-only --incremental` branch, runs
the narrow actions and `exit 0` **before** `remember_glass_mode` →
`save_glass_mode_memos`. The `css` and `window-brightness` actions update the
top-level memos but never the drawer. The full path's `load_glass_mode_memos`
then prefers the drawer, and so do `Settings.__init__` (tints in both modes,
the level in Performance) and `apply_adaptive_blur restore`.

**Fix direction.** At the end of the narrow branch, when any action other than
`adaptive-blur` ran and `remembering` is true, save the drawer
(`save_glass_mode_memos`, or `remember_glass_mode`). The variables are already
resolved by then. Don't touch the drawer under `--adaptive-blur`.

**Verify.** The CLI sequence above keeps `#445566`. Add the
`check-incremental-drawer` fixture proposed in [CONSISTENCY.md](CONSISTENCY.md) §5.

---

## KI-02

**Adaptive restore breaks Performance mode.**

**Symptom.** In Performance mode, using the top-bar profile menu
(Performance → Full Glass or Auto), or any trigger clearing, leaves
Performance without its opaque shell sheet and with app-window blur switched
back on.

**Reproduce.**

```bash
./install.sh --settings-only -y --glass-mode performance
aura-glass-adaptive profile performance     # → install.sh --adaptive-blur active
aura-glass-adaptive profile full            # → install.sh --adaptive-blur restore
ls ~/.config/aura-glass/shell-80-solid.css  # gone
dconf read /org/gnome/shell/extensions/blur-my-shell/applications/blur   # true
```

**Root cause.** `apply_adaptive_blur` (`lib/steps-dconf.sh`) decides "the
baseline is already no-blur" only if the mode is `solid`, or
`$C/modes/<mode>/blur` or `$C/blur` holds 0. **No code writes either file**,
and `solid` is no longer a mode, so the guard never fires. `restore` then
re-applies the mode drawer with `WANT_BLUR=1 WANT_WINDOW_BLUR=1` and runs
`rm -f shell-80-solid.css`. The worker's own gate (`styling_enabled`) checks
only the legacy `styling-off` marker. The service is disabled in Performance,
but `aura-glass-adaptive profile` calls `sample(force=True)` directly.
`tools/check-adaptive-installer.sh` passes because it writes the
`modes/frosted/blur` file that production never writes.

**Fix direction.** Derive the baseline from `glass-mode` (`performance` means
no-blur) and drop the dead `blur` memo branches. Gate `sample()` in
`tools/aura_glass_adaptive.py` the same way, or hide or disable the menu in
Performance. Rewrite the check fixture to use a real Performance install.

**Verify.** The sequence above leaves `shell-80-solid.css` and every BMS key
unchanged.

---

## KI-03

**Mode switch on an existing install is partial.**

**Symptom.** You install in Frosted, then switch to Performance, and the panel,
overview, app folder, lock screen, window list, screenshot and dock are still
blurred. So Performance isn't zero-blur. The reverse: install in Performance
(or after `solid.ini` was loaded), switch to Frosted, and those surfaces stay
unblurred.

**Reproduce.**

```bash
./install.sh --settings-only -y --glass-mode performance
dconf read /org/gnome/shell/extensions/blur-my-shell/panel/blur      # still true
```

**Root cause.** `load_dconf` skips loading `core.ini` (and therefore
`solid.ini`) on an existing install ("existing extension settings preserved")
unless `--force` is given. The per-key `apply_*` that always run cover only
`popup/blur`, `popup/notification` and `applications/blur`. The other seven
components' `blur` keys are written only by a preset load or by the adaptive
path.

**Fix direction.** Make the mode own every component's `blur` key. When
`WANT_BLUR=0`, always apply `solid.ini`'s component keys. When it's 1, write
back the component keys `core.ini` enables, still preserving the user's other
extension settings. Mirror what `apply_adaptive_blur` already lists in
`bms_components`.

**Verify.** On a fixture where `blur-my-shell/pipelines` exists, frosted →
performance → frosted flips all ten components (CONSISTENCY §5,
`check-mode-switch`).

---

## KI-04

**Settings app needs pycairo, which nothing checks.**

**Symptom.** On Debian/Ubuntu with `python3-gi gir1.2-adw-1` (exactly what
`GUI_TOOLKIT_PKGS_DEBIAN` installs), the installer says the GUI is installed,
but `aura-glass-settings` dies with `ModuleNotFoundError: No module named 'cairo'`.
Reproduced in a clean Ubuntu container.

**Root cause.** `gui/aura_glass_settings.py` does `import cairo` at top level
(the radius preview drawing). `gui_toolkit_present` (`lib/distro.sh`) probes
only `gi`, `Gtk 4` and `Adw 1`, and the package lists omit pycairo. The setup
wizard doesn't import cairo, so it's unaffected.

**Fix direction.** Add `import cairo` to the probe and the cairo GI binding to
the package lists: Debian `python3-gi-cairo`, openSUSE `python3-gobject-cairo`,
Fedora `python3-gobject` (not `-base`), Arch `python-cairo` (pulled in by
`python-gobject`). Check each name per distro.

---

## KI-05

**Recommended/default pointer and icons disagree.**

See the table in [CONSISTENCY.md](CONSISTENCY.md) §3. The flagless default is
Adwaita, the text-wizard quick start uses AOSP, the GTK wizard and settings
app use Moga, and the text wizard's Customize step has no Moga option. Its
comment claims to match the GUI wizard's `Answers()`, but it doesn't.

**Fix direction.** Pick one recommended pair and state it once (for example as
a constant beside `VALID_*` in `install.sh`). Use it in both wizards and as
`Settings()`'s missing-memo default. Add Moga to the text wizard's pointer
step. Decide whether the flagless default should follow.

---

## KI-06

**Stale prose and labels in `install.sh` and the wizard.**

- The text wizard's Core list shows "Magic Lamp Effect". The pack now has Quick Settings Audio Panel instead.
- `--help`: `--full` says "all 14 extra extensions" (there are 8). `--window-blur` and `--gtk-apps-blur` call GTK-only "default", but the default is all apps. `--app-transparency` says "Off by default", but it resolves to 0.90.
- The comment in the quick-start branch says the defaults are `APP_BLUR_SCOPE=gtk`. The code says `all`.
- The GTK setup wizard's blur page reads "Frosted glass, or solid", and its "Solid" choice sends `--no-blur`, which now means **Performance** mode. The text wizard's summary also prints "Solid (No blur)".
- `css/shell-80-solid.css` says it's "installed only by --no-blur". It's Performance mode's sheet, and adaptive *active* installs it too.

Text-only fix. Keep the "why" comments accurate.

---

## KI-07

**Uninstall leaves commands behind.**

`install_css` installs `~/.local/bin/aura-glass-operation`, and `install_gui`
installs `~/.local/bin/aura-glass-preview`. `uninstall.sh` removes neither.
`~/.cache/aura-glass` (pinned checkouts, `operation.lock`) is removed only with
`--assets`. The extension list in `uninstall.sh` also carries the legacy UUID
`aura-glass-adaptive@aura-glass.local`. That one is harmless and intentional,
since `install_adaptive_performance` removes it too.

**Fix direction.** Add both commands to the "Removing aura-glass itself"
`rm -f`. Consider removing `operation.lock` in the base scope.

---

## KI-08

**Dry runs write.**

`--dry-run` is documented as changing nothing, but:

- `seed_glass_mode` (`lib/steps-modes.sh`) creates `$C/modes/<mode>/` and writes every field without a dry-run guard. `load_glass_mode_memos` can `rm -rf` and reseed a drawer. Both run for `--plan-json` too.
- `install_css` runs `ln -sf ~/.local/bin/aura-glass-apply ~/.local/bin/tahoe-glass-apply` unguarded.

`lib/steps-migrate.sh` (`conf_is_decoy`) already works around the first point.
Fix direction: guard with `remembering` / `DRY_RUN`, then simplify the
workaround.

---

## KI-09

**Launchers disagree on which copy to run.**

`bin/aura-glass-operation` prefers the checkout's `tools/aura_glass_operation.py`.
`bin/aura-glass-adaptive` and `bin/aura-glass-panel-blur` prefer the
**installed** copy in `~/.local/share/aura-glass/`. When fixing the adaptive or
panel worker, edits in `tools/` have no effect until a retune reinstalls them.
Restart the service after that. Either document this per launcher (done here)
or make all three behave the same.

---

## KI-10

**Packages page doesn't know Moga.**

`ICON_PACK_FAMILIES` in `gui/aura_glass_settings.py` lacks `Aura-Glass-Moga`,
so Moga variants under `~/.local/share/icons` are neither listed nor removable
there. `uninstall.sh --assets` does remove them.

---

## KI-11

**Misleading messages and an unneeded sudo prompt.**

- `refresh_bms_after_dconf` prints "refreshed after loading its pipelines" on GNOME ≥ 51, where it deliberately does nothing.
- `install_rounded_blur` prints "compiled … into ~/.local/lib" even when `gcc` failed (stderr is discarded and the result isn't checked).
- `install.sh` runs `sudo -v` whenever rounded blur is wanted, even though the default path (gcc + pkg-config) is rootless.

---

## KI-12

**Rootless rounded-blur, verify it loads.**

The rootless path builds `~/.local/lib/libblur-effect-1.0.so.1` and copies
`Blur-1.0.typelib` into `~/.local/share/girepository-1.0/` **only if a system
typelib already exists**. GNOME Shell doesn't search `~/.local` for typelibs or
libraries by default, and the "already installed" probe sets `LD_LIBRARY_PATH`
itself, so it may report success where the shell can't load it. Check on a
live session with `rounded-blur-found` in Blur My Shell, before relying on it.

**Reproduced** 2026-10-20 (GNOME 51.1). The rootless build was compiled with
`install_rounded_blur`'s own gcc line into a scratch prefix, then loaded with
`gjs` under `bwrap`, which hid the system package's typelib and library from
that one process and bound the build at the `~/.local` paths:

| Environment | Result |
|---|---|
| the shell's own (mutter's typelib and library dirs, nothing else) | `Typelib file for namespace 'Blur' … not found` |
| plus `GI_TYPELIB_PATH=~/.local/share/girepository-1.0` | typelib found, `libblur-effect-1.0.so.1` not found |
| plus `LD_LIBRARY_PATH=~/.local/lib` | loads |
| the installer's probe (`LD_LIBRARY_PATH` with `~/.local/lib`, no typelib path) | typelib not found |

The running shell's environment has neither variable. So on a machine without
the package the probe fails, the rootless path compiles, prints "compiled", and
Blur My Shell still falls back. Without the package there is also no system
typelib to copy, so `~/.local/share/girepository-1.0` stays empty.

**Fix** (decided 2026-10-20: root is fine). The rootless gcc path is gone.
`install_rounded_blur` uses the AUR helper or meson + sudo, which install where
the shell looks, and removes an old `~/.local` build. Both probes
(`install_rounded_blur` and `rounded_blur_needs_root`) dropped `~/.local/lib`,
so they ask what the shell can load, and `install.sh` asks for `sudo -v` up
front whenever the meson fallback will run.

---

## KI-13

**AUR packaging inconsistent with the repo.**

`packaging/aur/PKGBUILD` has these problems:

- `license=('GPL-3.0-or-later')`, but the repo is MIT.
- It installs `gui/aura-glass-settings.desktop` and `gui/assets/aura-glass.svg`, neither of which exists, so no desktop entry or icon is packaged.
- It installs to `/usr/share/aura-glass`, which `repo-path` then points at: a root-owned, non-git directory. The Updates page and `aura-glass-update-check` can't work there.
- `post_remove` points at `~/.config/aura-glass/uninstall.sh`, which is never installed.
- The `pkgver` example `2.4.0…` doesn't match the `v0.2.x` tags.

The README's `yay -S aura-glass-git` assumes the package is published, which
wasn't verifiable from here.

---

## KI-14

**Test-suite gaps.**

- `check-moga-cursors.sh` runs `install.sh --settings-only --dry-run` against the **real** `$HOME`. In a clean `HOME` it fails with "nothing installed yet". It isn't in the hook.
- `check-apply-lifecycle.py` and `check-overview-blur.sh` pass but aren't in `tools/hooks/pre-commit`.
- `check-adaptive-installer.sh` fabricates `modes/frosted/blur` (KI-02).
- No check covers KI-01, KI-03 or the defaults and parity drift.

Running the suite outside a GNOME session needs a `gnome-shell` on `PATH`
reporting a version, `XDG_CURRENT_DESKTOP=GNOME`, and PyGObject + Gtk4 + Adw +
pycairo (see [TESTING.md](TESTING.md)).

---

## KI-15

**Legacy `solid` / `transparent` machinery.**

No current flag reaches stand-down: `styling-off`, `stand_down_extensions`,
`modes/solid/disabled-extensions`, the stand-down branch of `aura-glass-apply`,
`restore_glass_from_solid` in the worker, and GUI comments about "three tabs".
A `glass-mode` memo of `solid` or `transparent` silently resolves to frosted.
The restore half is still useful for old installs. **Decide:** keep it as a
documented migration path (and its two checks), or remove it with a one-time
migration.

**Fix** (decided 2026-10-20: remove). `migrate_solid_era`
(`lib/steps-migrate.sh`) runs right after `migrate_legacy_names` on every real
run, so before the glass mode is resolved. It turns a `solid` memo into
`performance` and `transparent` into `frosted`, moves `backups/*.stood-down`
targets back (a target recreated since keeps the newer file), re-enables the
extensions in `modes/solid/disabled-extensions`, and deletes the marker and both
retired drawers. Gone: `WANT_STYLING`, `sync_styling_marker`,
`stand_down_extensions`/`glass_owned_extensions`, `aura-glass-apply`'s stand-down
and revive branches, the worker's `styling_enabled` and
`restore_glass_from_solid`, the panel worker's and the helper's `solid` checks,
and the dry-run line's `styling=` field. `check-solid-extensions.sh` and
`check-styling-off.sh` are replaced by `check-migration.sh` case 8.

---

## KI-16

**Full apply forces dark mode.**

`apply_gsettings` writes `color-scheme=prefer-dark` on every full run and full
retune, including GUI Applies that fall back to full. The theme is dark-only,
so this may be intended, but it overrides a later user choice of light, and
`aura-glass-icon-sync` exists precisely to follow light/dark. **Decide**
whether it belongs only to the first install.

---

## KI-17

**Housekeeping.**

- `origin` carries non-release tags `wip` and `zz-experiment`. The update check filters them, but RELEASING says not to push them. **Deleted** from `origin` and locally on 2026-10-20 (both on a stray commit `one`, not in `main`).
- `.claude/README.md` says `.claude/` is git-ignored. It isn't (it shows as untracked).
- `--plan-json` is implemented but no front end calls it yet. **Wired** 2026-10-20: the settings window's "N changes" popover opens on what Apply will run, from `--plan-json` for the pending flags.
- The settings app runs `aura-glass-adaptive refresh` via `PATH`. If `~/.local/bin` isn't on the session `PATH`, the games list is saved but the worker isn't told.

---

## KI-18

**A fresh frosted install from the text wizard or `--glass-mode frosted` comes out opaque.**

**Symptom.** On a machine with no `$C/app-transparency` memo:

- `./install.sh` (flagless) resolves the window level to **0.90**.
- `./install.sh --glass-mode frosted` resolves it to **0** (no transparency sheet, opaque windows).
- The text wizard's *Customize* path sets `--glass-mode frosted` internally and asks for 90/82/95 %, but **that answer is thrown away**. On an existing install the drawer's old value wins instead.

**Reproduce** (dry run, fresh `HOME`; note this also writes the drawer, see KI-08):

```bash
./install.sh --dry-run -y                       # glass-mode: frosted … transparency=0.90
./install.sh --dry-run -y --glass-mode frosted  # glass-mode: frosted … transparency=0
```

**Root cause.** `seed_glass_mode` seeds a new frosted drawer with
`app-transparency = ${disk_level:-0}`, which is 0 on a fresh machine.
`load_glass_mode_memos` then loads the drawer whenever
`APP_TRANSPARENCY_EXPLICIT` is unset. The text wizard assigns `APP_TRANSPARENCY`
and `APP_OPACITY` **without** setting `APP_TRANSPARENCY_EXPLICIT`, unlike the
GTK wizard, which sends `--app-transparency` as a real flag. Flagless runs
escape only because `GLASS_MODE` is still empty when `load_glass_mode_memos`
runs.

**Fix direction.** Seed the frosted level with the resolver's own default
(0.90, or 0.95 when window blur is off), not 0. Mark the text wizard's answers
explicit (`APP_TRANSPARENCY_EXPLICIT=1`, `APP_OPACITY_EXPLICIT=1`), the same as
the GTK wizard. Then add a `check-glass-modes.sh` case for a fresh
`--glass-mode frosted`.

---

## KI-19

**"Blur This App" touches a destroyed menu item, and re-checks it by a different rule.**

**Symptom.** After choosing *Blur This App* from a window's title-bar menu,
the journal gets pairs of GJS warnings, each with a stack trace into the
helper's `extension.js` (`_toggleBlur`'s callback):

```
Object St.Icon (0x…), has been already disposed — impossible to set any property on it.
Object Gjs_ui_popupMenu_PopupMenuItem (0x…), has been already disposed — impossible to access it.
```

32 such traces in one session on the audit machine. The toggle itself works.

**Reproduce** (live): open any app's window menu, click *Blur This App*, then
`journalctl --user -b | grep -A3 'already disposed'`.

**Root cause.** `_toggleBlur` (`extensions/aura-glass-blur@aura-glass.local/extension.js`)
runs `aura-glass-operation app-blur` asynchronously and, on success, calls
`item.setOrnament()` / `item.setSensitive()`. The window menu is destroyed as
soon as it closes, which is before the backend answers. Separately, that
callback recomputed the checkmark from the `enable-all` scope alone and the
root `wm_class`, while the menu builds it as
`whitelist || (enable-all && !blacklist)` over the whole class chain (the rule
the patched Blur My Shell `check_blur` uses).

**Fix.** Track the item's `destroy` signal and skip every write to it once it
fires; notifications still go out. Pass the class chain into `_toggleBlur` and
use the menu's rule for the post-success checkmark.

**Verify.** Toggle an app from its window menu after reloading the helper (next
login). No new `already disposed` lines; reopening the menu shows the same
checkmark the toggle left.

---

## Fixed

Fixed on 2026-10-15 and committed in that day's batch (`a1419f4` through `6a3adc1`). The entries above are kept for their reproductions.

**Live check, 2026-10-20** (GNOME 51.1, on the maintainer's desktop, through the
retune and the tray command): Frosted → Performance turned all ten Blur My
Shell components off, `hacks-level` 0, OSD alpha 100, `shell-80-solid.css` in,
and reloaded the shell and running GTK apps; Performance → Frosted left the
dconf dump byte-identical to the start (KI-03, KI-20). The tray Performance
profile on Frosted matched every mode-owned key of the Performance mode with
`glass-mode` still `frosted`, and Full restored a byte-identical dump (KI-21,
KI-25). Both tray profiles in Performance left dconf and both shell sheets
untouched (KI-02). An incremental `--app-tint-color` survived the next full
retune in the memo, the drawer and `gtk.css` (KI-01).

- **KI-01** — `install.sh`: the narrow `--incremental` branch now calls `remember_glass_mode` (not under `--adaptive-blur`). Verified with the fixture reproductions and the hermetic suite; verified live 2026-10-20 (below).
- **KI-02** — `apply_adaptive_blur` takes the no-blur baseline from the mode (`performance`); the worker skips `sample()` in performance (the `solid` half of the baseline went with KI-15); `check-adaptive-installer.sh` uses a real `glass-mode=performance` fixture. Verified with the fixture reproductions and the hermetic suite; verified live 2026-10-20 (below).
- **KI-03** — new `sync_mode_owned_keys` / `mode_owned_dconf_keys` (`lib/steps-dconf.sh`), run on the preserved-preset path: performance always gets `solid.ini`'s keys; frosted gets `core.ini`'s values back when coming from another mode. Verified with the fixture reproductions and the hermetic suite; verified live 2026-10-20 (below).
- **Chrome lost its window blur** — Two causes. (1) A working-tree edit pinned `[blur-my-shell/applications] opacity` to 255 (`apply_app_opacity`, install.sh normalisation, adaptive restore). Chrome and Electron paint an opaque background, so the actor opacity is the only way their blur shows; reverted to level × 255. (2) Present at HEAD too: `select_apply_actions` classed `--app-transparency`/`--no-app-transparency` as `css` only, so the settings app's incremental Apply rewrote the stylesheet and left the actor opacity stale. They now also add `app-opacity` (runs `apply_app_opacity`), asserted in `check-incremental-apply.py`. Verified live on 2026-10-15.
- **KI-04** — `gui_toolkit_present` imports `cairo`; Debian/openSUSE package lists add the cairo binding. Verified with the fixture reproductions and the hermetic suite; needs a live check.
- **KI-05** — Both wizards recommend Reversal + Moga with the same options in the same order; the text wizard gained Moga and its Complete Experience path moved from AOSP to Moga. A flagless `install.sh` deliberately keeps Colloid + Adwaita (decided 2026-10-15). CONSISTENCY §3 updated. Hermetic suite passes.
- **KI-08** — A dry run seeds and reads a scratch copy of `modes/` (`modes_root` / `MODES_ROOT`), thrown away on exit, so it resolves like the real run and writes nothing; the `tahoe-glass-apply` symlink goes through `run`. `check-glass-modes.sh` points `AURA_GLASS_DRY_MODES` at its fixture to keep asserting on seeded drawers. Verified with a fixture `HOME` (no file created) and the suite.
- **KI-16** — Closed as by design (decided 2026-10-15): the theme is dark-only, so every full apply keeps writing `color-scheme=prefer-dark`. The reason is now in `apply_gsettings` and in CLAUDE.md's "looks like a bug" list.
- **`dconf/core.ini` block-list comment** — the working tree had dropped the reason browsers and Electron apps are on the blacklist; restored and updated for all-apps mode.
- **KI-06** — `--help` (`--full`/`--all-extras` say 8 extensions; `--window-blur`/`--all-apps-blur` name all apps as the default; no "Off by default" on `--app-transparency`), the quick-start comment (`APP_BLUR_SCOPE=all`), the text wizard's Core list (Quick Settings Audio Panel) and summary ("Performance (No blur)"), the GTK wizard's blur page ("Frosted glass, or performance") and the `shell-80-solid.css` header. Text only; hermetic suite passes.
- **Settings app window-blur switch** — a working-tree edit had removed "Blur behind app windows" and the Popup brightness and Notification ground groups from the frosted page, so `_scope()` could not return `none` and any Apply on a no-window-blur install sent `--all-apps-blur`. Restored; the all-apps switch still defaults on. Needs a live check.
- **KI-07** — `uninstall.sh` removes `aura-glass-operation` and `aura-glass-preview`. Verified with the fixture reproductions and the hermetic suite; needs a live check.
- **KI-18** — `seed_glass_mode` seeds frosted at 0.90 (0.95 without window blur); the text wizard marks its transparency answer explicit. Verified with the fixture reproductions and the hermetic suite; needs a live check.
- **KI-19** — `_toggleBlur` guards the menu item with its `destroy` signal and re-checks it with the menu's own whitelist/blacklist rule over the class chain. Verified live 2026-10-20: two toggles left no `already disposed` line from `extension.js`. Each click still logs one `PopupMenuItem … already disposed` from GNOME's own `popupMenu.js:130` (the press-state handler on the window menu, which GNOME destroys on activate); it has no extension frames and shows for other window-menu clicks too.
- **Gray sheet over the wallpaper with Desktop Icons NG** ([#13](https://github.com/DevWebeloper/aura-glass/issues/13)) — DING's desktop window is a plain GTK4 `window.desktopwindow` that depends on its own 0.005-alpha background. The theme's and `gtk4-transparency.css`'s `window` / `window.background` ground matched it at equal specificity and painted it solid; the Overview hid it and a corner-rounding reapply brought it back. `css/gtk4-70-surfaces.css` now gives `window.desktopwindow` (two classes) its alpha back. Code-read against DING's source; **not reproduced** (DING is not installed on the dev machine) and needs a live check from the reporter. GTK3 DING builds are not covered.

---

## KI-20

**Mode switch leaves open GTK windows on the old opacity.**

**Symptom.** Frosted to Performance rewrote `gtk.css` (windows 1.00, popups and
banners opaque) but already-running GTK apps kept Frosted's translucent fill,
so with no blur behind them the wallpaper showed through until they were closed
and reopened.

**Root cause.** GTK reads user CSS at startup; `aura-glass-apply` only printed
"restart GTK apps".

**Fix.** `aura-glass-apply --reload-gtk` toggles `gtk-theme` (Adwaita and back)
when a GTK target changed and the theme in force is ours, which makes running
GTK3/GTK4 apps re-read their CSS live. The installer's CSS step and both
adaptive transitions pass it. A bare `aura-glass-apply` stays quiet, as
`tools/check-apply-publication.py` requires.

---

## KI-21

**Tray Performance profile leaves the shell on Frosted's sheet.**

**Symptom.** Choosing Performance from the top-bar profile menu turned blur off
but panel, menus and Quick Settings stayed translucent; the app's Performance
mode looked right.

**Root cause.** The adaptive `active` and `restore` transitions installed
`shell-80-solid.css` (or removed it) and re-spliced with `aura-glass-apply
--no-shell-reload`, so the running shell never loaded the change.

**Fix.** `apply_adaptive_blur` calls `aura-glass-apply --reload-gtk`; the shell
theme reloads when the shell CSS changed. Verified live: tray Performance and
Full both show the right sheet. The original flag was added against
actor-destruction and blur-recompile thrash; none seen.

---

## KI-22

**The settings app didn't say which glass is on.**

**Symptom.** Picking Performance or Frost Glass from the top-bar menu changed
the desktop, but the settings window showed nothing. Switching mode from the
window meant "click the other tab, then Apply".

**Root cause.** The top-bar menu sets the **adaptive profile**
(`$C/adaptive-profile`, `$C/adaptive-performance/`), never `glass-mode`, and
the window read neither. Its only `Gio.FileMonitor` filtered to System-page
stamps, so a real `glass-mode` change from the CLI was missed too. The update
check also replaced `self._applied` whole, which could leave a phantom pending
"Glass mode" change.

**Fix.** `gui/aura_glass_settings.py`:
- A status group above the Glass tabs: the mode in force (with "· Performance overlay" and the reason when the worker has it on), a "Switch to X" button that runs the ordinary Apply, and an "Adaptive performance" combo that runs `aura-glass-adaptive profile` (the panel menu's command).
- The header subtitle carries the same summary on every page.
- The banners on the other tab gained "Switch now".
- Two monitors (`$C`, `$C/adaptive-performance`) refresh it live and follow an outside `glass-mode` change, with a toast instead when edits are pending.
- The update check copies only `update_available`.

Smoke-tested off-screen; needs a live check.

---

## KI-23

**Install, update and uninstall audit (2026-10-15).**

Fixed:
- **Update terminal closed on failure.** The update script ran under `set -e` inside `keep_open`, so a failed `git pull` or install exited before the status line. Now chained with `&&`. `update-available` is removed after a successful install, so the window stops offering the update it just installed.
- **Offline update check died with 128.** Under `pipefail`, a failed `git ls-remote` in `$(...)` exited before the "offline?" message. Each pipeline now ends in `|| true`. The window toasts "Could not check" on exit 1 instead of "Up to date".
- **`check-update-channel.py` read the real `CONF_DIR`.** It now points the window module at the fixture.
- **The GUI toolkit offer never ran.** `ensure_gui_toolkit` read `DISTRO_FAMILY` before `preflight` set it. It now runs `detect_distro` itself.
- **Wizard summary.** An unreadable catalogue read "Minimal"; the text summary called Hatter "Colloid".
- **`multi_monitor_detected` counted every layout ever saved in `monitors.xml`.** It now uses `monitor_count`.
- **A mode round trip lost `panel-blur-fix`.** The memo now records the choice, not Performance's forced 0.
- **Failed `daemon-reload` aborted the run.** With no user manager, it stopped an install or uninstall midway; it is now `|| true` everywhere.
- **Dry runs still wrote.** The Tiling Assistant / user-theme queue writes and `aura-glass-gdm-sync --once` ran under `--dry-run` (KI-08).
- **`install_rounded_blur` said "compiled" after a failed gcc** (KI-11, second point).
- **Uninstall leftovers.** It now removes Copyous and the rootless rounded-blur build in `~/.local`.

Left as is:
- Tiling Assistant re-enabled on every retune: deliberate, commit 19ae4fa.
- The Flatpak override and `disable-extension-version-validation`: not reverted, because both may predate the install.
- `--no-window-menu`: still parsed and unused.

---

## KI-24

**Re-runs that don't reproduce every choice.**

Fixed (memos): "Install update" (`install.sh --gui`) and Full reinstall
(`--force --gui --yes`) run no wizard, and these choices had no memo, so they
came back as defaults. Each is now remembered where it is applied, under
`remembering()`, and read in `install.sh`'s resolution block (typed flag, then
memo, then default):
- the extension pack: `extension-pack` holds the chosen UUIDs (empty = Minimal). Written by `install_extensions` only when a flag or a wizard picked the pack, so an unanswered default keeps following the release's Recommended pack,
- `--no-osd`: `osd`,
- `--no-bms-git`: `bms-source` (`ego`) was written but never read; it is now,
- `--no-rounded-blur`: `rounded-blur-choice`, written only for the typed flags, because `--no-blur` forces the variable to 0 for a run without that being a choice.

The three opt-outs only move a value down: a remembered `1` is never read over
`--no-blur`. Uninstall removes all three new memos. Verified with a fixture
`HOME`: a Minimal memo stayed Minimal across a flagless `--gui --dry-run`, a
custom list came back as two UUIDs, a typed `--all-extras` beat the memo, and
the hermetic suite passes.

**Wizard parity drift** (fixed against the GTK wizard as canonical, decided
2026-10-15). The text wizard in `install.sh` now:
- asks Frosted or Performance first in Customize. Performance runs `parse_flags --no-blur`, the lone flag the window sends, and skips the detail questions,
- offers Full Experience (default, all 8) or Minimal for the pack, like the window. Core and Custom Selection are gone from the wizard; `--recommended` and `--extensions` still reach them,
- states Complete Experience's answers (frosted, all apps, 90%, popup blur, 20px pointer) the way `Answers.best()` sends them.

Left as is: the window's Performance sends `--no-blur`, while the settings app
sends `--glass-mode performance`. Those are different front ends for different
moments (first install vs a retune) and install.sh resolves both.
Verified in a pty against a fixture `HOME`: Performance + Minimal prints
"Performance (No blur)" and 0 extensions; Frosted + Full prints 8; Complete
Experience prints 20px and all apps at 90%. The hermetic suite passes.

---

## KI-25

**Tray Performance profile is a hand-kept subset of the Performance mode.**

**Symptom.** Choosing Performance from the top-bar menu looked worse than the
app's Glass mode switch, and Full did not always bring back exactly what
Frosted had.

**Root cause.** `apply_adaptive_blur` (`lib/steps-dconf.sh`) re-implemented a
slice of the switch instead of running it. Diffing a fixture `HOME` after
`--adaptive-blur active` against one after `--glass-mode performance` (both
from the same Frosted install) showed:
- `shell-80-solid.css` was the raw `css/` copy: not rescaled to the level, not tinted, not corner-matched to the radius preset (`apply_popup_transparency` and `apply_radius_css` never ran).
- `gtk4-transparency.css` was deleted at level 1.00, so GTK apps got plain libadwaita instead of the mode's opaque darkened ground.
- `blur-my-shell/hacks-level` stayed at 2 (a full-screen repaint every frame, the cost Performance exists to remove) and `custom-osd/alpha` stayed at Frosted's 60.
- `restore` copied the sheets back from `css/` without the rescale and radius steps, and re-read the drawer by hand.

**Fix.** The transient transition now resolves like the mode it stands in for
and runs the switch's own steps:
- `install.sh`: `--adaptive-blur active` sets `GLASS_MODE=performance` (not when styling stood down), and every transition resolves against a scratch copy of the drawers (`MODES_ROOT`, as a dry run does) so it reads the performance or remembered mode's drawer without creating or reseeding one.
- `apply_adaptive_blur`: `active` saves the keys a mode owns (`mode_owned_dconf_keys`, i.e. everything `dconf/solid.ini` sets, now including `hacks-level` and the OSD alpha) to `adaptive-performance/saved-mode-keys`, then runs `load_dconf` and `install_css`. `restore` writes them back, then runs the same two steps for the remembered mode. A `saved-bms-blur` left by an older release is still read once.
- `refresh_bms_after_dconf` returns early for an adaptive transition so a restore cannot cycle Blur My Shell on GNOME 48-50.
- `tools/check-adaptive-installer.sh` now builds a real Frosted install and asserts that `active` equals a Performance switch (sheets, `gtk.css`, every dconf row), that `restore` equals the Frosted install, that no memo or drawer moves, and that a per-component choice survives.

Not equal on purpose: the memos and drawer (an overlay is not a mode),
`adaptive-performance/*`, and the panel-blur-fix user service, which a real
Performance install disables and the overlay leaves to stand itself down.

---

## KI-26

**Notification banners sometimes arrive with no visible blur.**

**Symptom.** Some banners show their tinted ground with nothing frosted behind
it, or a faint blur that only sharpens when the pointer passes over the
banner. The next banner may be fine.

**Root cause** (code-read against GNOME 51 `messageTray.js`, not traced live).
`_showNotification()` puts the banner bin at `y = -height`, opacity 0, scale
0.9, and eases it in over 200ms. The blur surface
(`components/popup/blur_surface.js`, `update_live_surface()`) follows it from
`BEFORE_REDRAW` laters, which run before the stage relayout, so every pass
reads geometry and opacity a frame old. `notify::*` from the tween's last frame
is dropped while a transition later is armed. The patch's `was_transitioning`
re-run only fired if a pass had *succeeded* while the tween ran, and it ran
again from a later, still before layout. Which frame the tween ended on
decided whether the blur settled at the banner's final opacity and box. Two
further cases always lost it:
- `surface_fade.js` `get_banner_position_alpha()` measured the banner against
  the top bar even when the bar was hidden (fullscreen window on that monitor,
  autohiding bar): the tray then fills the monitor, the banner rests 10px from
  its top, and its blur came out at about a fifth of its opacity or zero.
- The same function compared a banner on another monitor with the bar's.

**Fix** (`patches/blur-my-shell-notifications.patch`).
- `'transitions-completed'` on the banner and each ancestor up to the overlay
  parent queues `queue_settle_update()`: one pass from an idle, after the final
  frame has been laid out and painted, not gated on the transition later.
  Replaces `was_transitioning`.
- `get_banner_position_alpha()` returns 1 when `Main.panel` is not mapped or
  the banner is on another monitor.
- With Blur My Shell's `debug` key on, the banner surface logs each change of
  outcome (hidden and why, waiting, shown with its final opacity and box) to
  the journal.

**Verify.** Rebuild Blur My Shell (the patch stamp changed, so a full
`./install.sh` rebuilds it; a retune does not), log out and in, then:

```
dconf write /org/gnome/shell/extensions/blur-my-shell/debug true
journalctl --user -f | grep 'popup blur'
for i in $(seq 10); do notify-send "test $i" "body"; sleep 7; done
```

Every banner should end on `shown: opacity 255`. A banner without blur now
leaves the reason in the journal. Turn `debug` off afterwards.

**Verified** 2026-10-20 on GNOME 51.1, two monitors: 8 of 8 banners logged a
settle pass after the tween and ended on `shown: opacity 255`, with no JS errors.
The fullscreen and hidden-bar case was not exercised.

---

## KI-27

**History cards never get rounded blur corners without gnome-rounded-blur.**

`attach_blur()` in the patched `message_stacks.js` used
`MESSAGE_CORNER_EFFECT_NAME`, which was never declared. Where the blur effect
can't round its own corners, the `ReferenceError` came straight after the blur
was added, the `catch` swallowed it, and the card kept a square blur under a
rounded card. `detach_blur()` threw the same way after removing the blur.
Latent on machines with gnome-rounded-blur (`rounded-blur-found=true`).

**Fix.** Declare it (`aura-glass-message-corner`).

---

## KI-28

**The helper never sees adaptive `active` change.**

`_initOpacityMonitor()` in the helper's `extension.js` watched
`~/.config/aura-glass` and filtered for `active`, but that file lives in
`adaptive-performance/`, and a directory monitor reports only its direct
children. Adaptive transitions therefore never refreshed the window opacity
the helper owns (scopes where Blur My Shell's application blur is off).

**Fix.** A second monitor on `adaptive-performance/`. Both watch moves, since
the worker and the installer replace files by rename. Needs a live check after
the helper reloads (next login).

---

## KI-29

**No check covers the Blur My Shell patches.**

The hook syntax-checks shell, Python and the preview driver, but nothing
applies the three `patches/blur-my-shell-*.patch` to `BMS_REF` or parses the
result, so a patch that no longer applies or references an undefined name
(KI-27) is only found on a user's desktop. **Direction:** a hermetic check that
applies the patches to a clean checkout of the pin and runs a parse plus an
undefined-name pass over the touched files.

**Fix.** `tools/check-bms-patches.sh`, in the hook. It clones from the
`$SRC_CACHE` copy (no network) and skips when there is none. Run against the
previous patch it reports KI-27's `MESSAGE_CORNER_EFFECT_NAME`.

---

## KI-30

**A gnome-shell update silently reverts the login-screen theme.**

`install_gdm` compiles the theme into the distribution's
`gnome-shell-theme.gresource` (`tweaks.sh -g`, with `#lockDialogGroup` pointing
at `/usr/share/backgrounds/aura-gdm.png`). That file belongs to the gnome-shell
package (or Yaru/Pop/Zorin's theme package), so any install or update of it puts
the stock file back. The login screen loses the theme and the wallpaper, and the
sync service keeps writing `aura-gdm.png` for a theme that no longer reads it.
Seen 2026-10-21 after a gnome-shell reinstall on CachyOS.

**Fix.** `record_gdm_gresource` (`lib/steps-gdm.sh`) finds the installed file by
the wallpaper URL in its CSS among WhiteSur's candidate paths and writes its
checksum to the `gdm-gresource` memo, in `sha256sum` format. `aura-glass-gdm-sync`
checks it at login (and on `--once`, which every install run calls) and, on a
mismatch, prints a warning and sends a notification asking for
`install.sh --gdm`. It only warns: repairing needs root and a rebuild against
the new shell. Uninstall removes the memo. An install from before this fix has
no memo until its next `--gdm` run. Verified with a fixture (`AURA_GLASS_CONF`,
stub `notify-send`): quiet when the file matches or there is no memo, warns
once replaced. No pacman hook: restoring a saved gresource after a major shell
update would put CSS built for the old shell on the new one.

---

## KI-31

**The overview sometimes keeps a stale blur after leaving a settings-app
preview.** Reported 2026-10-21: after changing a setting in the settings app,
the overview "sometimes" did not show it.

**Cause** (code-read against Blur My Shell v73). `aura-glass-preview revert`
restored the blur-my-shell subtree with `dconf reset -f` then `dconf load`.
Between the two, `pipelines` is Blur My Shell's own default, which has none of
the project's pipelines. `PipelinesManager.on_pipeline_update` emits
`pipeline-destroyed` for each, and every `Pipeline` on one of them
(`conveniences/pipeline.js`) moves itself to `pipeline_default`. The load
brings the pipelines back, but a returning id only gets `pipeline-created`,
which no `Pipeline` listens for. Whether the overview recovers then depends on
the order its own `overview/pipeline` key change and the `pipelines` change
arrive in, hence "sometimes". Blur My Shell's warnings do not reach this
machine's journal, so there is no log of it.

**Fix.** `cmd_revert` loads the snapshot in one `dconf load` (one change set,
no pipeline ever missing) and then resets only the keys the snapshot does not
have. Verified on a throwaway dconf path: changed, added and nested keys all
return to the snapshot byte for byte. `tools/check-preview.sh` passes against
the live install.

---

## KI-32

**Updating from the settings app greys out Install or stops at a git error.**
Reported 2026-10-22: users see Install disabled, or a git message about a
different HEAD or the worktree, and cannot get to the release.

**Cause.** The Updates page ran `git pull --ff-only` and, before it,
`update_blockers` refused any checkout that was not a clean branch tracking a
remote. Real checkouts are often a release tag checked out by hand (detached
HEAD), carry a hand-edited file (dirty tree), have a `main` someone committed on
(diverged), or hold a tag that was re-cut on the remote (fetch refuses to
clobber it). Each one either greyed Install out or stopped the pull.

**Fix.** `bin/aura-glass-update <tag|branch>` replaces the pull. It fetches with
`--force --tags`, stashes local edits under an `aura-glass update` message,
keeps local commits on `aura-glass-backup/<branch>-<timestamp>`, then checks
out the tag detached or resets the branch to `origin/<branch>` with tracking,
and runs `install.sh --gui`. `update_blockers` keeps only the cases with
nothing to switch: no checkout, a package, no `origin`. The Updates page now
lists every release (GitHub notes, or commit subjects as a fallback), `main`'s
unreleased commits and a history graph, each with its own Install, so any
version can be picked, including an older one. `tools/check-update-channel.py`
covers a dirty detached HEAD, a diverged `main` and a re-cut tag.

---

## KI-33

**The helper's opacity sync crashed.**

**Symptom.** The journal logs `ReferenceError: mode is not defined` from
`_updateOpacityFromConfig` (`extensions/aura-glass-blur@aura-glass.local/extension.js`)
at every enable and every Blur My Shell state change. In Performance, where
Blur My Shell's application blur is off, the window opacity that branch exists
to set was never applied.

**Root cause.** The branch compared a `mode` that nothing in the function
declared.

**Fix.** Read `glass-mode` with `readState` first. Verify: no ReferenceError in
`journalctl --user -b | grep aura-glass-blur` after the next login.

---

## KI-34

**Retunes rewrote what they did not change.**

**Symptom.** A flagless `./install.sh --settings-only -y` made 37 dconf and
gsettings writes (logged 2026-10-22 with wrapper scripts first on `PATH`), every
one to the value already there. dconf stores and announces a write whether or
not the value changed, so each one woke its listener: Blur My Shell rebuilt
pipelines and effects, User Themes reloaded the shell theme, GTK re-read icons,
cursor and fonts. That is a flicker and a GPU spike for a retune of nothing, and
the adaptive worker's transitions paid it twice.

**Root cause.** `run` executed every write, and the inline Python pipeline
writers compared the blob as text, while dconf prints a double back in full
(`0.7` as `0.69999999999999996`), so the window brightness writer rewrote the
whole `pipelines` key every run.

**Fix.** `run` skips a `dconf write` or `gsettings set` whose value is already
in place (`already_in_place`, `same_gvariant` in `lib/common.sh`: same text,
numbers equal by value, or structured values equal once GLib parses them). Dry
runs still print every write. The five pipeline writers compare doubles by
value, and `apply_wiggly_cursor` writes the cursor path only when it moved.
Verified live: a no-op retune makes 0 writes and leaves `dconf dump /`
byte-identical; a brightness change makes exactly its 2 writes.

---

## KI-35

**Frosted repaints the whole screen every frame. Kept on purpose.**

**What it costs.** Blur My Shell's `hacks-level=2` turns clipped redraws off,
so any damage repaints the whole monitor and every blur actor on it.

**What was tried** (live, RX 7600, 3440×1440 at 180 Hz plus the laptop panel,
2026-10-22, shipped on main for a few hours as `--blur-refresh`):

- `hacks-level 0` with a stage repaint from the helper after activity. Faint
  patches showed in the blur wherever something kept moving, because Shell's
  background blur blits its whole box while only the redraw clip is fresh.
- `0` plus repainting the whole blur of each blurred window stacked over a
  damaged one, in that frame. Correct, and no cheaper than 2.

Back to back with a YouTube video and a streaming window on screen: 2 at
53–57%, 0 at 60–63%, 0 with the window repaint at 65%. Window blur itself is
the cost: off 11%, on 55%, about five points per blurred window. A blurred
window that redraws has its whole blur recomputed whatever the level.

**Decision.** Always 2 in Frosted. `pin_frosted_hacks_level` writes core.ini's
value on every frosted run, which also brings back an install that the
short-lived flag left at 0, and drops its `blur-refresh` memo. The flag is
gone; `uninstall.sh` still removes the memo.

---

## Phase 3 fixes (2026-10-20, `07689ba`)

- **KI-09** — `bin/aura-glass-adaptive` and `bin/aura-glass-panel-blur` now prefer the checkout's `tools/` worker when run from a checkout's `bin/`, like `aura-glass-operation`. The copies in `~/.local/bin` have no `tools/` beside them, so the services keep the installed worker. `AURA_GLASS_ADAPTIVE_WORKER` still wins.
- **KI-10** — `ICON_PACK_FAMILIES` knows `Aura-Glass-Moga`. Its nine accent variants are one row (`SINGLE_ROW_FAMILIES`), in use when any variant is, because the accent switch moves between them.
- **KI-11** — On GNOME ≥ 51, `refresh_bms_after_dconf` says it skipped the reload instead of "refreshed". `install.sh` asks for `sudo -v` for rounded blur only when `rounded_blur_needs_root` (library not already loadable, no AUR helper, meson present).
- **KI-13** — `PKGBUILD`: `license=('MIT')` plus the license file, `install=` now references `aura-glass.install` (its hooks never ran), the desktop entry is generated with the app id and the icon comes from `gui/icons/`, and `pkgver` matches the `v0.3.x` tags. The removal hint moved to `pre_remove`, while `/usr/share/aura-glass/uninstall.sh` still exists. `package()` was run against the checkout into a temp `pkgdir`. The package copy is root-owned and not a git checkout, so `package()` now writes `.packaged` (name, `pkgver`, URL): `aura-glass-update-check` compares the `.g<sha>` in `pkgver` with `main` on that URL, and the Updates page names the package and points at the package manager instead of offering a pull. Three cases in `check-update-check.sh`.
- **KI-14** — `check-apply-lifecycle.py`, `check-overview-blur.sh` and `check-moga-cursors.sh` are in the hook. The Moga check's dry run uses a fixture `HOME`, so it's hermetic now.
- **KI-17** — The settings app runs `aura-glass-adaptive refresh` through the same `~/.local/bin` then checkout lookup as the profile combo, not `PATH`. `.claude/` is ignored here (global excludes). The remote `wip` and `zz-experiment` tags are deleted, and `--plan-json` drives the Apply popover's first row.
- **KI-23 leftover** — `--no-window-menu` works: `install_aura_ext` remembers it as `window-menu`, `install.sh` reads the memo back, the helper reads it live through its config monitor and adds or drops "Blur This App" without a reload, and uninstall removes the memo.


## Contributor and issue fixes (2026-10-20)

- **Blur My Shell lifecycle (PR #17)** — list and scope edits recheck tracked windows instead of rebuilding every pipeline. Full rebuilds untrack first, sticky windows are tracked once, window-state and static X11 `child-added` handlers belong to tracking and go on disable, `disable` cancels a pending blur-type `enable`, and the focused window keeps dynamic opacity across a rebuild. The allow list applies at once in all-apps mode, and the popup switch retargets live surfaces while notifications hold the component. Regenerated the subwindows and notifications patches against `BMS_REF`. Offline tests in `tests/` (`BMS_TEST_SOURCE` for the patched-source ones). Verified live (2026-10-20, fresh login on GNOME 51.1): no Blur My Shell errors in the journal; 20 blacklist and 10 allow-list edits, four scope flips and popup and notification toggles logged nothing, left `gnome-shell` RSS flat across the list edits and cost no more CPU than the shell's idle load; `tools/preview.sh` rendered window, quick-settings and notification blur with the new build.
- **Packages page placeholder (PR #17)** — an empty system group's placeholder row has no `_owner`, and `_own_next_pack` raised on it. It now skips rows without one, as `_size_next_pack` already did for `_sized`.
- **Service workers (PR #15)** — `aura-glass-panel-blur` checks the operation lock without blocking before it rebuilds, so a theme operation in flight defers the rebuild instead of a 30 s wait, a `RuntimeError` and a systemd restart loop. The adaptive worker takes `~/.cache/aura-glass/adaptive-worker.lock` and logs a failed sample instead of exiting. `aura-glass-gdm-sync` kills its monitor subshells on exit and drains event bursts before one sync. Verified live (2026-10-20): with the operation lock held 40 s the panel worker rebuilt one second after release with no restart, a second adaptive worker exited at once, a transition under a held lock logged `sample error` and applied after release, and four wallpaper-key changes 0.2 s apart produced one GDM wallpaper write. The PR's skip of the installer's post-apply `refresh` while the service runs was left out, because it would delay the downshift after a full apply.
- **`--no-blur` (PR #16, not merged)** — the PR made bare `--no-blur` stay frosted. That reverses the recorded decision (`--no-blur` ⇒ performance, ARCHITECTURE §resolution) that `check-glass-modes.sh` on `main` asserts.
- **SassC deprecated (#9)** — `missing_cmds` accepts Dart Sass's `sass` for `sassc`, and `install_theme` gives the pinned theme installer a `sassc` shim forwarding to `sass --no-source-map`. The Tahoe targets compiled both ways differ only in whitespace and in three status colours written as `rgb()`, none of them an accent blue that `aura-glass-apply` rewrites by hex. Verified live (2026-10-20): the pinned theme installer built `gtk-4.0/gtk.css` in a fixture `HOME` with `sassc` off `PATH`. `sassc` is still the package offered, since every supported family ships it.
- **Copyous clipboard entries missing** — Copyous 2.1.2 (and upstream main) calls `entry.connectObject('notify::content', …)` in `TextItem` with no tracking object, so the shell logs `No object to track signals` and that entry is never built. `patch_copyous_extension` now passes `this`, the object its `destroy()` already disconnects. Checked apart from the old GLSLEffect marker, which 2.1.2 no longer has, so that older edit is now a no-op apart from `shell-version`. Verified live (2026-10-21, after a reboot): Copyous loaded its history with no `No object to track signals` errors in the journal.
- **Copyous Super+V dialog opaque** — Blur My Shell already blurred behind it (its `.clipboard-dialog` box is a `.modal-dialog`), but Copyous paints that box an opaque `#36363a` from a stylesheet it loads itself, and St ranks every extension-loaded sheet above the shell theme whatever the specificity or `!important` (`get_origin` in `st-theme.c`), so no rule in `gnome-shell.css` could reach it. `.modal-dialog.clipboard-dialog` now sits in the dialog lists of `shell-50-dialogs`, `shell-popup-blur` and `shell-80-solid`; `aura-glass-apply` copies those rules, tinted and radius-rewritten, into `$CONF_DIR/extension-overrides.css`, and Aura Glass Helper loads that as an extension sheet, where the second class outranks Copyous's one. Copyous's own Custom theme was tried first and frosted it, but its template fixes the corner at 18px against the blur's `dialog-corner-radius`. The Helper change needs a re-login to load.
- **GDM login wallpaper spanned across monitors** — the greeter builds no per-monitor backgrounds (`layout.js` `_updateBackgrounds` returns early when `sessionMode.isGreeter`), so the GDM theme's `#lockDialogGroup` `background-image` with `background-size: cover` stretched one image over the whole stage. Both generators (`generate_gdm_wallpaper` in `lib/steps-gdm.sh` and `bin/aura-glass-gdm-sync`) now lay the image out like the stage: one zoomed copy per logical monitor from Mutter's `GetCurrentState`, on a canvas the size of the stage's bounding box (capped at 3840 px wide), so `cover` maps it back 1:1. One monitor keeps the old single image. The sync service also rebuilds it on `MonitorsChanged`. Relies on GDM getting the user's layout (`sync_monitors`). The unlock screen in the session was never affected: Blur My Shell's lockscreen pipeline draws per monitor. Generated image checked on the two-monitor dev machine (2026-10-21); needs a look at the login screen.
- **Window blur offset in screenshots** — with dynamic app blur on a mixed-scale layout (eDP at 1.67 beside DP at 1.0), the blur behind a window sampled the wrong part of the stage in a screenshot (a blue wallpaper area showed a red-tinted blur). Blur My Shell's dynamic blur is `Blur.BlurEffect` from gnome-rounded-blur when that library loads, else `Shell.BlurEffect`; both carry the same `update_actor_box`, which in an off-stage paint (no stage view) assumes scale 1 at the stage origin. A screenshot paints through `clutter_stage_paint_to_framebuffer` with the viewport at `-(rect.x * scale), -(rect.y * scale)` and `stage width * scale` wide, so the blit landed elsewhere whenever the capture was scaled or started past 0,0 (a capture of the ultrawide starts at x=1536). Fix: read the scale and origin back from the framebuffer viewport in that branch. `patches/gnome-rounded-blur-offstage.patch`, applied by `install_rounded_blur` to the pin; on Arch it builds a `1.0.2-1.1` pacman package (one pkgrel above the AUR's, so a helper upgrade keeps it) instead of going through an AUR helper, which cannot take a patch. The `rounded-blur-patch` stamp makes an install without it rebuild once, so the next full install asks for sudo on machines that had the AUR package. Verified live 2026-10-21 with the same patch built by hand: the screenshot blur matched the screen on both monitors. The installer path was run in a fixture `HOME` with `sudo` stubbed: one build, one `pacman -U`, the same file list as the AUR package, and a skip on the second run. The AUR helper used to bring the build dependencies; `ensure_rounded_blur_build_deps` now offers them per family (package names checked against Fedora rawhide, openSUSE Tumbleweed and Debian's indexes; the commands checked with a stubbed `sudo`, not run on those distros). `rounded_blur_loadable` puts every `mutter-*` directory (`/usr/lib`, `/usr/lib64`, Debian's multiarch) on the library path, where it used to add only Arch's `/usr/lib/mutter-$GNOME_MAJOR` and `mutter-18`: on Fedora, openSUSE, Debian and GNOME 48/49 the probe failed on a working install and every full run rebuilt it. GNOME Shell's own `shell-blur-effect.c` has the same code, but Blur My Shell does not use it while gnome-rounded-blur loads, so it is left alone.
- **Brightness write fails under a decimal-comma locale** ([#18](https://github.com/DevWebeloper/aura-glass/issues/18)) — `apply_popup_brightness` and `apply_window_brightness` formatted the level with `awk printf "%.2f"`. Debian's awk (mawk) follows `LC_NUMERIC`, so under `fr_BE.UTF-8` it printed `1,15` and `dconf write` failed with `1:expected end of input`, which aborted the settings app's Apply. Both calls, and the number comparison in `same_gvariant` (`lib/common.sh`, which would otherwise read `1.15` as `1` and skip a real change as already in place), now run awk under `LC_NUMERIC=C`. Reproduced with a scratch `fr_BE.UTF-8` locale and `gawk --posix` (prints `1,15`, `1.15` with the fix); the reporter confirmed `LC_NUMERIC=C` fixes it on Debian 13. The `same_gvariant` half is inferred from mawk using the locale for its output and not reproduced (gawk reads `-v` numbers with a dot even in POSIX mode, and mawk is not on the dev machine). The Python writers format with `%`, which ignores the locale.
- **Giant cog on the login screen's session button** — GNOME 50 replaced the session list with `js/gdm/authMenuButton.js`, so the bottom-right button that picks the session (GNOME, Gamescope, …) and the lock screen's Login Options button are `.login-dialog-button.login-dialog-auth-menu-button`. The pinned WhiteSur GDM theme and the Aura-Glass shell theme style only the old `.login-dialog-session-list-button`: no rule in the installed GDM gresource named the new class, so its `StIcon` used St's 48px default, about three times the accessibility button beside it, at any display scale. Stock GNOME 51's CSS lists the new class next to the old one. `css/shell-50-dialogs.css`, which `install_gdm` already appends to the GDM CSS, now sizes it like its neighbour in each theme (WhiteSur's `.a11y-button` on the login screen, the Aura-Glass `.switch-user-button` on the lock screen) and gives the popup and indicator icons stock GNOME 51's sizes. Reaches the login screen only on the next `install.sh --gdm`; the lock-screen copy arrives with `--settings-only`. Found by extracting the installed gresource and the `gnome-shell` 51.1 package's; needs a look at the login screen.
- **Laptops installed undocked never got the panel blur rebuild** — with no flag and no memo, `install.sh` turned `panel-blur-fix` on only when `monitor_count` saw more than one screen. A laptop installed with nothing plugged in counted one, got `0` remembered, and then lost its panel blur every time an external monitor was connected or removed, until Blur My Shell's panel switch was toggled by hand. The default now also turns it on when DRM has a built-in panel connector (`eDP`, `LVDS` or `DSI`; `has_builtin_panel` in `lib/common.sh`, mirrored in the settings app's missing-memo default). An existing install keeps the `0` it remembered, which looks the same as a deliberate `--no-panel-blur-fix`, so it needs one run with `--panel-blur-fix`.
- **Top bar blur strip after login, and a flash on every fix** — Blur My Shell's static panel blur is a copy of the monitor's wallpaper in an actor sized to that monitor when the blur is built; `update_size` only moves and clips it. On a monitor change upstream sets a dirty flag and calls `reset()` on the next `workareas-changed`. When no work-area change follows (a docked laptop's second monitor settling at login, at fractional scale), the copy keeps the old size and part of the bar shows blur that does not line up with the wallpaper. When it does follow, `reset()` is `disable()` then `enable()` a timeout later, and `disable()` takes the panel's style classes off, so the bare bar flashes; the `aura-glass-panel-blur` service's `false`/`true` toggle does the same. `patches/blur-my-shell-panel-refit.patch` replaces the dirty flag: after every `monitors-changed`, and once after `startup-complete`, it waits for the frame that allocates the new layout, then builds a new blur for any static panel whose monitor index or size changed, places it, and drops the old one in the same main-loop pass, leaving the style classes alone. Other panels are only re-clipped. The geometry handlers are tracked per blur so the swap drops only its own on the shared `uiGroup`. Verified live (2026-10-25, GNOME 51.1, eDP-1 at 1.67 beside DP-1 at 1.33): with the rebuild service switched off, a fresh login showed a clean bar with no strip and no flash. The service is retired: `remove_panel_blur_unit` takes out its unit (all three names it has had), command, worker and `panel-blur-fix` memo on every run, retune included; the settings app's switch and the `--panel-blur-fix` default are gone, and the two flags are accepted and ignored.
- **Login wallpaper misplaced after a display scale change** — `aura-glass-gdm-sync` copied `monitors.xml` to GDM and re-laid-out the GDM wallpaper on `MonitorsChanged`. Mutter emits that as soon as a new layout is applied but writes `monitors.xml` only when it is kept (`meta_monitor_manager_confirm_configuration` calls `meta_monitor_config_manager_save_current` on "Keep Changes", up to 20 s later), so the copy took the layout being replaced while the wallpaper was cut for the new one: the greeter came up at the old scale under per-monitor tiles placed for the new scale. The service now also runs `gio monitor` on `~/.config/monitors.xml` and syncs both when the file is written (mutter's atomic rename shows up as an event). The three watchers each render through `mktemp` instead of a shared `/tmp/aura-gdm-sync-$$.png`, since subshells share `$$`. Verified live (2026-10-25): an atomic rewrite of `monitors.xml` rebuilt `aura-gdm.png` two seconds later with no temp file left. That alone did not fix the login screen: the lock screen (Super+L) was right and a full logout still came up at the old scale. GDM runs the greeter as a dynamic user (`/var/lib/gdm/.migrated-dyn-users`) with its config home in `/var/lib/gdm/seat0/config`, a 0700 directory it owns, and `sync_gdm_monitors` had copied `monitors.xml` in there (and into `seat0/.config`) with sudo at install time. Mutter loads `/etc/xdg/monitors.xml` and then the config home's file over it, key by key (`meta_monitor_config_store_reset`), so that copy pinned the greeter to the install-day layout. The sync service runs as the desktop user and can reach only `/etc/xdg` and `/var/lib/gdm/.config`. `sync_gdm_monitors` now removes the two `seat0` copies (`drop_gdm_seat_monitors`) instead of writing them, so the greeter falls back to `/etc/xdg/monitors.xml`. Existing installs get that on the next full run with the `gdm-monitors-synced` memo; a retune has no sudo and does not. A side effect, reported on the dev machine (2026-10-25): the screen no longer blanks when it switches between the login screen and the session. With the greeter on the install-day configuration, each switch was a modeset; with both on the same layout there is nothing to reprogram. The rest of the scale audit: Blur My Shell's static dock blur has the same frozen-size pattern the panel had (rebuilt only on a monitor index change), covered in practice because Dash to Dock recreates its docks on a monitor change; `shell-90-density.css` is measured from the primary monitor's scale at install time only, so a later scale or primary change leaves it stale until the next retune.
- **Cursor packs on GNOME 51** — `ensure_scalable_cursors` turned every Xcursor in a pack into a PNG wrapped in an SVG under `cursors_scalable/`. That was meant as the Moga fix for GNOME 51, but nothing on GNOME reads that directory. Mutter 51.1 still draws the pointer from Xcursor files (`meta-cursor-xcursor.c`, through its bundled libXcursor lookup, which follows `index.theme` Inherits). GTK 4.24 hands the pointer to Mutter through `wp_cursor_shape_v1`. The one reader was Wiggly's `cursor-path`. The wrapper also took its blue channel from green. Removed. `sync_cursor_theme_files` deletes the old wrappers from the `Aura-Glass-Moga-*` packs. The `~/.icons/default`, `~/.icons` symlinks and GTK `settings.ini` sync that came with the GNOME 51 work stays, for XWayland and legacy clients. AOSP installed and applied live with `--settings-only` (2026-10-25); the pointer on screen needs a look from the user.
- **Wiggly: shrink snapped at the end, growth off the tip, wrong or default picture** — Wiggly 10 measured the pointer once, at enable, from the sprite texture, so on a scaled monitor (1.33 and 1.67 here) the shrink ended larger than the pointer and snapped down, and a theme or size change was never seen. Its ease also animated `pivot_point` in from the top-left corner, so the growth drifted off the tip (upstream issue Arch-Lover/wiggly#2). It draws only the SVG in `cursor-path`, so a theme without one, or set outside this project, showed its bundled black arrow (Arch-Lover/wiggly#3). AOSP hit that even here: its vector default is `arrow.svg`, not `default.svg`. No other GNOME 51 extension does shake-to-find (searched EGO; Jiggle was last pushed in 2023), and no Wiggly fork fixes these. `patches/wiggly-follow-cursor.patch`, applied by `patch_wiggly_extension` after the extensions install: before every shake it measures the pointer in logical pixels, sets the pivot on the hotspot before scaling, and grows from the pointer's own size. The logical size is `cursor-size` × the theme's Xcursor canvas/nominal ratio, which is how Mutter sizes it. On fractional scales the sprite is a texture loaded at ceil(scale) and `get_scale()` still returns 1: the first version of the patch trusted it and ended the shrink at twice the pointer, sticking out to the bottom right of the tip. A new `theme.js` resolves the active theme's pointer on every `cursor-theme` change (and `cursor-size` is followed too): the vector file named by `cursors_scalable/default/metadata.json`, else the largest Xcursor `default`/`left_ptr` frame as a pixbuf (no file written), following Inherits like libXcursor. `apply_wiggly_cursor` clears a `cursor-path` that an earlier run wrote, so a typed path still wins. Wiggly's `show()` also allowed unfocus again before making the pointer visible. Mutter then re-picked the pointer focus while the pointer was hidden, `meta_wayland_pointer_set_focus` refused it (its assertion was in the journal after each shake), and the cursor stayed gone until the next motion. The patch reverses the order. The resolver was checked in gjs against aosp-cursors, MacTahoe-dark (vector) and Adwaita, Aura-Glass-Moga-Red, steam and `default` (pixbuf); the patch applies to and reverses on the EGO v10 zip. The animation needs a look after re-login (GNOME Shell does not reload changed extension modules).
