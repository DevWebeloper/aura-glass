# Architecture

How aura-glass turns a command line into a themed desktop, and why it is built
the way it is.

---

## 1. The shape of the thing

There is no compiler and no package. The whole system is:

```
  flags / wizard answers
          │
          ▼
  install.sh ── resolves every setting once ──┐
          │                                   │
          ├── fetch pinned upstreams          │  memos in ~/.config/aura-glass
          ├── copy css/ into $CONF_DIR        │  so the next flagless run
          ├── rewrite the copies (tint,       │  resolves to the same answers
          │   opacity, radii) in place        │
          ├── splice them into 4 generated ───┘
          │   CSS files via aura-glass-apply
          ├── load dconf/*.ini
          ├── apply_* dconf keys per flag
          └── gsettings for accent/theme/icons/cursor/font
```

Three properties fall out of that and everything else defends them:

1. **Reversible.** The installer only ever *appends inside a marked block* to a
   generated file, and takes a first-run copy (`backup_once`) of anything it
   overwrites. `uninstall.sh` puts back the copy or strips the block.
2. **Rootless.** Everything is under `$HOME`. The three exceptions
   (dependencies, `gnome-rounded-blur`, GDM) are opt-in and clearly announced.
3. **Idempotent.** Re-running replaces a block rather than stacking one, and
   `--dry-run` proves what a run would do without doing it.

---

## 2. Precedence: how a setting gets its value

This is the single most important mechanism in the project.

```
  a flag typed on the command line          (highest)
    ↓
  --glass-mode, for the sub-flags a mode owns
    ↓
  the current mode's drawer:  $CONF_DIR/modes/<mode>/<key>
    ↓
  the shared memo:            $CONF_DIR/<key>
    ↓
  the shipped default         (lowest)
```

Implemented in exactly two places, both in `install.sh`'s flow:

- the **resolution block** in `install.sh` (roughly the second half of the
  file), which reads memos into shell variables, validates them, and dies on a
  bad value *before* anything has been written; and
- the `apply_*` functions in [`lib/steps-dconf.sh`](../lib/steps-dconf.sh) and
  [`lib/steps-css.sh`](../lib/steps-css.sh), each of which writes its memo back
  as its last step.

Every flag has a twin `*_EXPLICIT` variable set by the parser. `_EXPLICIT` means
"the user typed this, do not overrule it". `lib/steps-modes.sh` reuses the same
marker to mean "settled for this run" once a mode's drawer has supplied a value,
so a later reader does not fall back past it.

Memo writes are guarded by `remembering()` in `lib/common.sh`, which is false
under `--dry-run` and under `PREVIEW_MODE=1`. That is what lets
`bin/aura-glass-preview` call the real `apply_*` functions on every slider tick
without ever changing what the next real run resolves to.

### Why the GUI does not resolve anything

`gui/aura_glass_settings.py` sends only the flags that **changed** and lets the
installer resolve the rest:

```
install.sh --settings-only --yes <only the flags that changed>
```

A window with its own copy of the precedence chain would drift from the
installer within one release. The two places the window *must* duplicate
knowledge — the radius preset rows and the per-surface bounds, because spin rows
need their ranges before `install.sh` runs — are covered by
`tools/check-gui-radius.py`.

---

## 3. The CSS pipeline

### Cascade by filename

`css/` holds numbered sheets. **The numeric prefix is the cascade order**, not
decoration: several sheets are meant to beat the one before them on equal
specificity (the dropdown radius over the button radius, the accent slider fill
over the white one, the second `.quick-settings .icon-button` block over the
first).

```
shell-00-flat        shell-10-quick-settings   shell-20-popup-menus
shell-30-notifications  shell-40-quick-toggles  shell-50-dialogs
shell-80-solid       (only when --no-blur)
shell-90-density     (generated per display, see below)
shell-popup-blur     shell-notification-blur   (optional, by flag)

gtk4-00-flat  gtk4-10-fields  gtk4-20-buttons  gtk4-30-dropdowns
gtk4-40-containers  gtk4-50-window-controls  gtk4-60-controls
gtk4-70-surfaces    gtk4-transparency
gtk4-window-controls-{adwaita,material,flat}   (one, by --titlebar-button-style)

gtk3-tweaks   gtk3-window-controls-{adwaita,material,flat}
```

Three places decide a sheet's fate and only one of them is a glob, which is why
`tools/check-cascade.sh` exists:

| Place | Role |
|---|---|
| `install_css` (`lib/steps-css.sh`) | copies `css/` into `$CONF_DIR`; optional sheets get an explicit install-or-remove branch |
| `SHELL_SNIPPETS` / `GTK4_SNIPPETS` (`bin/aura-glass-apply`) | the ordered concatenation list |
| `tools/preview-session.sh` | the preview harness's own copy of the same set |

An optional sheet is **installed or deleted** by `install_css`, never switched
on at read time — `aura-glass-apply` concatenates whatever it finds and has no
way to know which flags this install was given.

### Rewriting the installed copies

Four rewriters edit the copies in `$CONF_DIR`, never `css/` in the repo. The
repository stays at the shipped `default` state so `check-tokens.sh` always has
one known baseline to check.

| Rewriter | Owns |
|---|---|
| `tools/rescale-transparency.py` | every alpha in `gtk4-transparency.css`, rescaled relative to `TOKEN_APP_TRANSPARENCY_SHIPPED` |
| `tools/apply-tint-color.py` | the colour translucent GTK grounds are mixed toward |
| `tools/apply-shell-tint.py` | the hue of the shell's dark surfaces, keeping each one's lightness |
| `tools/apply-notification-opacity.py` | the alpha of the notification ground ladder (rest / hover / pressed) |
| `tools/apply-radius-preset.py` | the eight radii across every installed sheet |

The tint rewriter owns a literal's *colour channels* and the opacity rewriter
owns its *alpha*, so the two are order-independent and neither undoes the other.

`shell-90-density.css` is generated, not shipped: `measure_logical_ppi` +
`density_css` scale panel icon sizes for whatever screen the installer actually
ran on. It gets prefix 90 so it lands after every hand-written shell sheet, and
its own file so a re-run cannot silently double an appended block.

### Splicing: `bin/aura-glass-apply`

Four targets, all generated by upstream installers:

```
~/.themes/<THEME>/gnome-shell/gnome-shell.css   flattened
~/.config/gtk-4.0/gtk.css                        flattened
~/.config/gtk-4.0/gtk-dark.css                   flattened
~/.config/gtk-3.0/gtk.css                        not flattened (user's own file)
```

Each gets exactly one block:

```
/* >>> aura-glass BEGIN <<< */ … /* >>> aura-glass END <<< */
```

Re-running strips the old block first, so blocks never stack. Legacy marker
names (`tahoe-glass`, `tahoe-tweaks`) are stripped too.

**Flattening** rewrites the theme's own `box-shadow`, `background-image:
…-gradient(…)` and text-shadow values to `none` *where they are declared*,
rather than trying to out-rank them. The earlier approach appended counter-rules
and had to win a cascade fight against a sheet marking 37 of its own shadows
`!important` — unwinnable with a blanket reset, because between two `!important`
declarations specificity still decides. Setting the value at its declaration
leaves no rule to lose to. A gradient is replaced by the mean of its colour
stops; a stop the parser cannot read aborts that replacement rather than
inventing a colour.

**Accent substitution** rewrites the theme's hard-coded blues
(`#0091ff #3584e4 #3484e2 #1c6bc7 #619fe8`) to `-st-accent-color` on the shell
side and `@accent_bg_color` on the GTK4 side, per line, so GNOME's own accent
machinery drives the whole desktop live. One `@define-color` is skipped: the one
defining the very name being substituted in, which would otherwise become a
definition naming itself.

Finally the User Themes key is toggled off and back on, because that extension
reloads on a settings change rather than a file change.

---

## 4. Tokens

[`tokens/tokens.sh`](../tokens/tokens.sh) is sourced, not templated. GTK4's
`var()` fails at computed-value time rather than parse time, St has no custom
properties at all, and GTK3's engine predates them — there is no cross-toolkit
way to express a shared number as a variable. Generating the CSS from templates
was considered and rejected, because the per-value comments explaining *why* a
number is that number are the most valuable content in the repo and templating
would strip them from the files people read.

So values stay literal in the files that use them, and the duplication is made
**checked** instead of trusted:

- each token's comment lists every consumer file and selector/key;
- `tools/token_manifest.py` is that pairing list in machine-readable form;
- `tools/check-tokens.sh` fails naming the exact file and line that disagrees.

Tokens held: eight radii (`TOKEN_RADIUS_*`), six Blur My Shell sigmas
(`TOKEN_SIGMA_*`), and two transparency values
(`TOKEN_APP_TRANSPARENCY_SHIPPED`, `TOKEN_APP_TINT`).

Deliberately *not* tokens: the accent colour (already live-plumbed through
GNOME's own machinery) and any value with a single consumer (a token there
cannot catch drift and only adds a place to forget).

### Radius presets

Seven curated rows — `flat sharp adwaita soft medium default rounded` — plus
`custom`. Curated rather than a multiplier, because the eight numbers are not
proportional to each other: Quick Settings is *larger* than a menu (Blur My
Shell groups the date menu with it), and the OSD ceiling is set by the height of
the box being blurred rather than by the shape drawn inside it. Past half that
height the four corner arcs overlap and the pill becomes an ellipse.

The project rule, stated in the sheets themselves: **a painted radius must equal
the blur radius behind it.** Blur My Shell rounds the blur actor; the CSS rounds
the surface on top. Disagreement leaves a sliver of the larger shape showing,
which reads as a rendering fault. This is why `apply_radius_css` and
`apply_radius_dconf` always move together.

`radius_preset_canonical()` is the one place a retired name maps to its
replacement (`pill` → `rounded`), and it is what the memo is written at, so no
downstream reader has to know a name that no longer names a row.

---

## 5. The three glass modes

A mode is **not a fourth kind of setting**. It is a name for a combination of
flags `install.sh` already had, plus a drawer to keep that combination's own
tuning in. `lib/steps-modes.sh` resolves a mode into those flags and then gets
out of the way — nothing downstream knows a mode exists.

| Mode | Window blur | Popup blur | Window transparency | Styling |
|---|---|---|---|---|
| `frosted` (default) | on | on | as tuned | on |
| `transparent` | off | on | on, seeded at 0.82 | on |
| `solid` | — | — | — | **off** |

- `frosted` is the full look.
- `transparent` shows the wallpaper straight through the window. Because there
  is no blurred layer under the text it seeds *darker* (0.82) rather than
  inheriting frosted's level. Tint colours *are* inherited — a colour preference
  travels with the user; an opacity level is coupled to whether there is blur
  behind the glass, which is exactly what changes between modes.
- `solid` stands the theme down: stylesheets come back out, shell and GTK themes
  return to GNOME's stock ones, and this project's extensions are switched off
  **with their own settings intact**. Icons, cursors and accent stay — those are
  the user's preferences, not this theme's styling. Nothing is uninstalled.

Because `solid` removes the styling itself, it *refuses* flags that would have
nothing to act on (`--blur`, `--popup-blur`, `--notification-blur`,
`--window-blur`, a non-zero `--app-transparency`) rather than discarding them
silently.

**Per-mode drawers** live at `$CONF_DIR/modes/<mode>/<key>`, holding
`app-transparency`, `app-tint-color`, `shell-tint-color`, `blur-strength`,
`popup-brightness`, `notification-opacity`, `popup-blur`, `notification-blur`
and (frosted only) `app-blur-scope`. `seed_glass_mode` creates a drawer on first
entry, `load_glass_mode_memos` reads it into this run's variables where no flag
was given, `save_glass_mode_memos` writes this run's answers back.

Two markers record state: `$CONF_DIR/glass-mode` (the remembered name) and
`$CONF_DIR/styling-off` (the honest, on-disk fact that the theme is down —
it outranks a memo that a hand-edited install could have left disagreeing).

`--no-blur` is **not** `solid`. `--no-blur` is an opaque but fully themed
desktop: every radius, spacing, accent, monochrome control and capsule slider
survives, and only Blur My Shell's shaders go. `dconf/solid.ini` is what it
loads on top of `core.ini`. `solid` is a desktop with the theme taken off it.

Design table and rationale: [superpowers/specs/2026-08-18-glass-modes-design.md](superpowers/specs/2026-08-18-glass-modes-design.md).

---

## 6. Extensions

Three tiers, all catalogued in `lib/steps.sh`:

- **core** — `user-theme@…` from the extensions site, plus two built from a
  pinned commit: `blur-my-shell@aunetx`,
  `custom-osd@neuromorph`.
- **recommended** (`EXT_EXTRA_RECOMMENDED`) — six.
- **full** (`EXT_EXTRA_ALL`) — fourteen.
- `EXT_NO_AUTO_ENABLE` — catalogued and installable but never switched on by a
  pack (currently `auto-accent-colour@Wartybix`, which would overwrite the
  accent the wizard just asked for).

Upstreams are **pinned by commit**. Both Blur My Shell and the base theme move
regularly, and a theme that changes under the CSS tweaks is exactly how you get
a half-applied look with no error message.

Three patches are applied on top of the Blur My Shell pin, in order:

| Patch | Why |
|---|---|
| `blur-my-shell-overview.patch` | `blur-on-overview: false` upstream only stops forcing window actors visible; it does not remove blur from overview previews |
| `blur-my-shell-subwindows.patch` | upstream's `check_blur` matched one frame-type set excluding `ATTACHED` and `UTILITY`, leaving a blurred app's dialogs and tool palettes unblurred |
| `blur-my-shell-notifications.patch` | splits notification banners and history cards onto their own `notification` key, gated independently of menus and dialogs |

`patches/custom-osd-gnome50.patch` carries
Custom OSD to GNOME 50 and 51.

`bin/aura-glass-ext` is the catalogue reachable one UUID at a time
(`list | install | remove | enable | disable | recommended | full`). The settings
window builds its Extensions page from `aura-glass-ext list` rather than keeping
a second Python copy of the arrays — `tools/check-ext-catalogue.sh` asserts the
command describes everything the install path can reach.

### The first-party extension

`extensions/aura-glass-blur@aura-glass.local` does three things:

1. Adds **Blur This App** to the window right-click menu, by monkeypatching
   `WindowMenu._buildMenu`. It reads and writes Blur My Shell's own
   `applications` keys (`blur`, `enable-all`, `whitelist`, `blacklist`) and
   **mirrors the change into the same `$CONF_DIR` memos** `install.sh` reads
   back — without that mirror a toggle would hold only until the next install.
   It adds nothing at all when Blur My Shell's schema is absent or its per-app
   blur is off.
2. Exports `io.github.DevWebeloper.AuraGlass` on D-Bus (`ListWindows`,
   `WindowsChanged`, `GetFocusState`, `GetFullscreen`, `FocusChanged`),
   which is the only way an unprivileged GTK app on Wayland can know what windows
   exist and whether the active window is fullscreen — used by the settings
   window's "Open now" list and the adaptive service.
3. Provides the **Adaptive Performance Mode** top-bar quick profile menu
   (**Auto**, **Full Glass**, **Performance**). It updates its status icon and
   reason live, invokes `aura-glass-adaptive profile` asynchronously, and stays
   active even across Solid mode so users can restore glass anytime from the panel.

### The adaptive performance service

`bin/aura-glass-adaptive` and `systemd/aura-glass-adaptive.service` provide
dynamic performance management:

- Persists selected profile in `$CONF_DIR/adaptive-profile` (`auto` by default).
- Persists selected fullscreen games in `$CONF_DIR/adaptive-fullscreen-apps`.
- In `auto` profile, triggers Performance mode on battery discharge (`Discharging`),
  sustained GPU load (≥80% for three 2-second samples, clearing below 65%), or
  when a configured game is focused and fullscreen.
- Transient transitions run `install.sh --settings-only --incremental --adaptive-blur active|restore`
  under the writer operation lock, ensuring all blur surfaces (app windows, popups,
  notifications, CSS) transition cleanly while leaving normal saved memos completely
  immutable.

---

## 7. dconf and gsettings

`dconf/core.ini` is **core extension settings** as one preset:
Blur My Shell pipelines and sigmas, custom-osd,
and the rest. `dconf/extras.ini` covers the optional extensions.
`dconf/solid.ini` is loaded on top of core by `--no-blur`.

`load_dconf` loads the preset; the `apply_*` functions in `lib/steps-dconf.sh`
then overwrite individual keys from this run's resolved flags:

```
apply_radius_dconf        eight radii into Blur My Shell's corner-radius keys
apply_pipeline_radius     the blur pipelines' own rounding
apply_app_opacity         window opacity + the Blur My Shell applications sigma
apply_app_blur            whitelist/blacklist/enable-all, built by app_blur_literal
apply_popup_blur          the popup component, static vs dynamic
apply_notification_blur   the split-out notification key from the patch
apply_popup_brightness    both places Blur My Shell keeps a brightness
apply_blur_strength       scales every sigma together, 25–200%
apply_grain               noise overlay
apply_window_buttons      org.gnome.desktop.wm.preferences button-layout
apply_cursor_size         org.gnome.desktop.interface cursor-size
apply_font                interface / document / titlebar font at existing sizes
apply_gsettings           color-scheme, accent-color, gtk-theme, icon-theme, cursor-theme
sync_osd_profile          keeps custom-osd in step with the rest
```

`app_blur_literal` is the one place arbitrary user text reaches dconf — the
per-app patterns someone typed into the settings window. It builds a GVariant
array literal, and `tools/check-app-blur-lists.sh` round-trips the result
through GLib's own parser without touching live dconf.

**Solid mode never calls `load_dconf`.** Loading `core.ini` is exactly the
"modifying the extension" that standing down is supposed to avoid; the
extensions are disabled with their settings untouched, ready for the way back.
The list of what was disabled is recorded at
`$CONF_DIR/modes/solid/disabled-extensions`.

---

## 8. Systemd user units

| Unit | Why |
|---|---|
| `aura-glass-icon-sync.service` | GNOME's `icon-theme` key holds one name with no light/dark notion; Colloid ships `-Light`/`-Dark` per accent. This follows the system preference. |
| `aura-glass-panel-blur.service` | Blur My Shell clips its panel background actor to panel geometry, which is not settled at login and is in flux on every monitor change. Rebuilds the blur once the desktop settles. Enabled by default only on multi-monitor machines. |
| `aura-glass-gdm-sync.service` | Pushes the desktop wallpaper and primary monitor to the login screen. |
| `aura-glass-update-check.{service,timer}` | One `git ls-remote` a day. Notifies once **per release**, not once per day. Never installs anything — that is a button in the window. |

---

## 9. The GUI layer

Two separate windows, both optional, both pure front ends for flags.

**`gui/aura_glass_setup_wizard.py`** runs *before* anything is installed.
Contract: stdout is the flag list, one token per line, and nothing else may ever
be printed there (`lib/steps-wizard.sh` reads it); exit 0 answered, exit 2
cancelled (install stops, nothing changed), anything else falls back to the
terminal wizard. `install.sh` **blocks** on it. Every question here has a twin in
`install.sh`'s terminal wizard — parity is a stated rule, not enforced by code.

**`gui/aura_glass_settings.py`** runs after install and refuses to open without
`$CONF_DIR`. Pages: Glass (three mode tabs), Appearance, Corner rounding,
Per-app blur, Extensions, Packages, System, Updates, Uninstall.

Three kinds of thing deliberately do **not** ride on Apply:

- **extension switches** — instant, reversible, unprivileged, but not settings
  the installer resolves; they go through `bin/aura-glass-ext`;
- **the Packages page** — a filesystem delete for a pack under `$HOME`; for one
  under `/usr` it names the owning package and hands the command to a terminal,
  because deleting a package's files out from under it leaves its database
  describing files that are gone;
- **anything root** — dependencies, `gnome-rounded-blur`, GDM, monitor sync, the
  uninstall scopes. These **open a real terminal** rather than running `sudo`
  down a pipe nothing can type into.

**Live preview** is `bin/aura-glass-preview` (`begin` / `set` / `apps` /
`revert` / `status`). It snapshots the installed sheets, the Blur My Shell dconf
subtree and the affected memos, then calls the *same* `apply_*` functions with
`PREVIEW_MODE=1` so nothing is remembered. Its one hard safety property: a
preview must never leave a `$CONF_DIR` memo different from what it found.
`tools/check-preview.sh` asserts that.

More detail: [GUI.md](GUI.md).

---

## 10. Migration and naming

The project was renamed from `tahoe-glass`. `lib/steps-migrate.sh` moves a
pre-rename install onto the current names, and the delicate part is the
`backups/` merge — getting it wrong silently turns a clean uninstall into one
that leaves every GTK4 app themed. `tools/check-migration.sh` drives that
against fixture `HOME`s.

Both names are still honoured at read time in `bin/aura-glass-apply` and
`uninstall.sh`, and the theme directory is resolved from **disk** rather than
from the dconf key — an install that predates the rename is still wearing
`Tahoe-Dark`, and reading dconf would reach the real user's database even when
`HOME` is overridden by a test fixture.

The upstream theme's installer writes `~/.themes/Tahoe-Dark` from a string
literal with no flag to change it, so the theme is **adopted after they run**
(`adopt_theme_dir`) rather than installed under our name.
