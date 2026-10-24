# Configuration reference

Every flag, memo, path, environment variable and system key Aura Glass reads or
writes. `$C` = `$CONF_DIR` = `~/.config/aura-glass`.

Column keys used below:

- **Memo** is the top-level file the consumer writes when `remembering()` is true.
- **Drawer** means the value is also kept per mode in `$C/modes/<mode>/`.
- **Incr.** is the `--incremental` action the flag maps to. `full` means it
  forces the complete retune.

---

## 1. Flags (`install.sh`)

`./install.sh --help` prints the user-facing list. This table is the
implementation view.

### Run control

`--reset` moves every remembered choice (`RESET_MEMOS` in `lib/steps-migrate.sh`) to `$C/backups/reset-<time>/` before anything reads a memo, so the run and the wizard start from defaults. A cancelled wizard puts them back. Machine state (`repo-path`, stamps, `bms-ref`, GDM records) stays.

| Flag | Effect |
|---|---|
| *(none, in a TTY)* / `--interactive` | Setup wizard: the GTK window, else the text wizard. |
| `-y`, `--yes` | Answer yes to prompts (not to `confirm_always`). |
| `-n`, `--dry-run` | Print what would happen. Skips the writer lock. |
| `--settings-only` | Retune an existing install: no theme or extension fetch, no root, no network unless a pack or font flag asks for one. |
| `--incremental` | With `--settings-only`: run only the classified actions (§1.4), else fall back to full. |
| `--plan-json` | With `--settings-only --incremental --dry-run`: print the action plan as JSON and exit. |
| `--adaptive-blur active\|restore` | Private to the adaptive worker. Needs `--settings-only --incremental`. Never memoed. |
| `--deps-only` | Install missing dependencies, then exit (needs root). |
| `--no-deps` | Never touch the package manager. |
| `--force` | Reinstall what's present and **reload the dconf preset** over existing extension settings. |
| `-h`, `--help` | Usage. |

### Packs and components

| Flag | Default | Memo | Notes |
|---|---|---|---|
| `--recommended` / `--extras` | ✓ | `extension-pack` | 6 optional extensions (`EXT_EXTRA_RECOMMENDED`). The pack memo is written only when a flag or a wizard picked the pack; a run with none reads it back |
| `--all-extras` | | `extension-pack` | all 8 (`EXT_EXTRA_ALL`) |
| `--no-extras` / `--minimal` | | `extension-pack` (empty file) | foundation only |
| `--extensions LIST` | | `extension-pack` | comma-separated UUIDs, each must be in `EXT_EXTRA_ALL`. Empty means minimal. A remembered UUID that is no longer in the catalogue is dropped, not fatal |
| `--full` | | `extension-pack`, `osd` | all extras + icons + cursors + OSD + panel-blur fix |
| `--osd` / `--no-osd` | on | `osd` (`0\|1`) | Custom OSD pill. A remembered `0` is what a flagless `--gui` update or `--force` reinstall reads back |
| `--bms-git` / `--no-bms-git` | git | `bms-ref`, `bms-source` | `--no-bms-git` (EGO build) also forces popup and notification blur off. A remembered `ego` keeps a flagless re-run on the EGO build; `--bms-git`, `--popup-blur` or `--notification-blur` typed override it |
| `--rounded-blur` / `--no-rounded-blur` | on | `rounded-blur-choice` (`0\|1`), `rounded-blur` (stamp) | gnome-rounded-blur. Only the typed flags write the choice: `--no-blur` forces it off for a run without that being a decision, and a remembered `1` never overrides it |
| `--gui` / `--no-gui` | on | none | settings window (needs PyGObject, libadwaita, pycairo) |
| `--window-menu` / `--no-window-menu` | on | `window-menu` | "Blur This App" (the helper reads the memo live) |
| `--update-check` / `--no-update-check` | on | `update-check` | daily timer |
| `--update-channel release\|latest` | `release` | `update-channel` | what the check follows on `main`: tags, or commits (a new release is still announced) |
| `--panel-blur-fix` / `--no-panel-blur-fix` | on if >1 monitor or a laptop | `panel-blur-fix` | panel blur rebuild service |
| `--gdm` / `--no-gdm`, `--gdm-background PATH` | off | `gdm-installed` | root |
| `--gdm-monitors` (`--sync-monitors`) / `--no-gdm-monitors` | off | `gdm-monitors-synced` | root |

### Look and behaviour

| Flag (aliases) | Values / default | Memo | Drawer | Incr. |
|---|---|---|---|---|
| `--accent C` | `blue teal green yellow orange red pink purple slate`. Default `purple` | `accent` | | `accent` (+ `cursor-theme` when the pointer is Moga, + `glass-style` when the glass style is tinted) |
| `--glass-mode M` | `frosted` \| `performance` | `glass-mode` | | full |
| `--blur` / `--no-blur` | `--no-blur` ⇒ performance | (via `glass-mode`) | | full |
| `--window-blur` / `--no-window-blur` | on. `--no-window-blur` also sets scope `none` and level 0.95 unless a level was given | `window-blur` | | full |
| `--all-apps-blur` (`--all-app-blur`), `--gtk-apps-blur` (`--gtk-app-blur`), `--app-blur-scope gtk\|all` | **`all`** | `app-blur-scope` | ✓ | full |
| `--app-blur-allow LIST`, `--app-blur-block LIST` | shipped lists in `core.ini` | `app-blur-allow`, `app-blur-block` (one pattern per line) | | `app-blur` |
| `--popup-blur` / `--no-popup-blur` | on | `popup-blur` | ✓ | full |
| `--notification-blur` / `--no-notification-blur` | on | `notification-blur` | ✓ | full |
| `--app-transparency L` (`--window-opacity`, `--window-transparency`); `--no-app-transparency` (+ the two `--no-` aliases) | `0.70–1.00`, `%`, or `0–255`. 0 = off. Fresh default 0.90 (0.95 without window blur, 1.00 in performance). Buckets snap to 0.82, 0.90 and 0.95 | `app-transparency` (`app-opacity` is always 255 now) | ✓ | `css` for the primary spelling, full for the aliases |
| `--app-tint-color HEX` | `#000000` | `app-tint-color` | ✓ | `css` |
| `--shell-tint-color HEX` | `#000000` (inherits app tint if unset) | `shell-tint-color` | ✓ | `css` |
| `--notification-opacity P` | 10–85, default 40 | `notification-opacity` | ✓ | `css` |
| `--blur-strength P` | 25–200, default 100 | `blur-strength` | ✓ | full |
| `--popup-brightness P` | 50–150, default 115 (preset) | `popup-brightness` | ✓ | full |
| `--window-brightness P` (`--app-brightness`, `--window-blur-brightness`) | 50–150, default 100 | `window-brightness` | ✓ | `window-brightness` (except the last alias, which is full) |
| `--grain N` / `--no-grain` | 0–1, default 0 | `grain` | | full |
| `--glass-style S` | `frosted` (default), `liquid`, `vibrant`, `tinted` (accent colour), `smoked`. Liquid: top bar and dock, and makes the dock's blur static. The others: top bar, overview and lock screen; the dock stays frosted | `glass-style` | | full |
| `--liquid-windows` / `--no-liquid-windows` | off. Liquid or vibrant behind app windows too (ignored under tinted and smoked); makes `[applications] static-blur` true | `liquid-windows` | | full |
| `--fullscreen-blur` / `--no-fullscreen-blur` | off. On keeps the window blur behind a fullscreen window; off drops it and puts the window at opacity 255 (`[applications] unblur-when-fullscreen`) | `fullscreen-blur` | | `fullscreen-blur` |
| `--radius-preset P` | `flat sharp adwaita soft medium default rounded` (`pill` → `rounded`). Default `default` | `radius-preset` | | full |
| `--radius-custom W,M,Q,N,D,P,O,B` | 8 integers within `radius_bounds`. Implies `custom` | `radius-custom` (a 7-field memo is widened with `,9999`) | | full |
| `--window-buttons close\|all` | unset = leave GNOME's layout | `window-buttons` | | `window-buttons` |
| `--titlebar-button-style S` | `minimal` (default), `adwaita`, `material`, `flat` | `titlebutton-style` | | `css` |
| `--icons X` | `colloid` (flagless default), `reversal`, `hatter`, `-<colour>` variants, `original`, or an installed theme name | `icon-pack` (+ `icons` = resolved name) | | full |
| `--no-icons` | leave the icon theme alone, permanently | `icon-pack` = `keep` | | full |
| `--cursors X` | `adwaita` (flagless default), `aosp`, `mactahoe`, `moga`, `original`, or an installed theme | `cursor-pack` | | `cursor-theme` |
| `--no-cursors` | leave the pointer theme alone | `cursor-pack` = `keep` | | `cursor-theme` |
| `--cursor-size PX` | 16–128. Unset = never written | `cursor-size` | | `cursor-size` |
| `--font F` | `system` (default, restores the original), `misans`, `inter`, `sf-pro` | `font` | | full |
| `--no-wm-buttons`, `--wm-buttons` | deprecated no-ops | none | | full |

> The defaults that front ends **recommend** differ from the installer's flagless
> defaults: the wizards recommend Reversal icons, Moga (GUI) or AOSP (text)
> pointers, and 20 px. See [CONSISTENCY.md](CONSISTENCY.md) §3.

### 1.4 Incremental actions (`lib/steps-apply-plan.sh`)

| Action | Runs |
|---|---|
| `accent` | `apply_accent` |
| `cursor-theme` | `install_cursors` (if needed), then `apply_cursor_theme` |
| `cursor-size` | `apply_cursor_size` |
| `window-buttons` | `apply_window_buttons` |
| `window-brightness` | `apply_window_brightness` |
| `app-blur` | `apply_app_blur` |
| `css` | `install_css` (the whole CSS pipeline + `aura-glass-apply`) |
| `glass-style` | `apply_glass_style` (an accent edit under the tinted style) |
| `adaptive-blur` | `apply_adaptive_blur active\|restore` |

These are ignored by the classifier: `--settings-only --incremental --plan-json --yes -y --dry-run -n`.
Any other flag makes the action `full`. The incremental path also falls back to
`full` when `$C/apply-source-fingerprint` (a sha256 of `install.sh`, `lib/*.sh`,
`tokens.sh`, `aura-glass-apply`, `aura_glass_operation.py`, `css/*.css` and
`dconf/*.ini`) is absent or differs. **The incremental path doesn't call
`remember_glass_mode`**, so drawers are not updated (KI-01).

---

## 2. Memos in `$C`

Plain text, one value and a trailing newline (lists: one item per line).
Written by the consumer when `remembering()` is true (not dry-run, not preview,
not adaptive).

### Look

| File | Holds | Writer |
|---|---|---|
| `glass-mode` | `frosted` \| `performance`. A legacy `solid` or `transparent` is rewritten by `migrate_solid_era` | `remember_glass_mode` |
| `accent` | one of the nine accents | `apply_accent` |
| `radius-preset` | canonical preset or `custom` | `apply_radius_css` |
| `radius-custom` | 8 comma-separated px (`WINDOW,MENU,QUICK_SETTINGS,NOTIFICATION,DIALOG,POPUP,OSD,BUTTON`). Removed for named presets | `apply_radius_css` |
| `app-transparency` | `0` or `0.70`–`1.00` | `install_transparency_css` |
| `app-opacity` | BMS applications actor opacity (follows the transparency level, level × 255) | `apply_app_opacity` |
| `app-tint-color`, `shell-tint-color` | `#rrggbb` | `apply_app_tint_color`, `apply_shell_tint_color` |
| `notification-opacity` | 10–85 | `apply_notification_opacity` |
| `blur-strength` | 25–200 | `apply_blur_strength` |
| `popup-brightness`, `window-brightness` | 50–150 | `apply_popup_brightness`, `apply_window_brightness` |
| `grain` | 0–1 | `apply_grain` |
| `glass-style` | `frosted\|liquid\|vibrant\|tinted\|smoked` | `apply_glass_style` |
| `liquid-windows` | `0\|1`, kept under frosted | `apply_glass_style` |
| `fullscreen-blur` | `0\|1`, top-level | `apply_fullscreen_blur` |
| `titlebutton-style` | `minimal\|adwaita\|material\|flat` | `install_window_control_style` |
| `window-buttons` | `close\|all` | `apply_window_buttons` |

### Blur scope

| File | Holds | Writer |
|---|---|---|
| `window-blur` | `0\|1` | `apply_app_blur` |
| `app-blur-scope` | `all\|gtk\|none` | `apply_app_blur` |
| `app-blur-allow`, `app-blur-block` | one wm_class pattern per line (wildcards). The settings window's own class is pinned to allow | `apply_app_blur` (installer, preview `app-blur`, window menu) |
| `popup-blur`, `notification-blur` | `0\|1` (not written while blur is off) | `apply_popup_blur`, `apply_notification_blur` |

### Mode drawers: `$C/modes/<frosted|performance>/`

`app-transparency app-tint-color shell-tint-color app-blur-scope popup-blur
notification-blur blur-strength popup-brightness window-brightness
notification-opacity`. Created by `seed_glass_mode`, read by
`load_glass_mode_memos`, `Settings()` and `apply_adaptive_blur restore`, written
by `save_glass_mode_memos`.

### Adaptive

| File | Holds | Writer |
|---|---|---|
| `adaptive-profile` | `auto` (seeded) \| `full` \| `performance` | `aura-glass-adaptive profile`, `install_adaptive_performance` |
| `adaptive-fullscreen-apps` | wm_class per line | settings app |
| `adaptive-install` | absolute path of the `install.sh` the worker runs | `install_adaptive_performance` |
| `adaptive-performance/active` | `0\|1` | worker, `install_adaptive_performance` |
| `adaptive-performance/reason` | e.g. `normal`, `battery`, `gpu`, `game`, `performance`, `no-blur` | worker, installer |
| `adaptive-performance/saved-mode-keys` | `key<TAB>value` lines (the keys a mode owns) while active | `apply_adaptive_blur` |

### Assets

| File | Holds | Writer |
|---|---|---|
| `icon-pack` | as asked (`colloid`, `reversal-cyan`, `hatter-slate` …) or `keep` | `install_icons` / `apply_gsettings` |
| `icons` | the resolved icon theme base name | `lib/steps-assets.sh` |
| `cursor-pack` | `adwaita\|aosp\|mactahoe\|moga\|original\|<theme>` or `keep` | `apply_cursor_theme` |
| `cursor-size` | px. Only when given | `apply_cursor_size` |
| `font` | `system\|misans\|inter\|sf-pro` | `apply_font` |

### Machinery

| File | Holds | Writer / reader |
|---|---|---|
| `repo-path` | the checkout the GUI, preview, update check and worker run from. **Only written when the GUI is installed** | `install_gui` |
| `apply-source-fingerprint` | sha256 of the apply sources | `--incremental` full fallback |
| `panel-blur-fix`, `update-check` | `0\|1` | `install_panel_blur_unit`, `install_update_check` |
| `update-channel` | `release\|latest`. Still written, **no longer read**: every commit on main is offered as a tag (`v0.3.5+N`) either way | `install_update_check` |
| `update-available` | the version a check found: a release `vX.Y.Z`, a tag `vX.Y.Z+N`, or `branch@sha` on a test build | `aura-glass-update-check` |
| `rounded-blur` | build stamp | `rounded_blur_stamp` |
| `rounded-blur-choice` | `0\|1`, only after a typed `--rounded-blur` / `--no-rounded-blur`. Only a `0` is read back | `install_rounded_blur`; read in `install.sh`'s resolution block |
| `extension-pack` | comma-separated UUIDs of the optional extensions chosen. Empty file = Minimal. Absent = the Recommended seven | `install_extensions`; read in the resolution block |
| `extension-catalog` | comma-separated UUIDs of `EXT_EXTRA_ALL` when the pack was chosen. A recommended extension missing from it joins a non-empty pack on an update. Absent = everything but `EXT_EXTRA_ADDED_LATER` | `install_extensions`; read in the resolution block |
| `osd` | `0\|1`. Only a `0` is read back | `install_custom_osd`; read in the resolution block |
| `bms-ref`, `bms-source` | installed BMS commit and `git\|ego`. `ego` is read back as `--no-bms-git` | `install_bms`; read in the resolution block |
| `custom-osd-patch` (legacy `openbar-patch`), `rounded-blur-patch` | patch stamps | `patch_stamp_write` |
| `gdm-installed`, `gdm-monitors-synced` | login-screen state | `lib/steps-gdm.sh` |
| `gdm-gresource` | `sha256sum` line for the gresource `install_gdm` wrote. A mismatch makes `aura-glass-gdm-sync` warn that a package update reverted the login theme (KI-30) | `record_gdm_gresource`; read by `aura-glass-gdm-sync` |
| `accent-from-wallpaper` | opt-in marker for the (currently uncatalogued) auto-accent extension | `bin/aura-glass-ext` writes it; `lib/steps-extensions.sh` reads it |
| `preview-active`, `preview-backup/` | live preview marker and journal (sheets, BMS dump, memos, session id) | `aura-glass-preview` |
| `uninstalled` | written by `uninstall.sh`, removed by the next install | |
| `shell-*.css`, `gtk4-*.css`, `gtk3-*.css` | installed, rewritten copies spliced by `aura-glass-apply` | `install_css` |

### `$C/backups/`

| Record | Meaning |
|---|---|
| `<name>.orig` | the file before Aura Glass first ran |
| `<name>.absent` | there was no file. Uninstall deletes ours |
| `<name>.stood-down` | a `.absent` file moved aside by the retired solid mode. Put back and removed by `migrate_solid_era` |

Names: `gnome-shell.css`, `gtk4-gtk.css`, `gtk4-gtk-dark.css`, `gtk3-gtk.css`.
`gsettings_backup_once` keeps the original icon-theme, cursor-theme,
cursor-size and font keys (what `original` / `system` restore).

---

## 3. System keys written

### gsettings

| Key | When |
|---|---|
| `org.gnome.desktop.interface color-scheme` = `prefer-dark` | every full run or full retune (`apply_gsettings`) |
| `org.gnome.desktop.interface accent-color` | `apply_accent` |
| `org.gnome.desktop.interface gtk-theme` = `Aura-Glass` | styling on |
| `org.gnome.desktop.interface icon-theme` | unless `--no-icons` (then the icon-sync service follows light/dark) |
| `org.gnome.desktop.interface cursor-theme`, `cursor-size` | unless `--no-cursors` / only if size given |
| `org.gnome.desktop.interface font-name`, `document-font-name`; `org.gnome.desktop.wm.preferences titlebar-font` | `--font` (sizes kept) |
| `org.gnome.desktop.wm.preferences button-layout` | `--window-buttons` |
| `org.gnome.shell enabled-extensions` / `disabled-extensions` | enabling, queuing |
| `org.gnome.shell disable-extension-version-validation` = `true` | every `apply_gsettings` |
| `org.gnome.shell.extensions.user-theme name` | set to `Aura-Glass`; toggled by `aura-glass-apply` to reload |

### dconf subtrees

```
/org/gnome/shell/extensions/blur-my-shell/   pipelines, panel, popup (+ patched notification key), applications,
                                             overview, appfolder, lockscreen, window-list, screenshot, dash-to-dock, …
/org/gnome/shell/extensions/custom-osd/
/org/gnome/shell/extensions/{vitals,hotedge,appindicator}/   (extras.ini)
```

---

## 4. Environment variables

| Variable | Read by | Effect |
|---|---|---|
| `AURA_GLASS_DIR` (`TAHOE_GLASS_DIR`) | `aura-glass-apply`, `aura-glass-preview`, adaptive worker | override `$C` |
| `AURA_GLASS_CONF` | `aura-glass-update-check`, `aura-glass-update` | override `$C` (test fixtures) |
| `AURA_GLASS_THEME` (`TAHOE_GLASS_THEME`) | `aura-glass-apply`, preview harness | theme directory name |
| `AURA_GLASS_GUI` | `aura-glass-settings` | run the window from a checkout's `gui/` |
| `AURA_GLASS_ICONS` | `aura-glass-icon-sync` | icon base to follow |
| `AURA_GLASS_BLUR_SETTLE` | `aura-glass-panel-blur` | settle seconds (default 3) |
| `AURA_GLASS_OPERATION_TIMEOUT` | operation lock | seconds to wait (default 30) |
| `AURA_GLASS_OPERATION_FD` | operation lock | the inherited lock descriptor (internal) |
| `AURA_GLASS_OPERATION_PREVIEW` | operation lock | which `aura-glass-preview` handles `app-blur` (set for checkout runs) |
| `AURA_GLASS_OPERATION` | adaptive worker | operation command path |
| `AURA_GLASS_ADAPTIVE_WORKER` | `aura-glass-adaptive` | worker path override |
| `AURA_GLASS_ADAPTIVE_INTERVAL`, `AURA_GLASS_ADAPTIVE_SUSTAINED` | worker | sample period (2 s), GPU samples to trigger (3) |
| `AURA_PREVIEW_DIR`, `AURA_PREVIEW_SHOTS`, `AURA_PREVIEW_RES` | `tools/preview.sh` | harness profile, output, resolution |
| `AURA_SHOT_BASELINE` | `check-shots.py` | accepted baselines |
| `AURA_GPU_LOG` | `gpu-live.sh` | measurement log |
| `DRY_RUN=1`, `PREVIEW_MODE=1` | `lib/common.sh` | `run` prints only / `remembering()` false |
| `NO_COLOR` | `lib/common.sh` | plain output |

---

## 5. Paths

| Path | Contents |
|---|---|
| `~/.config/aura-glass/` | `$C` |
| `~/.themes/Aura-Glass/` | the theme (adopted from `Tahoe-Dark`) |
| `~/.config/gtk-4.0/gtk.css`, `gtk-dark.css`; `~/.config/gtk-3.0/gtk.css` | spliced targets |
| `~/.local/share/gnome-shell/extensions/` | `$EXT_DIR` |
| `~/.local/bin/` | the commands in [STRUCTURE.md](STRUCTURE.md) §1 |
| `~/.local/share/aura-glass/` | GUI copy, the three Python workers |
| `~/.config/systemd/user/` | the units |
| `~/.cache/aura-glass/src/` | pinned checkouts (`$SRC_CACHE`) |
| `~/.cache/aura-glass/operation.lock` | the writer lock |
| `~/.local/share/fonts/aura-glass/` | downloaded fonts |
| `~/.local/lib/libblur-effect-1.0.so*` | an old rootless gnome-rounded-blur build. No longer written; removed by `install_rounded_blur` and `uninstall.sh` (KI-12) |

Pre-rename installs used `tahoe-glass` everywhere. `lib/steps-migrate.sh`,
`aura-glass-apply` and `uninstall.sh` resolve both.
