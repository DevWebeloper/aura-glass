# Known issues

A working list of the bugs and inconsistencies found in the 2026-10-15 audit
of the working tree (local `main`, two commits ahead of `origin/main`, plus
uncommitted edits). Each entry gives the symptom, how to reproduce it, the
root cause by file and function, a fix direction, and how to verify the fix.

**Status key.** *Reproduced*: shown on a fixture install with stubbed
`dconf`/`gsettings`, nothing on a live desktop. *Code-read*: follows directly
from the code, not run. *Verify*: plausible, needs a live check first.

The CLI reproductions below **change the live desktop**. Note your current
values first (`head ~/.config/aura-glass/*`) and set them back afterwards.

When you fix one, move it to the bottom section with the commit that fixed it.

| ID | Severity | Status | One line |
|---|---|---|---|
| [KI-01](#ki-01) | High | **Fixed** (uncommitted) | Settings-app Apply is silently reverted by the next full apply. The window shows stale tint/level |
| [KI-02](#ki-02) | High | **Fixed** (uncommitted) | Adaptive restore breaks Performance mode (removes the opaque sheet, re-enables app blur) |
| [KI-03](#ki-03) | High | **Fixed** (uncommitted) | Switching modes on an existing install toggles only 3 of 10 blur components |
| [KI-04](#ki-04) | Medium | **Fixed** (uncommitted) | Settings app crashes without pycairo, which the toolkit probe doesn't check |
| [KI-05](#ki-05) | Medium | Code-read | Four different "recommended/default" pointer answers. Text wizard can't pick Moga |
| [KI-06](#ki-06) | Low | Code-read | Stale prose and labels (Magic Lamp, "14 extras", scope and transparency defaults, wizard "Solid" = Performance) |
| [KI-07](#ki-07) | Medium | **Fixed** (uncommitted) | Uninstall leaves `aura-glass-operation` and `aura-glass-preview` in `~/.local/bin` |
| [KI-08](#ki-08) | Low | Code-read | `--dry-run` / `--plan-json` aren't side-effect free |
| [KI-09](#ki-09) | Low | Code-read | Launchers disagree on checkout vs installed copy |
| [KI-10](#ki-10) | Low | Code-read | Packages page doesn't know Moga packs |
| [KI-11](#ki-11) | Low | Code-read | Misleading success messages (BMS refresh on 51, rounded-blur compile) and an unneeded sudo prompt |
| [KI-12](#ki-12) | ? | Verify | Does the rootless `~/.local/lib` rounded-blur build actually load in the shell? |
| [KI-13](#ki-13) | Low | Code-read | AUR packaging is inconsistent with the repo |
| [KI-14](#ki-14) | Low | Reproduced | Test-suite gaps: a non-hermetic check, checks missing from the hook, a fabricated fixture |
| [KI-15](#ki-15) | Info | | Legacy `solid`/`transparent` machinery: keep as migration or remove |
| [KI-16](#ki-16) | Info | | Every full apply forces `color-scheme=prefer-dark` |
| [KI-17](#ki-17) | Info | | Housekeeping: stray tags, `.claude/` not ignored, `--plan-json` unwired, `refresh` via PATH |
| [KI-18](#ki-18) | High | **Fixed** (uncommitted) | A fresh `--glass-mode frosted` (and the text wizard's Customize path) gives opaque windows. The wizard's transparency answer is discarded |
| [KI-19](#ki-19) | Low | **Fixed** (uncommitted) | "Blur This App" writes to the destroyed window menu (journal stack traces), and its post-toggle checkmark uses a different rule than the menu |
| [KI-20](#ki-20) | Medium | **Fixed** (uncommitted) | A mode switch left open GTK windows on the old alpha until each app was reopened |
| [KI-21](#ki-21) | Medium | **Fixed** (uncommitted) | Tray Performance profile never showed the opaque shell sheet (shell theme not reloaded) |
| [KI-22](#ki-22) | Medium | **Fixed** | Settings app never showed the mode in force or the adaptive overlay, and missed changes made outside it |
| [KI-23](#ki-23) | Medium | **Fixed** | Install/update/uninstall audit: silent failures, lost memos, leftovers |
| [KI-24](#ki-24) | Low | **Fixed** (wizard parity drift still open, see entry) | Update and full reinstall forgot the extension pack, `--no-osd`, `--no-bms-git`, `--no-rounded-blur`. Wizard parity drift awaits a decision on which wizard is canonical |

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

- `origin` carries non-release tags `wip` and `zz-experiment`. The update check filters them, but RELEASING says not to push them.
- `.claude/README.md` says `.claude/` is git-ignored. It isn't (it shows as untracked).
- `--plan-json` is implemented but no front end calls it yet.
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

Fixed in the working tree on 2026-10-15, not yet committed. The entries above are kept for their reproductions until the fix is committed:

- **KI-01** — `install.sh`: the narrow `--incremental` branch now calls `remember_glass_mode` (not under `--adaptive-blur`). Verified with the fixture reproductions and the hermetic suite; needs a live check.
- **KI-02** — `apply_adaptive_blur` takes the no-blur baseline from the mode (`performance`/`solid`); the worker skips `sample()` in performance; `check-adaptive-installer.sh` uses a real `glass-mode=performance` fixture. Verified with the fixture reproductions and the hermetic suite; needs a live check.
- **KI-03** — new `sync_mode_owned_keys` / `mode_owned_dconf_keys` (`lib/steps-dconf.sh`), run on the preserved-preset path: performance always gets `solid.ini`'s keys; frosted gets `core.ini`'s values back when coming from another mode. Verified with the fixture reproductions and the hermetic suite; needs a live check.
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
- **KI-19** — `_toggleBlur` guards the menu item with its `destroy` signal and re-checks it with the menu's own whitelist/blacklist rule over the class chain. Syntax-checked only; needs a live check after the helper reloads.
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

**Still open: wizard parity drift.** Waiting on a decision about which wizard
is canonical before either changes:
- the GTK wizard offers Performance in Customize; the text wizard doesn't,
- the extension pack choices and default differ,
- Complete Experience sends `--cursor-size 20` and no `--extensions` in the window,
- the window's Performance sends `--no-blur`, the app sends `--glass-mode performance`.
