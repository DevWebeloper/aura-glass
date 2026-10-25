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
| Top panel | `shell-00-flat` | `[blur-my-shell/panel]` sigma, pipeline `panel` | `TOKEN_SIGMA_PANEL` | `install_css`, `load_dconf` |
| Top bar shaded behind a maximized window | `shell-00-flat` (`#panel.aura-glass-maximized`, 60% black) | none | none | Aura Glass Helper `_syncPanelShade`: focused window on the primary monitor that is maximized, fullscreen or covers the work area (Tiling Assistant `maximize-with-gap`), outside the overview |
| Panel blur after monitor changes | none | none | none | `patches/blur-my-shell-panel-refit.patch` (in place, one frame: `install_bms`). The old `aura-glass-panel-blur.service` is removed by `remove_panel_blur_unit` |
| Panel icon size for this display | generated `shell-90-density` | none | `TUNED_PPI` (in `steps-css.sh`) | `measure_logical_ppi`, `density_css` |
| Quick Settings panel | `shell-20-popup-menus`, `shell-popup-blur` | `[blur-my-shell/popup] quick-settings-corner-radius` | `TOKEN_RADIUS_QUICK_SETTINGS` | `install_css`, `apply_radius_*` |
| Quick Settings sliders | `shell-10-quick-settings` | none | none | `install_css` |
| Quick toggles and switches | `shell-40-quick-toggles` | none | none (follows `-st-accent-color`) | `install_css` |
| Popup menus (panel, right-click) | `shell-20-popup-menus`, `shell-popup-blur` | `[blur-my-shell/popup] menu-corner-radius`, `sigma`, `brightness` | `TOKEN_RADIUS_MENU`, `TOKEN_SIGMA_POPUP` | `install_css`, `apply_popup_blur`, `apply_popup_brightness` |
| Date / calendar menu | `shell-20-popup-menus`, `shell-popup-blur` | grouped with **Quick Settings** radius, not the menu one | `TOKEN_RADIUS_QUICK_SETTINGS` | as above |
| Notification banners and history cards | `shell-30-notifications`, `shell-notification-blur` | `[blur-my-shell/popup] notification` (patched key), `notification-corner-radius` | `TOKEN_RADIUS_NOTIFICATION` | `apply_notification_blur`, `apply_notification_opacity` (`tools/apply-notification-opacity.py`) |
| Modal dialogs (auth, power, run) | `shell-50-dialogs` | `[blur-my-shell/popup] dialog-corner-radius` | `TOKEN_RADIUS_DIALOG` | `install_css` |
| Copyous clipboard dialog (Super+V) | `.modal-dialog.clipboard-dialog` in `shell-50-dialogs`, `shell-popup-blur`, `shell-80-solid` | as modal dialogs | `TOKEN_RADIUS_DIALOG` | `aura-glass-apply` copies those rules into `$CONF_DIR/extension-overrides.css`; Aura Glass Helper loads it as an extension sheet, the only rank that outranks Copyous's own stylesheet |
| Other popups | `shell-popup-blur` | `[blur-my-shell/popup] corner-radius` | `TOKEN_RADIUS_POPUP` | `apply_radius_dconf` |
| Volume / brightness OSD pill | none (drawn by Custom OSD) | `[custom-osd]`, `[blur-my-shell/popup] osd-corner-radius` | `TOKEN_RADIUS_OSD` | `sync_osd_profile`, `apply_radius_dconf`. Patch: `patches/custom-osd-gnome50.patch` |
| App folders | `shell-00-flat` | `[blur-my-shell/appfolder]` | `TOKEN_SIGMA_APPFOLDER` | `load_dconf` |
| Overview | none | `[blur-my-shell/overview]`. Patch: `blur-my-shell-overview.patch` | none | `load_dconf` |
| Dash to Dock / window list | none | `[blur-my-shell/dash-to-dock]`, `[…/window-list]` | `TOKEN_SIGMA_DASH_TO_DOCK`, `TOKEN_SIGMA_WINDOW_LIST` | `load_dconf` |
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
| Window corners and surfaces | `gtk4-70-surfaces` | `[blur-my-shell/applications] corner-radius` + pipeline `windows` corner | `TOKEN_RADIUS_WINDOW` | `apply_radius_css`, `apply_radius_dconf`, `apply_pipeline_radius` |
| Window transparency | `gtk4-transparency` (installed only if level ≠ 0) | `[blur-my-shell/applications] opacity` (the level × 255, so non-GTK apps like Chrome show the blur too) | `TOKEN_APP_TRANSPARENCY_SHIPPED` | `install_transparency_css` → `tools/rescale-transparency.py`. Memo `$C/app-transparency` |
| App tint | `gtk4-transparency` | none | `TOKEN_APP_TINT` | `apply_app_tint_color` → `tools/apply-tint-color.py`. Memo `$C/app-tint-color` |
| Blur behind app windows | none | `[blur-my-shell/applications] blur, enable-all, whitelist, blacklist, sigma, brightness` | `TOKEN_SIGMA_APPLICATIONS` | `apply_app_blur` (`app_blur_literal`), `apply_window_brightness` |
| Accent colour in GTK | substituted by `aura-glass-apply` (`@accent_bg_color`) | none | none | `apply_accent` |

## 3. GTK3 apps

| Feature | Stylesheet | Note |
|---|---|---|
| Everything GTK3 | `gtk3-tweaks` | User CSS at `PRIORITY_USER`, so it wins regardless of specificity. Window corners use `TOKEN_RADIUS_WINDOW`. |
| Titlebar button style | `gtk3-window-controls-<style>` | Must mirror the GTK4 sheet of the same style. |

## 4. Blur-wide controls

| Feature | Where | Applied by |
|---|---|---|
| Blur strength (25–200 %) | every BMS sigma and the `unscaled_radius` values in `pipelines` | `apply_blur_strength`. Memo `$C/blur-strength` (frosted drawer) |
| Popup blur brightness (50–150 %) | `[popup] brightness` + pipeline `popups` | `apply_popup_brightness` → `tools/apply-popup-brightness.py` |
| Window blur brightness (50–150 %) | `[applications] brightness` | `apply_window_brightness` |
| Static blur behind a full-screen window, dynamic behind a smaller one | `patches/blur-my-shell-static-maximized.patch`: a window maximized both ways, fullscreen, or sized over its monitor's whole work area (Tiling Assistant's drag-to-top with `maximize-with-gap`) is rebuilt on the `windows` pipeline (static, cached wallpaper blur) and goes back to dynamic when it shrinks. `[applications] static-blur=true` (liquid windows) still makes every window static | `install_bms` |
| Grain (0–1) | the noise effect in pipelines | `apply_grain` |
| Glass style (frosted / liquid / vibrant / tinted / smoked) | a `refraction` effect (id prefix `effect_aura_glass_style_`) after the blur in pipelines `panel` and `dock`, corner radius copied from that pipeline's corner effect; liquid also sets `[dash-to-dock] static-blur=true`. `--liquid-windows` adds pipeline `windows` and `[applications] static-blur=true`. Vibrant is a `luminosity` effect (saturation 1.35, brightness 1.06, 1.0 on the lock screen and windows) after the blur in pipeline `lock screen` and before the corner in `panel`, leaving the dock dynamic; with `--liquid-windows` also pipeline `windows` and `[applications] static-blur=true`. Tinted is a `color` effect (accent RGB from `accent_hex`, alpha 0.3, blend Color) and smoked a `luminosity` effect (brightness 0.7, saturation 0.8), both in `panel` and `lock screen` only, never windows. An `--accent` incremental Apply adds the `glass-style` action under tinted | `apply_glass_style`. Memos `$C/glass-style`, `$C/liquid-windows` (top-level, not drawer fields) |
| Popup blur on/off | `[popup] blur` + `shell-popup-blur.css` present/absent | `apply_popup_blur`, `install_css` |
| Notification blur on/off | `[popup] notification` + `shell-notification-blur.css` | `apply_notification_blur`, `install_css` |
| Per-app blur lists | `[applications] whitelist/blacklist`, memos `app-blur-allow/-block` | `apply_app_blur`. Window menu: `aura-glass-preview app-blur` |
| Rounded dynamic blur | `gnome-rounded-blur` library | `install_rounded_blur` |

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
| `TOKEN_SIGMA_{PANEL,APPFOLDER,POPUP,WINDOW_LIST,APPLICATIONS,DASH_TO_DOCK}` | 30 / 50 / 30 / 30 / 12 / 4 | the matching `core.ini` section's `sigma` | `check-tokens.sh` |
| `TOKEN_APP_TRANSPARENCY_SHIPPED` | 0.92 | `gtk4-transparency.css` | `check-tokens.sh` |
| `TOKEN_APP_TINT` | 45 | `gtk4-transparency.css` | `check-tokens.sh` |

Radius presets also live in `radius_preset_values`/`radius_bounds`
(`tokens.sh`) **and** in `RADIUS_PRESET_VALUES`/`RADIUS_SURFACES`
(`gui/aura_glass_settings.py`). `check-gui-radius.py` holds them together.
