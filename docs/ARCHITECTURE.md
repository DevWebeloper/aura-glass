# Architecture

How Aura Glass turns a command line into a themed desktop, and why it's built
this way. File-by-file detail is in [STRUCTURE.md](STRUCTURE.md). Every flag
and memo is in [CONFIG-REFERENCE.md](CONFIG-REFERENCE.md).

---

## 1. The shape of the system

```
 front ends                      the one resolver                         what it writes
 ──────────                      ────────────────                         ──────────────
 ./install.sh FLAGS ─┐
 setup wizard (GTK)  ├─ flags ─▶ install.sh ─ parse_flags ─ resolve ─┬─▶ ~/.config/aura-glass/   memos, mode drawers,
 text wizard         │           (+ lib/*.sh, tokens/tokens.sh)      │                          installed CSS copies, backups/
 settings app ───────┤                                               ├─▶ dconf  /org/gnome/shell/extensions/…
 adaptive worker ────┤  (--settings-only [--incremental] …)          ├─▶ gsettings (accent, themes, icons, cursor, font…)
 aura-glass-preview ─┘  (calls the same apply_* with PREVIEW_MODE=1) └─▶ bin/aura-glass-apply ─▶ 4 generated CSS targets
                                                                          (~/.themes/Aura-Glass/gnome-shell/gnome-shell.css,
 window menu "Blur This App" ─▶ aura-glass-operation app-blur ─▶           ~/.config/gtk-4.0/gtk.css + gtk-dark.css,
     aura-glass-preview app-blur ─▶ apply_app_blur                         ~/.config/gtk-3.0/gtk.css)
```

All project-owned writers run under one lock (`aura-glass-operation`, §10).
Nothing but `install.sh` and the `apply_*` functions in `lib/` decides what a
flag means. Every other program composes flags or calls those functions.

### Two kinds of run

| Run | Command | What it does | Needs |
|---|---|---|---|
| **Full install** | `./install.sh [flags]` | deps → base theme → extensions → rounded-blur → icons → cursors → fonts → dconf preset → CSS → gsettings → extensions on/off → integrations (icon sync, GUI, update timer, Flatpak override, panel-blur unit, adaptive worker) → enable extensions → GDM (opt-in) → `finish` (log out) | network; root only for deps, rounded-blur fallback, GDM |
| **Retune** | `./install.sh --settings-only [flags]` | optional pack/font install if those flags were given → dconf preset → CSS → gsettings → icon sync → extensions on/off → remember mode → GUI, update timer, panel-blur unit, adaptive worker → GDM sync (if installed) | nothing. Offline, unprivileged, a few seconds |

`--settings-only` refuses to run unless `$CONF_DIR` and the theme directory
exist.

Three modifiers narrow a retune further. All three are internal protocols used
by the GUI and the adaptive worker:

| Modifier | Contract |
|---|---|
| `--incremental` | Classify the typed flags (`lib/steps-apply-plan.sh`) and run **only** the matching steps: `accent`, `cursor-theme`, `cursor-size`, `window-buttons`, `window-brightness`, `app-blur`, `css`, `adaptive-blur`. Any other flag, a missing or changed source fingerprint, or no narrow flag at all falls back to the full retune. |
| `--plan-json` | With `--settings-only --incremental --dry-run`, print `{"schema_version":1,"actions":[…],"fallback_reason":…}` on stdout and exit. The settings window asks it for the pending flags (debounced, as a dry run) and shows the answer as the first row of the "N changes" popover: a quick apply and its steps, or a full reapply and why (`plan_summary`). `tools/check-incremental-apply.py` and `check-gui-flags.py` cover it. |
| `--adaptive-blur active\|restore` | Private to the adaptive worker. Requires `--settings-only --incremental`. Applies or removes a **transient** no-blur state without writing any memo (`remembering()` is false while it's set). |

`--deps-only` installs missing dependencies and exits. The settings window
hands it to a terminal because it needs `sudo`.

---

## 2. Resolution: how a setting gets its value

This is the mechanism everything else defends.

```
  a flag typed on the command line                 highest
    ↓
  --glass-mode, for the sub-flags a mode owns      (apply_glass_mode)
    ↓
  the mode's drawer   $CONF_DIR/modes/<mode>/<key> (load_glass_mode_memos)
    ↓
  the top-level memo  $CONF_DIR/<key>              (resolution block in install.sh, or read inside apply_*)
    ↓
  the shipped default                              lowest
```

- **Parsing.** `parse_flags` in `install.sh` is a function, not a loop, because
  it runs twice: once over argv and once over whatever the setup wizard printed.
  Every flag sets its variable and usually an `*_EXPLICIT` twin. `_EXPLICIT`
  means "the user typed this, nothing may overrule it". `TYPED_FLAGS` records
  the raw argv for the incremental classifier.
- **Validation happens before anything is written.** The resolution block
  (`install.sh`, after `parse_flags`) reads memos, normalises
  (transparency → two-decimal fraction, clamped to 0.70–1.00), and `die`s on a
  bad accent, preset, pack, font, cursor size, button style or radius list.
- **Memos are written by the consumer.** Each `apply_*` / `install_*` writes its
  memo as its last step, guarded by `remembering()` (`lib/common.sh`).
  `remembering()` is false under `--dry-run`, under `PREVIEW_MODE=1` (live
  preview) and while `ADAPTIVE_BLUR` is set (transient adaptive state). That's
  what lets the preview and the adaptive worker call the real functions without
  changing what the next run resolves to.
- **Some keys resolve at the point of use** rather than in the block:
  `--window-buttons`, `--cursor-size`, `--titlebar-button-style` and
  `--glass-style` read their
  memo inside their `apply_*`, so a run that dies early never records a value it
  didn't apply.

### Why front ends never resolve

The settings window sends **only the flags that changed**
(`Settings.flags_against`) and lets `install.sh` resolve the rest from memos.
The setup wizard sends a full flag list, but it only runs before an install.
Neither contains a copy of the precedence chain. Where a front end *must* know a
value before `install.sh` runs (radius bounds, preset rows), the duplicate has a
checker. See [CONSISTENCY.md](CONSISTENCY.md).

---

## 3. Glass modes

A mode is **not a new kind of setting**. It names a combination of flags
`install.sh` already has, and it owns a drawer that keeps that combination's own
tuning. `lib/steps-modes.sh` resolves a mode into flags and steps aside.

| Mode | `WANT_BLUR` | window / popup / notification blur | transparency seed | sheets |
|---|---|---|---|---|
| `frosted` (default) | 1 | on / on / on (each overridable) | the top-level memo, else **0**, so windows come out opaque (KI-18). The flagless resolver default is 0.90 | `shell-popup-blur`, `shell-notification-blur`, `gtk4-transparency` |
| `performance` | 0 | off / off / off | `1.00` (opaque) | `shell-80-solid` (opaque ladder); `gtk4-transparency` only if the level is below 1.00 |

- `VALID_GLASS_MODES="frosted performance"`. `resolve_glass_mode` takes
  `--glass-mode`, then infers it from typed flags (`--blur`/`--window-blur` →
  frosted, `--no-blur` → performance), then reads `$CONF_DIR/glass-mode`.
  Anything else, including the legacy names `solid` and `transparent`, leaves
  `GLASS_MODE` empty, and `remember_glass_mode` then records `frosted`.
- **Drawers** (`$CONF_DIR/modes/<mode>/`) hold `app-transparency`,
  `app-tint-color`, `shell-tint-color`, `app-blur-scope`, `popup-blur`,
  `notification-blur`, `blur-strength`, `popup-brightness`, `window-brightness`
  and `notification-opacity`.
  - `seed_glass_mode` creates a drawer on first entry. Frosted seeds from the
    top-level memos; performance seeds opaque black.
  - `load_glass_mode_memos` copies the drawer into this run's variables where no
    flag was given.
  - `save_glass_mode_memos` writes this run's answers back. It's called from
    `remember_glass_mode`, which runs at the end of full runs and full retunes
    **but not on the narrow `--incremental` path** (see
    [KNOWN-ISSUES.md](KNOWN-ISSUES.md) KI-01).
- `--no-blur` **is** performance mode now. It also loads `dconf/solid.ini` on
  top of `core.ini`, but only when the preset itself is (re)loaded (§7).

### Legacy: `solid` and `transparent`

Older versions had more modes. `solid` stood the whole theme down: it wrote
`$CONF_DIR/styling-off`, reset gtk-theme and the shell theme, moved the four
targets aside, and disabled the project's extensions (recorded in
`modes/solid/disabled-extensions`). `transparent` was folded into frosted.
Both were removed (KI-15). What's left is a one-time migration,
`migrate_solid_era` (`lib/steps-migrate.sh`), run right after
`migrate_legacy_names` on every real run: a `solid` memo becomes `performance`
and `transparent` becomes `frosted`, `backups/*.stood-down` targets come back,
the recorded extensions are re-enabled, and the marker and both drawers go.
`check-migration.sh` case 8 covers it.

---

## 4. Adaptive performance (an overlay, not a mode)

```
top-bar menu (Aura Glass Helper)          aura-glass-adaptive.service (user)
  Auto / Full Glass / Performance             loop every 2 s (AURA_GLASS_ADAPTIVE_INTERVAL)
        │ aura-glass-adaptive profile X           │ battery? GPU ≥80% ×3 (clears <65%)? listed game fullscreen+focused?
        ▼                                         ▼
  $CONF_DIR/adaptive-profile  ◀── tools/aura_glass_adaptive.py (AdaptiveReducer: hysteresis, debounce)
                                          │ on a state change only
                                          ▼
   aura-glass-operation run -- install.sh --settings-only --incremental --adaptive-blur active|restore --yes
                                          ▼
                    apply_adaptive_blur (lib/steps-dconf.sh)
```

- **active.** `install.sh` resolves the run as a retune to Performance (same
  `WANT_*`, the performance drawer's tints and level), so it leaves the same
  sheets and keys as the Glass mode switch: it saves the keys a mode owns
  (`dconf/solid.ini`'s set, including `hacks-level` and the OSD alpha) to
  `adaptive-performance/saved-mode-keys`, then runs `load_dconf` and
  `install_css`. It turns pipelines off *without* disabling the extension,
  because disabling BMS on GNOME 51 segfaults Mutter. `install_css` re-splices
  with `aura-glass-apply --reload-gtk`, which also reloads the shell theme so
  the sheet takes effect.
- **restore.** Writes the saved keys back, then runs the same two steps for the
  remembered mode (resolved from its drawer, so tints, level, popup and
  notification sheets and the radius preset come back as an ordinary Frosted
  install leaves them).
- It's transient: `remembering()` is false, so no top-level memo or drawer
  changes. State lives in `adaptive-performance/{active,reason}`.
- The service is enabled only while `WANT_BLUR=1`, i.e. in Frosted. In
  Performance it's disabled and `reason` is set to `no-blur`. The top-bar menu
  still works in Performance and calls the worker directly (KI-02).

---

## 5. The CSS pipeline

### Cascade by filename

`css/` holds numbered sheets. **The numeric prefix is the cascade order.** Later
sheets are meant to win at equal specificity.

```
shell:  00-flat → 10-quick-settings → 20-popup-menus → 30-notifications → 40-quick-toggles
        → 50-dialogs → 80-solid* → 90-density (generated) → popup-blur* → notification-blur*
gtk4:   00-flat → 10-fields → 20-buttons → 30-dropdowns → 40-containers → 50-window-controls
        → 60-controls → 70-surfaces → transparency* → window-controls-{adwaita|material|flat}*
gtk3:   gtk3-tweaks → gtk3-window-controls-{adwaita|material|flat}*
                                                         (* optional: installed or deleted by a flag)
```

Three places decide a sheet's fate, and only one is a glob. That's why
`tools/check-cascade.sh` exists:

| Place | Role |
|---|---|
| `install_css` (`lib/steps-css.sh`) | Copies `css/` into `$CONF_DIR` (glob for numbered sheets, explicit branches for optional ones). |
| `SHELL_SNIPPETS` / `GTK4_SNIPPETS` (`bin/aura-glass-apply`) | The ordered concatenation list. |
| `tools/preview-session.sh` | The headless preview harness's copy. |

An optional sheet is **installed or deleted**, never switched on at read time.
`aura-glass-apply` concatenates whatever it finds and can't know your flags.

### Rewriting installed copies (never `css/`)

`install_css` copies fresh sheets every run, then rewrites the copies. `css/`
stays at the shipped `default` state so `check-tokens.sh` has one baseline.

| Step (`lib/steps-css.sh` unless noted) | Runtime helper | Owns |
|---|---|---|
| `install_transparency_css` | `tools/rescale-transparency.py` | every alpha in `gtk4-transparency.css`, rescaled from `TOKEN_APP_TRANSPARENCY_SHIPPED` (0.92) |
| `apply_app_tint_color` | `tools/apply-tint-color.py` | the colour translucent GTK grounds mix toward |
| `apply_shell_tint_color` | `tools/apply-shell-tint.py` | the hue of shell surfaces (lightness kept) |
| `apply_popup_transparency` | inline Python | popup and solid-sheet alphas scaled by the window level |
| `apply_notification_opacity` | `tools/apply-notification-opacity.py` | the alpha of the notification ground ladder |
| `apply_radius_css` | `tools/apply-radius-preset.py` (+ `tools/token_manifest.py`) | the eight radii across every installed sheet |
| `apply_popup_brightness` (`lib/steps-dconf.sh`) | `tools/apply-popup-brightness.py` | both places Blur My Shell keeps a popup brightness |

The tint rewriters own a literal's colour channels and the opacity rewriters own
its alpha, so they're order-independent. `shell-90-density.css` is generated per
display by `measure_logical_ppi` and `density_css`.

### Splicing: `bin/aura-glass-apply`

- Four targets: the theme's `gnome-shell.css` and GTK4 `gtk.css`/`gtk-dark.css`
  are *flattened*; GTK3's `gtk.css` (the user's own file) is not. Each gets
  exactly one `/* >>> aura-glass BEGIN <<< */ … END` block. Legacy
  `tahoe-glass`/`tahoe-tweaks` blocks are stripped.
- **Flattening** rewrites the theme's own `box-shadow`, gradient and
  `text-shadow` values to `none` *where they're declared*, rather than fighting
  `!important` rules from outside.
- **Accent substitution** rewrites the theme's hard-coded blues to
  `-st-accent-color` in the shell and `@accent_bg_color` in GTK4, so GNOME's
  accent recolours everything live.
- **Publishing** goes through a temp file and `os.replace`, and identical output
  isn't rewritten (quiet apply). The shell reload (toggling User Themes) happens
  only when the shell CSS changed. `--force-reload` forces it,
  `--no-shell-reload` suppresses it, and `--json` prints a machine-readable
  result.

---

## 6. Tokens and radius presets

`tokens/tokens.sh` is **sourced, not templated**. GTK4 `var()` fails at
computed-value time, St has no custom properties, and GTK3 predates them, so a
shared number has to be written literally in each file. The duplication is made
**checked** instead:

- each token's comment names every consumer,
- `tools/token_manifest.py` is that list in machine-readable form (and the
  radius writer uses it too),
- `tools/check-tokens.sh` fails, naming the exact file and line.

The tokens are eight radii (`TOKEN_RADIUS_{WINDOW,MENU,QUICK_SETTINGS,NOTIFICATION,DIALOG,POPUP,OSD,BUTTON}`),
six Blur My Shell sigmas and two transparency values. Radius presets are
`flat sharp adwaita soft medium default rounded` plus `custom` (eight values,
bounded per surface by `radius_bounds`). `pill` is a retired name that
`radius_preset_canonical` maps to `rounded`.

**Project rule:** a painted radius must equal the blur radius behind it, so
`apply_radius_css` (paint) and `apply_radius_dconf` + `apply_pipeline_radius`
(blur) always move together.

---

## 7. dconf and gsettings

`load_dconf` (`lib/steps-dconf.sh`):

1. Loads `dconf/core.ini` into `/org/gnome/shell/extensions/`. Then
   `dconf/solid.ini` on top when `WANT_BLUR=0`, and `dconf/extras.ini` when
   extras are wanted.
   **On an existing install the preset is not reloaded.** If a `repo-path` or
   `accent` memo exists and Blur My Shell already has `pipelines`, it skips the
   load to preserve the user's extension settings, unless `--force` is given.
   That's why a mode switch on an existing install never reloads `solid.ini`
   (KI-03).
2. Then always overlays the resolved flags: `apply_grain`, `apply_blur_strength`,
   `apply_popup_brightness`, `apply_window_brightness`, `apply_popup_blur`,
   `apply_notification_blur`, `apply_app_blur`, `apply_app_opacity`,
   `apply_radius_dconf` (+ `apply_pipeline_radius`), `sync_osd_profile` and
   `refresh_bms_after_dconf`. The last one is skipped on GNOME ≥ 51, where
   toggling BMS crashes Mutter.

`apply_gsettings` writes `color-scheme=prefer-dark`, the accent,
gtk-theme/shell theme, icon theme, cursor theme/size, window buttons and font.
It also sets `org.gnome.shell disable-extension-version-validation=true`.

`app_blur_literal` is the one place arbitrary user text (per-app wm_class
patterns) reaches dconf. `check-app-blur-lists.sh` round-trips it through
GLib's parser.

---

## 8. Extensions

Catalogued in `lib/steps.sh`:

| Tier | Contents |
|---|---|
| core | `user-theme@…` (from EGO), plus `blur-my-shell@aunetx` and `custom-osd@neuromorph` built from pinned commits, plus the first-party `aura-glass-blur@aura-glass.local` |
| `EXT_EXTRA_RECOMMENDED` (7) | AppIndicator, Tiling Assistant, Quick Settings Audio Panel, Hot Edge, Kiwi Menu, Copyous, Wiggly |
| `EXT_EXTRA_ALL` (9) | the seven plus Vitals and Restart To |
| `EXT_EXTRA_ADDED_LATER` | recommended extensions a remembered pack never offered; added to it on an update (`extension-catalog`) |
| `EXT_NO_AUTO_ENABLE` | empty right now |

- Upstreams are **pinned by commit** (table in §12). A theme that changes under
  the CSS gives a half-applied look with no error.
- Blur My Shell patches, applied in order: `blur-my-shell-overview.patch`,
  `blur-my-shell-subwindows.patch`, `blur-my-shell-notifications.patch` (adds the
  separate `popup/notification` key), `blur-my-shell-static-maximized.patch`
  (static blur for full-screen windows, dynamic for smaller ones),
  `blur-my-shell-panel-refit.patch` (top-bar blur refitted in place after a
  monitor change, no flash). Custom OSD gets
  `custom-osd-gnome50.patch`. Copyous gets `copyous-gnome51.patch`.
- `bin/aura-glass-ext` exposes the catalogue one UUID at a time
  (`list | install | remove | enable | disable | recommended | full`). The
  settings window's Extensions page is built from `aura-glass-ext list`.

### The first-party extension: `extensions/aura-glass-blur@aura-glass.local`

"Aura Glass Helper" for shell versions 48–51:

1. **Blur This App** in the window menu. It runs
   `aura-glass-operation app-blur --wm-class X --enabled 0|1`, which goes
   through the writer lock to `aura-glass-preview app-blur` and
   `apply_app_blur`, so the memo and dconf change together.
2. A **D-Bus bridge**, `io.github.DevWebeloper.AuraGlass` at
   `/io/github/DevWebeloper/AuraGlass`. Methods are `ListWindows`,
   `GetFocusState`, `GetFullscreen`, `SetWindowOpacity`, `RefreshOpacity` and
   `InspectOverviewState`; signals are `WindowsChanged` and `FocusChanged`.
   Unprivileged GTK apps on Wayland have no other way to see the window list
   and the fullscreen state. Both the settings app and the adaptive worker use
   it.
3. The **adaptive profile menu** (Auto / Full Glass / Performance), which calls
   `aura-glass-adaptive profile <p>`.

---

## 9. User services (`systemd/`, installed to `~/.config/systemd/user/`)

| Unit | Runs | Why |
|---|---|---|
| `aura-glass-icon-sync.service` | `aura-glass-icon-sync` | Icon packs ship `-Light`/`-Dark` variants and GNOME's key holds one name. This follows the light/dark preference. |
| `aura-glass-panel-blur.service` | `aura-glass-panel-blur` → `aura_glass_panel_blur.py` | Rebuilds BMS panel blur after monitor layout changes. Default on for multi-monitor setups and laptops. |
| `aura-glass-gdm-sync.service` | `aura-glass-gdm-sync` | Pushes the wallpaper and primary monitor to GDM, and warns at login when a package update has replaced the themed gresource (KI-30). Present only if GDM was themed or synced. |
| `aura-glass-update-check.{service,timer}` | `aura-glass-update-check --notify` | Runs `git ls-remote` daily. Notifies once per release and never installs. |
| `aura-glass-adaptive.service` | `aura-glass-adaptive` → `aura_glass_adaptive.py` | Adaptive performance (§4). Enabled in Frosted only. |

`install_if_changed` makes these quiet: an unchanged unit or binary isn't
rewritten, and services aren't restarted.

---

## 10. Concurrency: one writer at a time

`bin/aura-glass-operation` → `tools/aura_glass_operation.py` takes an exclusive
`flock` on `~/.cache/aura-glass/operation.lock`. It waits up to 30 s
(`AURA_GLASS_OPERATION_TIMEOUT`), then runs the command with the descriptor
inherited (`AURA_GLASS_OPERATION_FD`), so nested writers see `held` and don't
deadlock.

- `install.sh` and `uninstall.sh` re-exec themselves under it, except for
  `--help` and `--dry-run`.
- `aura-glass-apply` re-execs under it.
- The adaptive worker and the window menu go through it.
- The live preview runs its operations under it, and `aura-glass-preview commit
  --session S -- install.sh …` makes Apply the step that ends a preview, or
  reverts on failure.

A full install holds the lock for minutes. A GUI Apply started during it fails
after 30 s instead of interleaving.

---

## 11. The GUI layer (summary; detail in [GUI.md](GUI.md))

- `gui/aura_glass_setup_wizard.py` runs **before** install. Its stdout is the
  flag list, one token per line. Exit 0 means answered, 2 means cancelled, and
  anything else falls back to the text wizard in `install.sh`.
- `gui/aura_glass_settings.py` runs **after** install and finds the checkout via
  `$CONF_DIR/repo-path`. Apply is
  `install.sh --settings-only --incremental --yes <changed flags>`, wrapped in
  `aura-glass-preview commit` when a preview is active.
- **Live preview** is `bin/aura-glass-preview` (`begin`/`set`/`apps`/`revert`/`status`/`commit`).
  It snapshots sheets, the BMS dconf subtree and memos, then calls the same
  `apply_*` with `PREVIEW_MODE=1`. Its hard rule is that **a preview never
  leaves a memo different from what it found.**

---

## 12. Pinned upstreams (`lib/steps.sh`)

| What | Repo | Pin |
|---|---|---|
| Base theme | kayozxo/GNOME-macOS-Tahoe | `6dfcd9d941e5` (installed as `Tahoe-Dark`, adopted as `Aura-Glass`) |
| Blur My Shell | aunetx/blur-my-shell | `425761d55049` (v73) + 3 patches |
| Custom OSD | neuromorph/custom-osd | `334ac17e9348` + GNOME 50/51 patch |
| gnome-rounded-blur | kancko/gnome-rounded-blur | `a4db9e5947b1` (v1.0.2) + `patches/gnome-rounded-blur-offstage.patch` |
| Colloid / Reversal / MacTahoe icons | vinceliuice, yeyushengfan258, vinceliuice | `c9e702beb96f` / `2c8122287e3b` / `b85923bb87f5` |
| Hatter icons | Mibea/Hatter | full SHA, shallow sparse fetch |
| AOSP cursors | Tech-Tac/aosp-cursors | release 1.3.1 + sha256 |
| Moga cursors | gnome-look.org/p/2302110 | release metadata resolved by `tools/moga_cursor.py` |
| Fonts | Inter 4.1 (sha256), MiSans (sha256 as notice; URLs unversioned), SF Pro mirror `8bfea09aa6f1` | |

`gnome-rounded-blur` is built from the pin plus its patch and installed
system-wide, where the shell finds it: on Arch as a `makepkg` package
(`1.0.2-1.1`, one pkgrel above the AUR's) through `sudo pacman -U`, elsewhere
with `meson … && sudo meson install`. Not through an AUR helper, which cannot
apply a patch. The `rounded-blur-patch` stamp makes an unpatched install (the
AUR package, or one from before the patch) rebuild once. Its build
dependencies (compiler, meson, pkg-config, gobject-introspection, mutter's
development files; Debian's `libmutter-N-dev` by API number) are offered by
`ensure_rounded_blur_build_deps` in `lib/distro.sh`. There is no
rootless build. One in `~/.local` never loads, because the shell searches
neither `~/.local/lib` nor `~/.local/share/girepository-1.0` (KI-12), so an old
one is removed.

---

## 13. Naming and migration

The project was renamed from `tahoe-glass`. `lib/steps-migrate.sh` moves an old
`$CONF_DIR` (merging `backups/` carefully, since a wrong merge turns a clean
uninstall into a themed one) and adopts the theme directory. `aura-glass-apply`
and `uninstall.sh` still read both names. The theme is resolved **from disk**,
not from dconf, so fixtures with an overridden `HOME` never touch the real
user's database. The upstream installer writes `~/.themes/Tahoe-Dark` from a
string literal, so the theme is adopted after it runs (`adopt_theme_dir`).
