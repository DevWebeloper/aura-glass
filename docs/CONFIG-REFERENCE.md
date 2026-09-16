# Configuration reference

Every path aura-glass writes to, every memo it remembers a setting in, and what
reads each one back.

---

## Paths

| Path | Contents |
|---|---|
| `~/.config/aura-glass/` | `$CONF_DIR` — the memos, the installed stylesheet copies, `backups/`, `modes/` |
| `~/.config/aura-glass/backups/` | first-run copies of everything the installer overwrote |
| `~/.config/aura-glass/modes/<mode>/` | the per-glass-mode tuning drawers |
| `~/.themes/Aura-Glass/` | the theme, adopted from the upstream installer's `Tahoe-Dark` |
| `~/.config/gtk-4.0/gtk.css`, `gtk-dark.css` | GTK4 targets, spliced |
| `~/.config/gtk-3.0/gtk.css` | GTK3 target, spliced (the user's own file — not flattened) |
| `~/.local/share/gnome-shell/extensions/` | `$EXT_DIR` |
| `~/.local/share/icons/`, `~/.icons/` | icon and cursor packs |
| `~/.local/share/fonts/aura-glass/` | fonts `--font` downloaded |
| `~/.local/bin/` | `aura-glass-apply`, `aura-glass-settings`, `aura-glass-preview`, `aura-glass-ext`, `aura-glass-update-check`, `aura-glass-icon-sync`, `aura-glass-panel-blur`, `aura-glass-gdm-sync`, `aura-glass-open-once` |
| `~/.local/share/aura-glass/gui/` | `$GUI_DIR` — the installed copy of the settings window |
| `~/.config/systemd/user/` | the four user units |
| `~/.cache/aura-glass/src/` | `$SRC_CACHE` — checkouts of pinned upstreams |
| `~/.cache/aura-glass/preview/` | the preview harness's throwaway profile |

Pre-rename installs used `tahoe-glass` in place of `aura-glass` throughout.
`bin/aura-glass-apply`, `uninstall.sh` and `lib/steps-migrate.sh` still resolve
both.

---

## `$CONF_DIR` memos

Each is a plain text file holding one value with a trailing newline, written by
the `apply_*` function that consumes the setting, and read back on the next
flagless run. Writes are guarded by `remembering()` — a `--dry-run` and a live
preview leave none behind.

### Look and tuning

| File | Holds | Written by |
|---|---|---|
| `glass-mode` | `frosted` \| `transparent` \| `solid` | `remember_glass_mode` |
| `styling-off` | present = the theme has stood down (solid). Read by `aura-glass-apply` | `sync_styling_marker` |
| `accent` | one of the nine accent names | `apply_gsettings` |
| `radius-preset` | canonical preset name, or `custom` (`pill` is normalised to `rounded`) | `apply_radius_css` |
| `radius-custom` | eight comma-separated pixels, in `WINDOW,MENU,QUICK_SETTINGS,NOTIFICATION,DIALOG,POPUP,OSD,BUTTON` order | `apply_radius_css` |
| `app-transparency` | `0`, or a two-decimal fraction `0.70`–`1.00` | `install_transparency_css` |
| `app-opacity` | the same level as 0–255, for the Blur My Shell key | `apply_app_opacity` |
| `app-tint-color` | hex, e.g. `#000000` | `apply_app_tint_color` |
| `shell-tint-color` | hex | `apply_shell_tint_color` |
| `blur-strength` | percent of the tuned sigmas, `25`–`200` | `apply_blur_strength` |
| `popup-brightness` | percent of the backdrop, `50`–`150` | `apply_popup_brightness` |
| `notification-opacity` | percent, `10`–`85` | `apply_notification_opacity` |
| `grain` | noise overlay amount | `apply_grain` |
| `titlebutton-style` | `minimal` \| `adwaita` \| `material` \| `flat` | `install_window_control_style` |
| `window-buttons` | the `button-layout` this install wrote | `apply_window_buttons` |

### Blur scope

| File | Holds |
|---|---|
| `window-blur` | `0` \| `1` — blur behind app windows |
| `popup-blur` | `0` \| `1` |
| `notification-blur` | `0` \| `1` |
| `app-blur-scope` | `gtk` (whitelisted apps) \| `all` (everything but the blocklist) |
| `app-blur-allow` | one `wm_class` pattern per line; wildcards allowed |
| `app-blur-block` | one pattern per line |

`app-blur-allow` / `app-blur-block` are the only place arbitrary user text
reaches dconf. `app_blur_literal` builds the GVariant array;
`tools/check-app-blur-lists.sh` round-trips it through GLib's parser.

The first-party extension writes these two directly when someone uses **Blur
This App** from the window menu — skipping that mirror would mean a toggle
holding only until the next `install.sh`, which reads the stale memo over dconf.

### Assets

| File | Holds |
|---|---|
| `icons` | the resolved icon theme name actually set (`icon_base`) |
| `icon-pack` | the pack as asked for (`colloid-teal`, `hatter-slate`, …), or `keep` for `--no-icons` |
| `cursor-pack` | `adwaita` \| `aosp` \| `mactahoe` \| `moga` \| `original`, or `keep` |
| `cursor-size` | pixels, only ever written when `--cursor-size` was given |
| `font` | `system` \| `misans` \| `inter` \| `sf-pro` |

### Machinery

| File | Holds |
|---|---|
| `repo-path` | the checkout the settings window must run `install.sh` from |
| `panel-blur-fix` | `0` \| `1` — the multi-monitor panel blur unit |
| `update-check` | `0` \| `1` — the daily timer |
| `update-available` | the version a check found, so the window can offer it |
| `rounded-blur` | the `gnome-rounded-blur` build stamp |
| `bms-ref` / `bms-source` | the Blur My Shell commit installed, and `git` or `ego` |
| `openbar-patch` / `custom-osd-patch` | patch stamps, so a re-run knows the patch is already in |
| `gdm-installed` | `dynamic` when the login screen was themed |
| `gdm-monitors-synced` | present = the monitor layout was pushed to GDM |
| `accent-from-wallpaper` | set when `auto-accent-colour` was installed, so the accent row can warn |
| `preview-active` / `preview-backup` | `aura-glass-preview`'s in-flight state and its snapshot |

### Per-mode drawers

`$CONF_DIR/modes/<frosted|transparent|solid>/` holds a mode's own copy of:

```
app-transparency  app-tint-color  shell-tint-color  blur-strength
popup-brightness  notification-opacity  popup-blur  notification-blur
app-blur-scope    (frosted only)
```

plus, for solid only, `disabled-extensions` — the record of what
`stand_down_extensions` switched off, so `restore_extensions` can put exactly
that set back.

`seed_glass_mode` creates a drawer on first entry. Transparent seeds
`app-transparency` at `0.82` unconditionally rather than inheriting the shared
memo: that value belongs to frosted, tuned for a blurred window behind it. Tints
*are* inherited — a colour preference travels with the user, an opacity level is
coupled to whether there is blur behind the glass.

### Installed stylesheet copies

`$CONF_DIR` also holds the copies `aura-glass-apply` concatenates:
`shell-NN-*.css`, `gtk4-NN-*.css`, `gtk3-tweaks.css`, `gtk4-transparency.css`,
the three `{gtk3,gtk4}-window-controls-*` variants (one installed at a time),
`shell-popup-blur.css`, `shell-notification-blur.css`, `shell-80-solid.css`, and
the generated `shell-90-density.css`.

An **optional** sheet is installed or deleted by `install_css`, never switched
on at read time — `aura-glass-apply` concatenates whatever it finds and cannot
know which flags this install was given.

---

## `$CONF_DIR/backups/`

First-run copies, taken by `backup_once` before anything is overwritten:

| Record | Meaning |
|---|---|
| `<name>.orig` | the file as it was before aura-glass first ran |
| `<name>.absent` | there was no such file before aura-glass created it |
| `<name>.stood-down` | a `.absent`-recorded file moved aside by solid mode, kept for the way back |

Four names are tracked: `gnome-shell.css`, `gtk4-gtk.css`, `gtk4-gtk-dark.css`,
`gtk3-gtk.css`. `gsettings_backup_once` records the original value of every
gsettings key the installer writes, which is what `gsettings_original` reads
back for `--font system` and for uninstall.

`uninstall.sh` restores the `.orig` or deletes the `.absent`. Standing down is
deliberately different: it moves a `.absent` file aside instead of deleting it,
because solid is a mode and coming back out of it must be one run with nothing
lost.

---

## gsettings keys written

| Schema / key | When |
|---|---|
| `org.gnome.desktop.interface color-scheme` = `prefer-dark` | always |
| `org.gnome.desktop.interface accent-color` | `--accent` |
| `org.gnome.desktop.interface gtk-theme` | when styling is on |
| `org.gnome.desktop.interface icon-theme` | unless `--no-icons` |
| `org.gnome.desktop.interface cursor-theme` | unless `--no-cursors` |
| `org.gnome.desktop.interface cursor-size` | only when `--cursor-size` given |
| `org.gnome.desktop.interface font-name`, `document-font-name` | `--font` |
| `org.gnome.desktop.wm.preferences titlebar-font` | `--font` |
| `org.gnome.desktop.wm.preferences button-layout` | `--window-buttons` |
| `org.gnome.shell enabled-extensions` | enabling / standing down |
| `org.gnome.shell.extensions.user-theme name` | toggled by `aura-glass-apply` to force a reload |

`--no-icons` and `--no-cursors` mean the key is **never written**, so a choice
made in GNOME Tweaks or anywhere else stands — and the memo records that, so
later runs leave it alone too.

Font sizes are never changed: `apply_font` writes the new family at whatever
size the key already carried (`font_size_now`).

---

## dconf

| File | Loaded when |
|---|---|
| `dconf/core.ini` | every install with styling on — every extension's settings in one preset |
| `dconf/extras.ini` | with the optional extensions |
| `dconf/solid.ini` | on top of core, by `--no-blur` |

Solid **mode** never loads any of them: loading `core.ini` is exactly the
"modifying the extension" that standing down avoids. The extensions are disabled
with their settings intact.

Individual keys are then overwritten from this run's resolved flags by the
`apply_*` functions in `lib/steps-dconf.sh` — see
[ARCHITECTURE.md §7](ARCHITECTURE.md#7-dconf-and-gsettings).

The subtrees touched:

```
/org/gnome/shell/extensions/blur-my-shell/…      panel, popup, applications,
                                                 overview, window-list, dash-to-dock
/org/gnome/shell/extensions/openbar/…            bar geometry, menu styling
/org/gnome/shell/extensions/custom-osd/…         the volume/brightness pill
/org/gnome/shell/extensions/just-perfection/…    and the rest of extras.ini
```

---

## Environment variables

| Variable | Read by | Effect |
|---|---|---|
| `AURA_GLASS_DIR` | `aura-glass-apply`, `aura-glass-preview` | override `$CONF_DIR` |
| `AURA_GLASS_CONF` | `aura-glass-update-check` | override `$CONF_DIR` for the update check (this is what its test fixtures set) |
| `AURA_GLASS_THEME` | `aura-glass-apply`, `preview.sh` | override the theme directory name |
| `AURA_GLASS_GUI` | `aura-glass-settings` | run the window from a checkout's `gui/` instead of the installed copy |
| `AURA_GLASS_ICONS` | `aura-glass-icon-sync` | the icon theme base name to follow light/dark with |
| `AURA_GLASS_BLUR_SETTLE` | `aura-glass-panel-blur` | seconds to wait for the desktop to settle, default 3 |
| `AURA_PREVIEW_DIR` | `preview.sh` | the harness's throwaway profile directory |
| `AURA_PREVIEW_SHOTS` | `preview.sh` | where preview PNGs land |
| `AURA_PREVIEW_RES` | `preview.sh` | preview resolution, default `1920x1080` |
| `AURA_SHOT_BASELINE` | `check-shots.py` | where accepted baselines live |
| `AURA_GPU_LOG` | `gpu-live.sh` | the measurement log |
| `PREVIEW_MODE=1` | `lib/common.sh` | makes `remembering()` false — no memo is written |
| `DRY_RUN=1` | `lib/common.sh` | same, plus `run()` prints instead of executing |
| `NO_COLOR` | `lib/common.sh` | plain output |

Every `AURA_*` name above also answers to its `TAHOE_*` spelling, for pre-rename
installs.

---

## systemd user units

```
aura-glass-icon-sync.service       follow light/dark with the icon theme
aura-glass-panel-blur.service      rebuild panel blur after the desktop settles
aura-glass-gdm-sync.service        push wallpaper + primary monitor to GDM
aura-glass-update-check.service    one git ls-remote
aura-glass-update-check.timer      daily, 15 min after boot
```

```bash
systemctl --user status aura-glass-panel-blur.service
systemctl --user list-timers aura-glass-update-check.timer
```

The update check notifies **once per release**, not once per day, and never
installs anything — that is a button in the settings window.
