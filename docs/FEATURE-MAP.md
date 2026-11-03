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
| Top panel | `shell-00-flat` | `[blur-my-shell/panel]`, pipeline `lock screen` (shared with the overview background) | none | `install_css`, `load_dconf` |
| Top bar shaded behind a maximized window | `shell-00-flat` (`#panel.aura-glass-maximized`, 60% black shipped, alpha rewritten by `apply_maximized_panel_brightness` from `--maximized-panel-brightness`, settings app → Appearance → Titlebar & top bar; 250ms fade both ways) | none | none | Aura Glass Helper `_syncPanelShade`: focused window on the primary monitor that is maximized, fullscreen or covers the work area (Tiling Assistant `maximize-with-gap`), outside the overview |
| Panel blur after monitor changes | none | none | none | Blur My Shell v76 keeps it aligned itself. The old `aura-glass-panel-blur.service` is removed by `remove_panel_blur_unit` |
| Panel icon size for this display, Copyous and tray icons included | generated `shell-90-density`, Status Tray `icon-size` | none | `TUNED_PPI` (in `steps-css.sh`) | `measure_logical_ppi`, `density_css`, `sync_tray_icon_size`; re-measured on a layout change by the Helper (`aura-glass-display-sync`, `write_display_sheet`) |
| Top bar height (24–48 px, settings app → Glass → Top bar; reset goes to GNOME's 32), snapped so there is no seam under a maximized window | generated `shell-90-density` (`#panel { height }`: the asked height snapped to whole device pixels, so 39px for the theme's 40 at 1.33/1.67; absent when that is the theme's own 40) | none | `PANEL_HEIGHT_THEME` 40, `PANEL_HEIGHT_GNOME` 32 (`steps-css.sh`, copied in `gui/aura_glass_settings.py`, held by `check-gui-flags.py`) | `resolve_panel_height`, `measure_primary_scale`, `panel_height_css`. Memo `$C/panel-height` |
| Quick Settings panel | `shell-20-popup-menus`, `shell-popup-blur` | `[blur-my-shell/popup] quick-settings-corner-radius` | `TOKEN_RADIUS_QUICK_SETTINGS` | `install_css`, `apply_radius_*` |
| Quick Settings sliders | `shell-10-quick-settings` | none | none | `install_css` |
| Quick toggles and switches | `shell-40-quick-toggles` | none | none (follows `-st-accent-color`) | `install_css` |
| Popup menus (panel, right-click) | `shell-20-popup-menus`, `shell-popup-blur` | `[blur-my-shell/popup] menu-corner-radius`, pipeline `popups` | `TOKEN_RADIUS_MENU`, `TOKEN_BLUR_RADIUS_POPUP` | `install_css`, `apply_popup_blur`, `apply_blur_pipelines`; opacity `apply_popup_transparency` (`--popup-opacity`, else the windows' level) |
| Date / calendar menu | `shell-20-popup-menus`, `shell-popup-blur` | grouped with **Quick Settings** radius, not the menu one | `TOKEN_RADIUS_QUICK_SETTINGS` | as above |
| Notification banners and history cards | `shell-30-notifications`, `shell-notification-blur` | the popup blur (v76 has no separate notification switch), `notification-corner-radius` | `TOKEN_RADIUS_NOTIFICATION` | `install_css` (the sheet goes with `--popup-blur`), `apply_notification_opacity` (`tools/apply-notification-opacity.py`, ground 40 × the popup opacity / 90) |
| Modal dialogs (auth, power, run) | `shell-50-dialogs` | `[blur-my-shell/popup] dialog-corner-radius` | `TOKEN_RADIUS_DIALOG` | `install_css` |
| Copyous clipboard dialog (Super+V) | `.modal-dialog.clipboard-dialog` in `shell-50-dialogs`, `shell-popup-blur`, `shell-80-solid`; its cards, buttons and search bar on the white lift ladder in `shell-50-dialogs` | as modal dialogs | `TOKEN_RADIUS_DIALOG` | `aura-glass-apply` copies those rules into `$CONF_DIR/extension-overrides.css`; Aura Glass Helper loads it as an extension sheet, the only rank that outranks Copyous's own stylesheet |
| Other popups | `shell-popup-blur` | `[blur-my-shell/popup] corner-radius` | `TOKEN_RADIUS_POPUP` | `apply_radius_dconf` |
| Volume / brightness OSD pill | none (drawn by Custom OSD) | `[custom-osd]`, `[blur-my-shell/popup] osd-corner-radius` | `TOKEN_RADIUS_OSD` | `apply_osd_device_name`, `sync_osd_profile`, `apply_radius_dconf`. Patch: `patches/custom-osd-gnome50.patch` |
| Volume / brightness OSD background opacity and tint | none (drawn by Custom OSD) | `[custom-osd] alpha`, `[custom-osd] bgcolor` | none | `apply_osd_background`, `sync_osd_profile`. Memos `$C/osd-opacity`, `$C/osd-tint` |
| App folders | `shell-00-flat` | `[blur-my-shell/appfolder]`, pipeline `app folders` | `TOKEN_BLUR_RADIUS_APPFOLDER` | `load_dconf` |
| Overview workspace corners | none | `[blur-my-shell/overview] workspace-corner-radius`. Only while the overview blur is on: with it off (performance, adaptive overlay) Blur My Shell leaves GNOME's hardcoded 30 | `TOKEN_RADIUS_WINDOW` | `apply_radius_dconf` |
| Overview | search bar and results fill in `shell-00-flat`, `shell-80-solid` | `[blur-my-shell/overview]`; window blur kept out by `[applications] blur-on-overview=false`, faded out on opening it and eased back in on leaving it by `patches/blur-my-shell-overview-fade.patch` (following the overview's progress during a touchpad swipe, both ways) | none | `load_dconf` |
| Overview dash, Dash to Dock / window list | `#dash .dash-background` in `shell-00-flat`, `shell-80-solid` (the fill only shows with `override-background=false`) | `[blur-my-shell/dash-to-dock]`, `[…/window-list]`, pipelines `dock`, `window list`. The overview dash blurs the app grid under it (`patches/blur-my-shell-upstream-backports.patch`, #1211) because `unblur-in-overview=false` | `TOKEN_BLUR_RADIUS_DASH_TO_DOCK`, `TOKEN_BLUR_RADIUS_WINDOW_LIST` | `load_dconf` |
| Lock screen blur | none | `[blur-my-shell/lockscreen]` | none | `load_dconf` |
| Shell tint (hue of dark surfaces) | every shell sheet (installed copies) | none | none | `apply_shell_tint_color` → `tools/apply-shell-tint.py`. Memo `$C/shell-tint-color` |
| Dock & search colour, top bar colour (desktop, maximized) | `#dash .dash-background`, `#overview .search-entry`, `#panel.aura-glass-maximized` (channels rewritten in the installed copies); the desktop bar's rule is appended to `shell-00-flat`, and `aura-glass-apply` copies its `#panel.transparent-panel` half into `extension-overrides.css` | none | none | `apply_surface_tint_colors` → `tools/apply-shell-tint.py --surface`. Memos `$C/dock-tint-color`, `$C/panel-tint-color`, `$C/maximized-panel-tint-color` |
| Performance mode shell look | `shell-80-solid` (opaque ladder) | `dconf/solid.ini` (fresh preset loads only) | `TOKEN_RADIUS_NOTIFICATION` | `install_css` (when `WANT_BLUR=0`), `apply_popup_transparency` |
| Accent colour in the shell | substituted by `bin/aura-glass-apply` (`-st-accent-color`) | none | none | `apply_accent`. gsettings `accent-color` |
| Login screen (GDM) | `gdm-auth-menu` (session switcher menu), `shell-50-dialogs` | none | none | `lib/steps-gdm.sh`, `bin/aura-glass-gdm-sync` (opt-in, root) |
| Login screen cursor, icons and font | none | `/etc/dconf/db/gdm.d/90-aura-glass` | none | `sync_gdm_look` copies the desktop's packs to `/usr/share/icons` and an Aura-installed font to `/usr/share/fonts/aura-glass`, marked `.aura-glass-gdm`, and sets `font-name`. Every retune that changes icons, cursor or font re-runs it (`sync_gdm_look_if_installed`) when it differs from the `gdm-look` memo, as root through `sudo -n` or one polkit (`pkexec`) prompt; `aura-glass-gdm-sync` retries the same at login |

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
| Blur behind app windows | none | `[blur-my-shell/applications] blur, enable-all, whitelist, blacklist`, pipeline `windows`. Dialogs and tool palettes follow their app (`patches/blur-my-shell-subwindows.patch`). A `title:` entry matches the window title instead of its class, up the same chain (`patches/blur-my-shell-upstream-backports.patch`, #1217). The window menu checkmark reads them too; its toggle only writes classes | `TOKEN_BLUR_RADIUS_APPLICATIONS` | `apply_app_blur` (`app_blur_literal`), `apply_blur_pipelines` |
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
| One surface's own blur amount and brightness (windows, maximized windows, popups & notifications, top bar, lock screen + overview) | the pipeline its component (`applications`, `popup`, `panel`, `lockscreen`) points at; `main` follows the main values. Dock, app folders and window list follow the main values only | `apply_blur_pipelines` (`BLUR_SURFACES`). Memos `$C/<surface>-blur-strength`, `$C/<surface>-blur-brightness` (frosted drawer) |
| Popups & notifications opacity (70–100, or follow the windows) | `shell-popup-blur.css` alphas and the banner ground in `shell-notification-blur.css` | `apply_popup_transparency`, `apply_notification_opacity`. Memo `$C/popup-opacity` (frosted drawer) |
| Moving an install onto v76's pipelines | `pipelines`, `settings-version`, every component's `pipeline`; legacy `sigma`/`brightness`/`customize` reset | `upgrade_bms_settings` (once: below version 7, or after v76's own migration) |
| Grain (0–1) | the noise effect in pipelines | `apply_grain` |
| Smooth animations (VRAM for no reallocation as an animation starts) | `full-size-buffers` from `patches/blur-my-shell-full-size-buffers.patch`, and `CLUTTER_PAINT` in `~/.config/environment.d/aura-glass.conf` | `apply_smooth_animations`. Memo `$C/smooth-animations` (top-level). Settings app: Animations → Smoothness |
| Animation speed (windows, notification banners, menus) | none (no dconf, no CSS) | `apply_animation_speed` writes memos `$C/{window,notification,menu}-animation-speed` (top-level); the Aura Glass Helper (`_readAnimationSpeeds`, `_hookEase`) scales `Clutter.Actor.prototype.ease` durations by actor kind, hooked only while a speed isn't 100. Settings app: Animations |
| Glass style (frosted / liquid / vibrant / tinted / smoked) | a `refraction` effect (id prefix `effect_aura_glass_style_`) after the blur in pipeline `dock` (v76 rounds it from the component's corner; never the top bar, whose pipeline is the overview's); liquid also sets `[dash-to-dock] static-blur=true`. `--liquid-windows` adds pipeline `windows` and `[applications] static-blur=true`. Vibrant is a `luminosity` effect (saturation 1.35, brightness 1.0) ahead of the blur in pipeline `lock screen` (top bar, overview, lock screen), leaving the dock dynamic; with `--liquid-windows` also pipeline `windows` and `[applications] static-blur=true`. Tinted is a `color` effect (accent RGB from `accent_hex`, alpha 0.3, blend Color) and smoked a `luminosity` effect (brightness 0.7, saturation 0.8), both in `lock screen` only, never windows. An `--accent` incremental Apply adds the `glass-style` action under tinted | `apply_glass_style`. Memos `$C/glass-style`, `$C/liquid-windows` (top-level, not drawer fields) |
| Popup blur on/off | `[popup] blur` + `shell-popup-blur.css` present/absent | `apply_popup_blur`, `install_css` |
| Notification blur | follows the popup blur: `shell-notification-blur.css` is installed with `shell-popup-blur.css` (`--notification-blur` is retired) | `install_css` |
| Static or dynamic blur per window | none | `[blur-my-shell/applications] static-blur=false`, with `patches/blur-my-shell-static-maximized.patch` turning a window static while it covers its monitor (shows the wallpaper only, not the windows behind it) and dynamic otherwise. `covers_monitor` is the same test as `coversMonitor` in the helper. `--liquid-windows` sets `static-blur=true`: every window static | none | `apply_glass_style` (`--liquid-windows`), `install_bms` |
| Maximized windows: static or dynamic, and a static one's own blur amount and brightness (settings app → Glass → app chip) | none | `[blur-my-shell/applications] maximized-static-blur`, pipeline `maximized` (named by the patch, not a key; unused while `static-blur=true`) | `TOKEN_BLUR_RADIUS_APPLICATIONS` | `apply_maximized_blur` (`--maximized-blur`), `apply_blur_pipelines` (`--maximized-blur-strength`, `--maximized-brightness`, inserts the pipeline on an existing install) |
| Per-app blur lists | `[applications] whitelist/blacklist`, memos `app-blur-allow/-block` | `apply_app_blur`. Window menu: `aura-glass-preview app-blur` |

## 5. Modes and adaptive

| Feature | Files | Notes |
|---|---|---|
| Frosted / Performance | `lib/steps-modes.sh`, `$C/glass-mode`, `$C/modes/<mode>/` | See ARCHITECTURE §3 |
| Adaptive profiles (Auto / Full Glass / Performance) | `extensions/…/extension.js` (menu), `bin/aura-glass-adaptive`, `tools/aura_glass_adaptive.py`, `apply_adaptive_blur` in `lib/steps-dconf.sh`, `systemd/aura-glass-adaptive.service` | State in `$C/adaptive-profile`, `$C/adaptive-performance/`. Shown in the settings app's header button, switched from the panel menu, or `aura-glass-adaptive profile` while that icon is hidden |
| Aura Glass icon in the top bar (settings app → Appearance → Titlebar & top bar) | Helper `_buildPanelMenu`, `_syncTopBarIcon`, `apply_top_bar_icon` in `lib/steps-dconf.sh` | Memo `$C/top-bar-icon`, read live by the Helper's config monitor. Hiding it keeps the indicator built and hides its container |
| Fullscreen games list | settings app → Per-app blur → Games | `$C/adaptive-fullscreen-apps` |

## 6. Assets, fonts, extensions

| Feature | Files |
|---|---|
| Icon packs + accent mapping | `lib/steps-assets.sh` (`install_icons`, `icon_base`, `accent_to_*`), `bin/aura-glass-icon-sync` (light/dark) |
| System icons over a pack (`--system-icons`) | `symbols/lucide/` (Lucide with strokes outlined, generated and committed), `system_icons_choice`, `write_system_icons`, `prune_system_icons` in `lib/steps-assets.sh`, `apply_icon_theme`, `bin/aura-glass-icon-sync`, `gdm_theme_closure` |
| Pointer packs, size | `lib/steps-assets.sh` (`install_cursors`, `install_moga_cursors`), `tools/moga_cursor.py`, `apply_cursor_theme`, `apply_cursor_size`, Wiggly's magnified pointer: `patch_wiggly_extension` + `patches/wiggly-follow-cursor.patch` |
| Tray icon default effect (desaturation, brightness, contrast, tint) | `patch_status_tray_extension` in `lib/steps-extensions.sh`; per-app tuning is Status Tray's `icon-effect-overrides` |
| Tray icons only the theme has (Solaar's battery level) | `patch_status_tray_icon_lookup` in `lib/steps-extensions.sh` |
| Fonts | `lib/steps-fonts.sh`, `apply_font` |
| Extension catalogue | `lib/steps.sh` (arrays, `ext_description`), `bin/aura-glass-ext`, `lib/steps-extensions.sh` |
| Tiling Assistant's drag-to-top and `tile-maximize` really maximize, so the titlebar button shows restore (`maximize-with-gap` reset unless a screen gap needs it) | `lib/steps-dconf.sh` (`apply_tiling_maximize`, from `apply_gsettings`) |
| Blur This App (window menu) | `extensions/aura-glass-blur@aura-glass.local/extension.js` → `aura-glass-operation app-blur`. Shown or hidden by `--window-menu` (memo `window-menu`, set in the settings app's Per-app blur) |
| Mouse wheel switches workspaces while dragging in the overview | `extensions/aura-glass-blur@aura-glass.local/extension.js` (`_attachDragScroll`, `_onDragScroll`) |
| A window let go near a workspace or thumbnail in the overview still lands there | `extensions/aura-glass-blur@aura-glass.local/extension.js` (`_hookDropTargets`, `_workspaceNear`, `_delegateOtherScreens`) |
| The log out dialog starts keyboard focus on Log Out | `extensions/aura-glass-blur@aura-glass.local/extension.js` (`_hookEndSessionDialog`) |

## 7. Installer / system behaviour

| Behaviour | Files |
|---|---|
| Flag parsing, resolution, step order | `install.sh` |
| Incremental Apply classification | `lib/steps-apply-plan.sh` |
| What an update runs (parts, hashes, `$C/installed-parts`) | `lib/steps-apply-plan.sh` |
| Writer lock | `bin/aura-glass-operation`, `tools/aura_glass_operation.py` |
| Splicing, flattening, accent swap, atomic publish | `bin/aura-glass-apply` |
| Live preview | `bin/aura-glass-preview`, `gui/preview_queue.py` |
| Tint picker's suggestions (three rows, from the wallpaper) | `gui/wallpaper_palette.py` (colour work, stdlib only), `WallpaperWatch`, `GlassSwatch` and `TintPalette` in `gui/aura_glass_settings.py`. They only propose: a pick is the same `--*-tint-color` flag as a typed hex |
| Backups, dry-run, memo guard | `lib/common.sh` (`backup_once`, `run`, `remembering`) |
| Dependencies, distro detection | `lib/distro.sh` |
| Legacy rename (`tahoe-glass`) | `lib/steps-migrate.sh` |
| Update check / channel | `bin/aura-glass-update-check`, `systemd/aura-glass-update-check.*`, `current_branch` / `is_test_build` in the GUI |
| Installing an update, release list, history | `bin/aura-glass-update`, `updates_snapshot` / `_render_updates` / `update_blockers` in the GUI |
| Uninstall | `uninstall.sh` |

## 8. Which numbers are written twice (change them together)

| Token (`tokens/tokens.sh`) | Value | Consumers | Checker |
|---|---|---|---|
| `TOKEN_RADIUS_WINDOW` | 30 | `gtk3-tweaks.css`, `gtk4-70-surfaces.css`, `core.ini [applications] corner-radius`, `core.ini [overview] workspace-corner-radius`, the pipeline `windows` corner in `core.ini`, the GUI preset table | `check-tokens.sh`, `check-gui-radius.py` |
| `TOKEN_RADIUS_MENU` | 26 | `shell-20-popup-menus.css`, `shell-popup-blur.css`, `core.ini [popup] menu-corner-radius` | `check-tokens.sh` |
| `TOKEN_RADIUS_QUICK_SETTINGS` | 33 | `shell-20-popup-menus.css` (2 sites), `shell-popup-blur.css` (2), `core.ini [popup] quick-settings-corner-radius` | `check-tokens.sh` |
| `TOKEN_RADIUS_NOTIFICATION` | 20 | `shell-30-notifications.css` (4), `shell-80-solid.css` (2), `core.ini [popup] notification-corner-radius` | `check-tokens.sh` |
| `TOKEN_RADIUS_DIALOG` | 20 | `shell-50-dialogs.css`, `core.ini [popup] dialog-corner-radius` | `check-tokens.sh` |
| `TOKEN_RADIUS_POPUP` | 20 | `core.ini [popup] corner-radius` | `check-tokens.sh` |
| `TOKEN_RADIUS_OSD` | 12 | `core.ini [popup] osd-corner-radius` | `check-tokens.sh` |
| `TOKEN_RADIUS_BUTTON` | 9999 | `gtk4-20-buttons.css` | `check-tokens.sh` |
| `TOKEN_BLUR_RADIUS_{PANEL,APPFOLDER,POPUP,WINDOW_LIST,APPLICATIONS,DASH_TO_DOCK}` | 12 / 100 / 60 / 60 / 24 / 8 | the `unscaled_radius` of the matching pipeline in `core.ini` (`APPLICATIONS`: both `windows` and `maximized`) | `check-tokens.sh` |
| `TOKEN_APP_TRANSPARENCY_SHIPPED` | 0.92 | `gtk4-transparency.css` | `check-tokens.sh` |
| `TOKEN_APP_TINT` | 45 | `gtk4-transparency.css`, `gui/wallpaper_palette.py` (`APP_TINT_SHARE`) | `check-tokens.sh` |

Radius presets also live in `radius_preset_values`/`radius_bounds`
(`tokens.sh`) **and** in `RADIUS_PRESET_VALUES`/`RADIUS_SURFACES`
(`gui/aura_glass_settings.py`). `check-gui-radius.py` holds them together.
