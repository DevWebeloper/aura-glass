# Feature map

Look up a visible feature or a setting and get the files that own it, the
function that applies it, and how to see the change. Use this before searching
the tree.

Conventions: `$C` = `~/.config/aura-glass`. "Retune" = `./install.sh --settings-only -y`,
the way to put any change below on the live desktop (offline, rootless; see
rule 5 in [CLAUDE.md](../CLAUDE.md)). Shell CSS reloads itself. GTK apps need
a restart.

---

## 1. GNOME Shell surfaces

| Feature | Stylesheet(s) (`css/`) | Blur / dconf (`dconf/core.ini`) | Token(s) | Applied by |
|---|---|---|---|---|
| Top panel | `shell-00-flat` | `[blur-my-shell/panel]`, pipeline `panel` | `TOKEN_BLUR_RADIUS_PANEL` | `install_css`, `load_dconf` |
| Top bar shaded behind a maximized window | `shell-00-flat` (`#panel.aura-glass-maximized`, 60% black) | none | none | Aura Glass Helper `_syncPanelShade`: focused window on the primary monitor that is maximized, fullscreen or covers the work area (Tiling Assistant `maximize-with-gap`), outside the overview |
| Panel blur after monitor changes | none | none | none | Blur My Shell v76 keeps it aligned itself. The old `aura-glass-panel-blur.service` is removed by `remove_panel_blur_unit` |
| Panel icon size for this display | generated `shell-90-density` | none | `TUNED_PPI` (in `steps-css.sh`) | `measure_logical_ppi`, `density_css` |
| Top bar height (24–48 px, settings app → Appearance → Top bar; reset goes to GNOME's 32), snapped so there is no seam under a maximized window | generated `shell-90-density` (`#panel { height }`: the asked height snapped to whole device pixels, so 39px for the theme's 40 at 1.33/1.67; absent when that is the theme's own 40) | none | `PANEL_HEIGHT_THEME` 40, `PANEL_HEIGHT_GNOME` 32 (`steps-css.sh`, copied in `gui/aura_glass_settings.py`, held by `check-gui-flags.py`) | `resolve_panel_height`, `measure_primary_scale`, `panel_height_css`. Memo `$C/panel-height` |
| Quick Settings panel | `shell-20-popup-menus`, `shell-popup-blur` | `[blur-my-shell/popup] quick-settings-corner-radius` | `TOKEN_RADIUS_QUICK_SETTINGS` | `install_css`, `apply_radius_*` |
| Quick Settings sliders | `shell-10-quick-settings` | none | none | `install_css` |
| Quick toggles and switches | `shell-40-quick-toggles` | none | none (follows `-st-accent-color`) | `install_css` |
| Popup menus (panel, right-click) | `shell-20-popup-menus`, `shell-popup-blur` | `[blur-my-shell/popup] menu-corner-radius`, pipeline `popups` | `TOKEN_RADIUS_MENU`, `TOKEN_BLUR_RADIUS_POPUP` | `install_css`, `apply_popup_blur`, `apply_blur_pipelines`; opacity `apply_popup_transparency` (`--popup-opacity`, else the windows' level) |
| Date / calendar menu | `shell-20-popup-menus`, `shell-popup-blur` | grouped with **Quick Settings** radius, not the menu one | `TOKEN_RADIUS_QUICK_SETTINGS` | as above |
| Notification banners and history cards | `shell-30-notifications`, `shell-notification-blur` | the popup blur (v76 has no separate notification switch), `notification-corner-radius` | `TOKEN_RADIUS_NOTIFICATION` | `install_css` (the sheet goes with `--popup-blur`), `apply_notification_opacity` (`tools/apply-notification-opacity.py`, ground 40 × the popup opacity / 90) |
| Modal dialogs (auth, power, run) | `shell-50-dialogs` | `[blur-my-shell/popup] dialog-corner-radius` | `TOKEN_RADIUS_DIALOG` | `install_css` |
| Copyous clipboard dialog (Super+V) | `.modal-dialog.clipboard-dialog` in `shell-50-dialogs`, `shell-popup-blur`, `shell-80-solid`; its cards, buttons and search bar on the white lift ladder in `shell-50-dialogs` | as modal dialogs | `TOKEN_RADIUS_DIALOG` | `aura-glass-apply` copies those rules into `$CONF_DIR/extension-overrides.css`; Aura Glass Helper loads it as an extension sheet, the only rank that outranks Copyous's own stylesheet |
| Other popups | `shell-popup-blur` | `[blur-my-shell/popup] corner-radius` | `TOKEN_RADIUS_POPUP` | `apply_radius_dconf` |
| Volume / brightness OSD pill | none (drawn by Custom OSD) | `[custom-osd]`, `[blur-my-shell/popup] osd-corner-radius` | `TOKEN_RADIUS_OSD` | `sync_osd_profile`, `apply_radius_dconf`. Patch: `patches/custom-osd-gnome50.patch` |
| App folders | `shell-00-flat` | `[blur-my-shell/appfolder]`, pipeline `app folders` | `TOKEN_BLUR_RADIUS_APPFOLDER` | `load_dconf` |
| Overview | none | `[blur-my-shell/overview]`; window blur kept out by `[applications] blur-on-overview=false` | none | `load_dconf` |
| Dash to Dock / window list | none | `[blur-my-shell/dash-to-dock]`, `[…/window-list]`, pipelines `dock`, `window list` | `TOKEN_BLUR_RADIUS_DASH_TO_DOCK`, `TOKEN_BLUR_RADIUS_WINDOW_LIST` | `load_dconf` |
| Lock screen blur | none | `[blur-my-shell/lockscreen]` | none | `load_dconf` |
| Shell tint (hue of dark surfaces) | every shell sheet (installed copies) | none | none | `apply_shell_tint_color` → `tools/apply-shell-tint.py`. Memo `$C/shell-tint-color` |
| Performance mode shell look | `shell-80-solid` (opaque ladder) | `dconf/solid.ini` (fresh preset loads only) | `TOKEN_RADIUS_NOTIFICATION` | `install_css` (when `WANT_BLUR=0`), `apply_popup_transparency` |
| Accent colour in the shell | substituted by `bin/aura-glass-apply` (`-st-accent-color`) | none | none | `apply_accent`. gsettings `accent-color` |
| Login screen (GDM) | none | none | none | `lib/steps-gdm.sh`, `bin/aura-glass-gdm-sync` (opt-in, root) |

## 2. GTK4 / libadwaita apps

| Feature | Stylesheet(s) | Blur / dconf | Token(s) | Applied by |
|---|---|---|---|---|
| Shadow and gradient flattening of the theme | `gtk4-00-flat` + flattening in `bin/aura-glass-apply` | none | none | `aura-glass-apply` |
| Text fields, spin buttons | `gtk4-10-fields` | none | none | `install_css` |
| Buttons (labelled, suggested, destructive, pill) | `gtk4-20-buttons` | none | `TOKEN_RADIUS_BUTTON` | `install_css`, `apply_radius_css` |
| Dropdowns and combo rows | `gtk4-30-dropdowns` (squarer than buttons; must load after them) | none | none | `install_css` |
| Boxed lists, cards, sidebars | `gtk4-40-containers` | none | none | `install_css` |
| Titlebar buttons, base "minimal" style | `gtk4-50-window-controls` | none | none | `install_css` |
| Titlebar buttons, adwaita / material / flat | `gtk4-window-controls-<style>` (+ GTK3 mirror) | none | none | `install_window_control_style`. Flag `--titlebar-button-style`, memo `$C/titlebutton-style` |
| Titlebar button layout (close only / all) | none | gsettings `org.gnome.desktop.wm.preferences button-layout` | none | `apply_window_buttons`. Flag `--window-buttons` |
| Switches, checks, radios, sliders | `gtk4-60-controls` (accent-driven) | none | none | `install_css` |
| Window corners and surfaces | `gtk4-70-surfaces` | `[blur-my-shell/applications] corner-radius` | `TOKEN_RADIUS_WINDOW` | `apply_radius_css`, `apply_radius_dconf` |
| Window transparency | `gtk4-transparency` (installed only if level ≠ 0) | `[blur-my-shell/applications] opacity` (the level × 255, so non-GTK apps like Chrome show the blur too) | `TOKEN_APP_TRANSPARENCY_SHIPPED` | `install_transparency_css` → `tools/rescale-transparency.py`. Memo `$C/app-transparency` |
| App tint | `gtk4-transparency` | none | `TOKEN_APP_TINT` | `apply_app_tint_color` → `tools/apply-tint-color.py`. Memo `$C/app-tint-color` |
| Blur behind app windows | none | `[blur-my-shell/applications] blur, enable-all, whitelist, blacklist`, pipeline `windows`. Dialogs and tool palettes follow their app (`patches/blur-my-shell-subwindows.patch`) | `TOKEN_BLUR_RADIUS_APPLICATIONS` | `apply_app_blur` (`app_blur_literal`), `apply_blur_pipelines` |
| Accent colour in GTK | substituted by `aura-glass-apply` (`@accent_bg_color`) | none | none | `apply_accent` |

## 3. GTK3 apps

| Feature | Stylesheet | Note |
|---|---|---|
| Everything GTK3 | `gtk3-tweaks` | User CSS at `PRIORITY_USER`, so it wins regardless of specificity. Window corners use `TOKEN_RADIUS_WINDOW`. |
| Titlebar button style | `gtk3-window-controls-<style>` | Must mirror the GTK4 sheet of the same style. |

## 4. Blur-wide controls

| Feature | Where | Applied by |
|---|---|---|
| Main blur amount (25–200 %) and brightness (50–100 %) | every `dual_kawase_blur` effect's `unscaled_radius` and `brightness` in `pipelines`, from `core.ini`'s values, capped at v76's 100 and 1.0 | `apply_blur_pipelines`. Memos `$C/blur-strength`, `$C/blur-brightness` (frosted drawer) |
| One surface's own blur amount and brightness (windows, popups & notifications, top bar, lock screen + overview) | the pipeline its component (`applications`, `popup`, `panel`, `lockscreen`) points at; `main` follows the main values. Dock, app folders and window list follow the main values only | `apply_blur_pipelines` (`BLUR_SURFACES`). Memos `$C/<surface>-blur-strength`, `$C/<surface>-blur-brightness` (frosted drawer) |
| Popups & notifications opacity (70–100, or follow the windows) | `shell-popup-blur.css` alphas and the banner ground in `shell-notification-blur.css` | `apply_popup_transparency`, `apply_notification_opacity`. Memo `$C/popup-opacity` (frosted drawer) |
| Moving an install onto v76's pipelines | `pipelines`, `settings-version`, every component's `pipeline`; legacy `sigma`/`brightness`/`customize` reset | `upgrade_bms_settings` (once: below version 7, or after v76's own migration) |
| Grain (0–1) | the noise effect in pipelines | `apply_grain` |
| Glass style (frosted / liquid / vibrant / tinted / smoked) | a `refraction` effect (id prefix `effect_aura_glass_style_`) after the blur in pipelines `panel` and `dock` (v76 rounds it from the component's corner); liquid also sets `[dash-to-dock] static-blur=true`. `--liquid-windows` adds pipeline `windows` and `[applications] static-blur=true`. Vibrant is a `luminosity` effect (saturation 1.35, brightness 1.06, 1.0 on the lock screen and windows) ahead of the blur in pipelines `lock screen` and `panel`, leaving the dock dynamic; with `--liquid-windows` also pipeline `windows` and `[applications] static-blur=true`. Tinted is a `color` effect (accent RGB from `accent_hex`, alpha 0.3, blend Color) and smoked a `luminosity` effect (brightness 0.7, saturation 0.8), both in `panel` and `lock screen` only, never windows. An `--accent` incremental Apply adds the `glass-style` action under tinted | `apply_glass_style`. Memos `$C/glass-style`, `$C/liquid-windows` (top-level, not drawer fields) |
| Popup blur on/off | `[popup] blur` + `shell-popup-blur.css` present/absent | `apply_popup_blur`, `install_css` |
| Notification blur | follows the popup blur: `shell-notification-blur.css` is installed with `shell-popup-blur.css` (`--notification-blur` is retired) | `install_css` |
| Per-app blur lists | `[applications] whitelist/blacklist`, memos `app-blur-allow/-block` | `apply_app_blur`. Window menu: `aura-glass-preview app-blur` |

## 5. Modes and adaptive

| Feature | Files | Notes |
|---|---|---|
| Frosted / Performance | `lib/steps-modes.sh`, `$C/glass-mode`, `$C/modes/<mode>/` | See ARCHITECTURE §3 |
| Adaptive profiles (Auto / Full Glass / Performance) | `extensions/…/extension.js` (menu), `bin/aura-glass-adaptive`, `tools/aura_glass_adaptive.py`, `apply_adaptive_blur` in `lib/steps-dconf.sh`, `systemd/aura-glass-adaptive.service` | State in `$C/adaptive-profile`, `$C/adaptive-performance/`. Shown and switchable in the settings app's Glass status group |
| Fullscreen games list | settings app → Per-app blur | `$C/adaptive-fullscreen-apps` |

## 6. Assets, fonts, extensions

| Feature | Files |
|---|---|
| Icon packs + accent mapping | `lib/steps-assets.sh` (`install_icons`, `icon_base`, `accent_to_*`), `bin/aura-glass-icon-sync` (light/dark) |
| Pointer packs, size | `lib/steps-assets.sh` (`install_cursors`, `install_moga_cursors`), `tools/moga_cursor.py`, `apply_cursor_theme`, `apply_cursor_size`, Wiggly's magnified pointer: `patch_wiggly_extension` + `patches/wiggly-follow-cursor.patch` |
| Fonts | `lib/steps-fonts.sh`, `apply_font` |
| Extension catalogue | `lib/steps.sh` (arrays, `ext_description`), `bin/aura-glass-ext`, `lib/steps-extensions.sh` |
| Blur This App (window menu) | `extensions/aura-glass-blur@aura-glass.local/extension.js` → `aura-glass-operation app-blur` |
| Mouse wheel switches workspaces while dragging in the overview | `extensions/aura-glass-blur@aura-glass.local/extension.js` (`_attachDragScroll`, `_onDragScroll`) |

## 7. Installer / system behaviour

| Behaviour | Files |
|---|---|
| Flag parsing, resolution, step order | `install.sh` |
| Incremental Apply classification | `lib/steps-apply-plan.sh` |
| Writer lock | `bin/aura-glass-operation`, `tools/aura_glass_operation.py` |
| Splicing, flattening, accent swap, atomic publish | `bin/aura-glass-apply` |
| Live preview | `bin/aura-glass-preview`, `gui/preview_queue.py` |
| Backups, dry-run, memo guard | `lib/common.sh` (`backup_once`, `run`, `remembering`) |
| Dependencies, distro detection | `lib/distro.sh` |
| Legacy rename (`tahoe-glass`) | `lib/steps-migrate.sh` |
| Update check / channel | `bin/aura-glass-update-check`, `systemd/aura-glass-update-check.*`, `current_branch` / `is_test_build` in the GUI |
| Installing an update, release list, history | `bin/aura-glass-update`, `updates_snapshot` / `_render_updates` / `update_blockers` in the GUI |
| Uninstall | `uninstall.sh` |

## 8. Which numbers are written twice (change them together)

| Token (`tokens/tokens.sh`) | Value | Consumers | Checker |
|---|---|---|---|
| `TOKEN_RADIUS_WINDOW` | 30 | `gtk3-tweaks.css`, `gtk4-70-surfaces.css`, `core.ini [applications] corner-radius`, the pipeline `windows` corner in `core.ini`, the GUI preset table | `check-tokens.sh`, `check-gui-radius.py` |
| `TOKEN_RADIUS_MENU` | 26 | `shell-20-popup-menus.css`, `shell-popup-blur.css`, `core.ini [popup] menu-corner-radius` | `check-tokens.sh` |
| `TOKEN_RADIUS_QUICK_SETTINGS` | 33 | `shell-20-popup-menus.css` (2 sites), `shell-popup-blur.css` (2), `core.ini [popup] quick-settings-corner-radius` | `check-tokens.sh` |
| `TOKEN_RADIUS_NOTIFICATION` | 20 | `shell-30-notifications.css` (4), `shell-80-solid.css` (2), `core.ini [popup] notification-corner-radius` | `check-tokens.sh` |
| `TOKEN_RADIUS_DIALOG` | 20 | `shell-50-dialogs.css`, `core.ini [popup] dialog-corner-radius` | `check-tokens.sh` |
| `TOKEN_RADIUS_POPUP` | 20 | `core.ini [popup] corner-radius` | `check-tokens.sh` |
| `TOKEN_RADIUS_OSD` | 12 | `core.ini [popup] osd-corner-radius` | `check-tokens.sh` |
| `TOKEN_RADIUS_BUTTON` | 9999 | `gtk4-20-buttons.css` | `check-tokens.sh` |
| `TOKEN_BLUR_RADIUS_{PANEL,APPFOLDER,POPUP,WINDOW_LIST,APPLICATIONS,DASH_TO_DOCK}` | 12 / 100 / 60 / 60 / 24 / 8 | the `unscaled_radius` of the matching pipeline in `core.ini` | `check-tokens.sh` |
| `TOKEN_APP_TRANSPARENCY_SHIPPED` | 0.92 | `gtk4-transparency.css` | `check-tokens.sh` |
| `TOKEN_APP_TINT` | 45 | `gtk4-transparency.css` | `check-tokens.sh` |

Radius presets also live in `radius_preset_values`/`radius_bounds`
(`tokens.sh`) **and** in `RADIUS_PRESET_VALUES`/`RADIUS_SURFACES`
(`gui/aura_glass_settings.py`). `check-gui-radius.py` holds them together.
