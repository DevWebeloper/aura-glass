# Structure and maps

Four maps of the same project:

1. [Repository map](#1-repository-map): every file, and what it is.
2. [Installed map](#2-installed-map): where each repo file lands on a user's machine.
3. [Call map](#3-call-map): which program runs which.
4. [Ownership map](#4-ownership-map): which function writes which piece of state.

For "which file draws this button / owns this setting", use
[FEATURE-MAP.md](FEATURE-MAP.md).

---

## 1. Repository map

### Top level

| Path | What it is |
|---|---|
| `install.sh` | Entry point. Lock re-exec, sources `lib/` and `tokens/`, flag parsing (`parse_flags`), the GUI/text setup wizard, the resolution block, and orchestration of a full install or a `--settings-only` retune. |
| `uninstall.sh` | Reverses an install in scopes: base, `--extensions`, `--assets`, `--gdm`, `--gdm-monitors`, `--all`. Interactive by default. |
| `README.md` | The user document. |
| `CLAUDE.md` / `AGENTS.md` / `llms.txt` | Instructions and an index for AI agents. |
| `CONTRIBUTING.md` | The short contributor guide. |
| `LICENSE` | MIT. |
| `wallpapers/` | Bundled wallpapers (JPEG). `install_wallpapers` copies them and lists them in Settings > Appearance; it never sets one. |
| `.gitignore` | Ignores preview screenshots, `__pycache__`, IDE files, `.agents/` and `*.code-workspace`. |

### `lib/`: the steps (sourced by `install.sh`; definitions only)

| File | Owns |
|---|---|
| `common.sh` | Output helpers (`step info ok warn skip die`), `run` (dry-run aware), `install_if_changed`, `remembering`, `confirm`/`confirm_always`, `backup_once`, `gsettings_backup_once`/`gsettings_original`, pinned fetchers (`clone_pinned`, `clone_pinned_sparse`, `fetch_tarball_pinned`, `fetch_zip_pinned`), `gnome_major`, `monitor_count`, `multi_monitor_detected`, `prompt_logout`, patch stamps. |
| `distro.sh` | `detect_distro` (arch/fedora/debian/suse), `missing_cmds`, `install_deps`, the GUI toolkit probe and hints, `pkg_owner`/`pkg_remove_cmd`, `ensure_aur_helper`. |
| `steps.sh` | Upstream pins, paths (`CONF_DIR`, `EXT_DIR`, `SRC_CACHE`, `BACKUP_DIR`), extension arrays and `ext_description`, `preflight`, `install_theme`, `finish`. **Sourced first**, because flag parsing reads `CONF_DIR`. |
| `steps-migrate.sh` | Moving from `tahoe-glass` to `aura-glass`: `migrate_legacy_names`, `merge_backups`, `adopt_theme_dir`, `sweep_theme_orphans`. The one-time solid-era migration, `migrate_solid_era`. |
| `steps-extensions.sh` | EGO installs, the pinned BMS and Custom OSD builds plus patches, the first-party extension (`install_aura_ext`), `install_rounded_blur`, enable/queue helpers, `refresh_bms_after_dconf`, `disable_retired_extensions`. |
| `steps-assets.sh` | Icon packs (Colloid, Reversal, Hatter, MacTahoe) and accent mapping (`icon_base`, `accent_to_*`); pointers (Adwaita, AOSP, MacTahoe, Moga, original); `install_wallpapers`. |
| `steps-fonts.sh` | `--font` installs: Inter, MiSans (Latin + Arabic), SF Pro. |
| `steps-modes.sh` | Glass modes: `resolve_glass_mode`, `apply_glass_mode`, the drawers (`seed_glass_mode`, `load_glass_mode_memos`, `save_glass_mode_memos`), `remember_glass_mode`. |
| `steps-css.sh` | `install_css` and the rewriter wrappers (transparency, tints, popup transparency, notification opacity, radius), `install_window_control_style`, display density (`measure_logical_ppi`, `density_css`). |
| `steps-dconf.sh` | `load_dconf` and every `apply_*` that writes a dconf/gsettings key: radii, pipelines, app blur and lists, popup/notification blur, grain, brightnesses, blur strength, `apply_adaptive_blur`, window buttons, cursor theme/size, accent, Moga variants, `apply_gsettings`, `apply_font`. |
| `steps-integration.sh` | `install_icon_sync`, `flatpak_override`, `install_panel_blur_unit`, `install_adaptive_performance`. |
| `steps-gdm.sh` | Login screen theme, wallpaper generation, monitor sync, and the GDM sync unit (all opt-in, root). |
| `steps-gui.sh` | `install_gui` (settings window, launcher, preview, desktop entry, icon, the `repo-path` memo), `install_first_open_autostart`, `install_update_check`. |
| `steps-wizard.sh` | `run_setup_wizard`, which runs the GTK wizard and reads its flags back. |
| `steps-apply-plan.sh` | The incremental classifier (`select_apply_actions`) and `apply_source_fingerprint`. |

### `tokens/`

| File | Owns |
|---|---|
| `tokens.sh` | Every number written in more than one place: 8 radii, 6 BMS sigmas, `TOKEN_APP_TRANSPARENCY_SHIPPED` (0.92), `TOKEN_APP_TINT` (45). Also the radius presets (`radius_preset_values`, `radius_preset_canonical`, `radius_bounds`, `radius_preset_matches_shipped`). Each token's comment lists its consumers. |

### `css/`: stylesheets (the `NN-` prefix is the cascade order)

| Shell (St) | GTK4 | GTK3 |
|---|---|---|
| `shell-00-flat` panel, translucency ladder, flattening | `gtk4-00-flat` shared ladder | `gtk3-tweaks` everything GTK3 |
| `shell-10-quick-settings` QS sliders | `gtk4-10-fields` entries, spin buttons | `gtk3-window-controls-{adwaita,material,flat}` one, by style |
| `shell-20-popup-menus` menus, date menu | `gtk4-20-buttons` labelled buttons, suggested/destructive | |
| `shell-30-notifications` banners, history cards | `gtk4-30-dropdowns` dropdowns, combo rows | |
| `shell-40-quick-toggles` toggles, switches | `gtk4-40-containers` boxed lists, cards, rows | |
| `shell-50-dialogs` modal, auth, end-session dialogs | `gtk4-50-window-controls` base titlebar buttons ("minimal") | |
| `shell-80-solid` opaque ladder (Performance / `--no-blur`) | `gtk4-60-controls` switches, checks, radios, sliders | |
| `shell-popup-blur` popup alphas over real blur | `gtk4-70-surfaces` surfaces, Nautilus status, sidebars | |
| `shell-notification-blur` notification alphas over real blur | `gtk4-transparency` translucent windows (rescaled, tinted) | |
| *(generated)* `shell-90-density` panel icon scale for this display | `gtk4-window-controls-{adwaita,material,flat}` one, by style | |

### `dconf/`

| File | Loaded |
|---|---|
| `core.ini` | Blur My Shell (pipelines, every component, sigmas, radii, app lists) and Custom OSD. Loaded on a fresh install or with `--force`, and skipped on an existing install (see ARCHITECTURE §7). |
| `solid.ini` | On top of core when `WANT_BLUR=0`: every BMS component's `blur=false`, plus OSD alpha. |
| `extras.ini` | Vitals, Hot Edge, AppIndicator, Wiggly settings, when extras are wanted. |

### `patches/`

| Patch | Target |
|---|---|
| `blur-my-shell-overview.patch` | BMS: take blur out of overview window previews when `blur-on-overview` is false |
| `blur-my-shell-subwindows.patch` | BMS: blur a blurred app's ATTACHED dialogs and UTILITY palettes too |
| `blur-my-shell-notifications.patch` | BMS: split notifications onto their own `popup/notification` key |
| `blur-my-shell-static-maximized.patch` | BMS: static blur for a window that covers its monitor (maximized both ways, fullscreen, or filling the work area), dynamic for smaller ones |
| `custom-osd-gnome50.patch` | Custom OSD on GNOME 50/51 |
| `copyous-gnome51.patch` | Copyous on GNOME 51 |
| `gnome-rounded-blur-offstage.patch` | gnome-rounded-blur: place the background blur right in screenshots (off-stage paints) |

### `bin/`: commands (most installed into `~/.local/bin`)

| Command | Purpose | Installed by |
|---|---|---|
| `aura-glass-apply` | Splice installed sheets into the 4 targets (flatten, accent swap, atomic publish, shell reload). `--json`, `--force-reload`, `--no-shell-reload`. | `install_css` |
| `aura-glass-operation` | The writer lock: `run -- CMD…`, `held`, `app-blur --wm-class X --enabled 0\|1`. | `install_css` |
| `aura-glass-preview` | Live preview: `begin`, `set`, `apps`, `revert`, `status`, `commit --session S -- CMD`, and `app-blur` (window-menu writer). | `install_gui` |
| `aura-glass-settings` | Launches the settings window (`AURA_GLASS_GUI` overrides it with a checkout). | `install_gui` |
| `aura-glass-open-once` | First-login autostart: removes its own `.desktop` file, then opens the settings window. | `install_first_open_autostart` |
| `aura-glass-ext` | Extension catalogue: `list`, `install`/`remove`/`enable`/`disable UUID`, `recommended`, `full`. | not installed; run from the checkout |
| `aura-glass-update-check` | Compare the checkout with the remote's tags or branch. `--notify` is used by the timer. | `install_update_check` |
| `aura-glass-update` | Put the checkout on a release tag or a branch tip (stash edits, back up diverged commits), then run `install.sh --gui`. `--no-install` switches only. What the Updates page's Install runs. | `install_update_check` |
| `aura-glass-icon-sync` | Follow light/dark with the icon variant (service). | `install_icon_sync` |
| `aura-glass-panel-blur` | Launcher for `aura_glass_panel_blur.py` (service). | `install_panel_blur_unit` |
| `aura-glass-gdm-sync` | Push wallpaper and monitors to GDM (service, `--once`). | `install_gdm_sync_unit` |
| `aura-glass-adaptive` | Launcher for `aura_glass_adaptive.py`: no args runs the loop; also `profile auto\|full\|performance` and `refresh`. | `install_adaptive_performance` |

### `gui/`

| File | What |
|---|---|
| `aura_glass_setup_wizard.py` | First-run GTK wizard. Prints flags on stdout. |
| `aura_glass_settings.py` | The settings app (~7,000 lines): `Settings` (state read from memos), `flags_against`, the `Window` pages, `ShellBridge` (D-Bus client), terminal spawning, update logic. |
| `preview_queue.py` | `PreviewQueue`: one active preview operation plus one replaceable pending one. Apply, Revert and Close take priority. |
| `icons/io.github.DevWebeloper.AuraGlassSettings.svg` | App icon (also the README logo). |

### `extensions/aura-glass-blur@aura-glass.local/`

`extension.js` and `metadata.json`. This is "Aura Glass Helper": Blur This App,
the D-Bus bridge and the adaptive profile menu. Shell versions 48–51.

### `systemd/`

`aura-glass-icon-sync.service`, `aura-glass-panel-blur.service`,
`aura-glass-gdm-sync.service`, `aura-glass-update-check.service` + `.timer`,
`aura-glass-adaptive.service`.

### `tools/`: three different kinds of file

**A. Runtime helpers.** Part of the theme. `lib/` and `bin/` call them on every
install or retune. Don't move or rename one without updating its callers.

| Helper | Called from |
|---|---|
| `rescale-transparency.py` | `install_transparency_css` |
| `apply-tint-color.py` | `apply_app_tint_color` |
| `apply-shell-tint.py` | `apply_shell_tint_color` |
| `apply-notification-opacity.py` | `apply_notification_opacity` |
| `apply-radius-preset.py` | `apply_radius_css` (imports `token_manifest.py`) |
| `apply-popup-brightness.py` | `apply_popup_brightness` |
| `token_manifest.py` | `apply-radius-preset.py`, `check-tokens.sh` (and the pattern `apply_pipeline_radius` mirrors) |
| `moga_cursor.py` | `install_moga_cursors` (resolves official release metadata) |
| `aura_glass_operation.py` | `bin/aura-glass-operation` (copied to `~/.local/share/aura-glass/`) |
| `aura_glass_panel_blur.py` | `bin/aura-glass-panel-blur` (copied to `~/.local/share/aura-glass/`) |
| `aura_glass_adaptive.py` | `bin/aura-glass-adaptive` (copied to `~/.local/share/aura-glass/`) |

The rewriters run **from the checkout** (`$REPO_ROOT/tools/…`), so every retune
needs the checkout recorded in `$CONF_DIR/repo-path` to still exist. Only the
three workers and the apply command work without it.

**B. Hermetic checks.** These use fixture `HOME`s, temp dirs, stubs and
`--dry-run`, and are safe to run anywhere: `check-tokens.sh`, `check-cascade.sh`,
`check-radius-preset.sh`, `check-glass-modes.sh`, `check-migration.sh`, `check-ext-catalogue.sh`,
`check-app-blur-lists.sh`, `check-update-check.sh`, `check-adaptive-installer.sh`,
`check-overview-blur.sh`, `check-gui-flags.py`, `check-wizard-flags.py`,
`check-gui-radius.py`, `check-terminal-spawn.py`, `check-update-channel.py`,
`check-preview-queue.py`, `check-operation-recovery.py`,
`check-apply-publication.py`, `check-integration-reconcile.py`,
`check-panel-blur-events.py`, `check-incremental-apply.py`,
`check-apply-feedback.py`, `check-adaptive-worker.py`,
`check-apply-lifecycle.py`. Plus the hook: `hooks/pre-commit` and
`install-hooks.sh`.

**C. Live-session tools.** These touch the real desktop, the real `HOME` or
the GPU. **Agents never run these.** Humans only: `preview.sh`,
`preview-session.sh` (never directly), `preview-shot.py`,
`preview-extensions.py`, `preview-driver/`, `gpu-live.sh`, `gpu-sample.py`,
`check-preview.sh` and `check-shots.py`.

### Not part of the product

| Path | What |
|---|---|
| `docs/` | This documentation, plus historical `superpowers/` design records and upstream PR drafts in `pull-requests/`. |
| `packaging/aur/` | `PKGBUILD`, `.SRCINFO`, `aura-glass.install` and a submission guide (with known issues, KI-13). |
| `.github/` | `release-assets.yml` (tarball and zip on release), `traffic-tracker.yml` plus `scripts/update_traffic.py` (badge JSON in `badges/`, `traffic/`). |
| `screenshots/*.webp`, `screenshots/showcase.gif` | README screenshots (click-through thumbnails) and the looping slideshow built from them. |
| `screenshots/preview/` | Preview harness output (git-ignored). |
| `.claude/` | Local `scene.py` GTK render helper and its README. Untracked, but not git-ignored. |
| `.agents/`, `.superpowers/`, `.idea/`, `*.code-workspace` | Local agent and IDE state (ignored). |

---

## 2. Installed map

```
~/.themes/Aura-Glass/                         base theme (adopted from Tahoe-Dark); gnome-shell.css spliced
~/.config/gtk-4.0/gtk.css, gtk-dark.css       libadwaita override from the base theme; spliced + flattened
~/.config/gtk-3.0/gtk.css                     user CSS; spliced (not flattened)
~/.config/aura-glass/                         $CONF_DIR
  ├─ <memos>                                  one value per file (CONFIG-REFERENCE.md)
  ├─ modes/{frosted,performance}/             per-mode drawers
  ├─ adaptive-performance/                    active, reason, saved-mode-keys
  ├─ backups/                                 <name>.orig | <name>.absent
  ├─ shell-*.css gtk4-*.css gtk3-*.css        installed, rewritten copies of css/
  └─ preview-active, preview-backup/          only while a live preview is open
~/.local/bin/                                 aura-glass-{apply,operation,preview,settings,open-once,update-check,
                                              icon-sync,panel-blur,gdm-sync,adaptive}  (+ tahoe-glass-apply symlink)
~/.local/share/aura-glass/                    gui/ (settings window + preview_queue.py),
                                              aura_glass_{operation,panel_blur,adaptive}.py
~/.local/share/applications/io.github.DevWebeloper.AuraGlassSettings.desktop
~/.local/share/icons/hicolor/scalable/apps/io.github.DevWebeloper.AuraGlassSettings.svg
~/.local/share/gnome-shell/extensions/        user-theme, blur-my-shell, custom-osd, aura-glass-blur, extras
~/.local/share/icons/, ~/.icons/              icon and pointer packs
~/.local/share/fonts/aura-glass/              fonts from --font
~/.local/share/backgrounds/aura-glass/        wallpapers/ copies
~/.local/share/gnome-background-properties/aura-glass.xml   lists them in Settings > Appearance
~/.config/systemd/user/aura-glass-*.service|timer
~/.config/autostart/aura-glass-open-once.desktop   (until the first login spends it)
~/.cache/aura-glass/src/                      pinned upstream checkouts ($SRC_CACHE)
~/.cache/aura-glass/operation.lock            the writer lock
/usr/share/gdm/…, /etc/…                      only with --gdm / --gdm-monitors (root)
```

---

## 3. Call map

```
install.sh ──(not --help/--dry-run)──▶ aura-glass-operation run -- install.sh …
  ├─ run_setup_wizard ─▶ python3 gui/aura_glass_setup_wizard.py --repo R [--gdm-present]  (stdout = flags)
  ├─ install_css ─▶ tools/{rescale-transparency,apply-tint-color,apply-shell-tint,
  │                       apply-notification-opacity,apply-radius-preset}.py
  │              └▶ ~/.local/bin/aura-glass-apply ─▶ (lock already held) splice 4 targets
  ├─ load_dconf ─▶ dconf load; apply_* ─▶ tools/apply-popup-brightness.py
  ├─ install_cursors ─▶ tools/moga_cursor.py (Moga only)
  └─ install_{gui,update_check,icon_sync,panel_blur_unit,adaptive_performance} ─▶ systemctl --user …

aura_glass_settings.py
  ├─ Apply ─▶ PreviewQueue ─▶ [aura-glass-preview commit --session S --] install.sh --settings-only --incremental --yes FLAGS
  ├─ sliders ─▶ aura-glass-preview begin|set|apps|revert
  ├─ Extensions page ─▶ bin/aura-glass-ext list|install|remove|enable|disable
  ├─ root steps, repair, reinstall, update ─▶ a real terminal running install.sh / uninstall.sh
  └─ ShellBridge ─▶ D-Bus io.github.DevWebeloper.AuraGlass (ListWindows, GetFocusState, SetWindowOpacity …)

Aura Glass Helper (extension.js)
  ├─ window menu ─▶ aura-glass-operation app-blur ─▶ aura-glass-preview app-blur ─▶ apply_app_blur
  └─ profile menu ─▶ aura-glass-adaptive profile P ─▶ sample(force) ─▶ install.sh --adaptive-blur …

aura-glass-adaptive.service ─▶ aura_glass_adaptive.py loop ─▶ (D-Bus focus/fullscreen, /sys battery, DRM busy)
                              └▶ aura-glass-operation run -- $CONF_DIR/adaptive-install --settings-only --incremental --adaptive-blur …
```

---

## 4. Ownership map

Who writes what. When two writers own the same thing, they must agree. That's
the subject of [CONSISTENCY.md](CONSISTENCY.md).

| State | Written by | Read by |
|---|---|---|
| Top-level memos | the `apply_*`/`install_*` that consumes the setting (guarded by `remembering`) | `install.sh` resolution, `Settings()` in the GUI, `aura-glass-preview`, adaptive restore (fallback) |
| Mode drawers `modes/<mode>/*` | `seed_glass_mode`, `save_glass_mode_memos` (full runs only) | `load_glass_mode_memos`, `Settings()` (tints, levels), `apply_adaptive_blur restore` |
| `glass-mode` | `remember_glass_mode` | `resolve_glass_mode`, `Settings()`, `apply_adaptive_blur` |
| `app-blur-allow` / `-block` | `apply_app_blur` (installer, preview `app-blur`, window menu) | the same, plus `Settings()` |
| `adaptive-profile` | `aura-glass-adaptive profile`, `install_adaptive_performance` (seed `auto`) | worker, extension menu |
| `adaptive-fullscreen-apps` | settings app (Per-app blur → games) | worker |
| `adaptive-performance/*` | worker (`active`, `reason`), `apply_adaptive_blur` (`saved-mode-keys`) | worker, extension, `install_adaptive_performance` |
| `repo-path` | `install_gui` (only when the GUI is installed) | settings app, preview, update check, adaptive worker (fallback) |
| `adaptive-install` | `install_adaptive_performance` | adaptive worker |
| `apply-source-fingerprint` | the `--settings-only --incremental` full fallback | the incremental classifier |
| BMS dconf subtree | `load_dconf` + `apply_*`, `apply_adaptive_blur`, preview `revert` | Blur My Shell |
| The 4 CSS targets | `aura-glass-apply` only | GNOME Shell (User Themes), GTK |
