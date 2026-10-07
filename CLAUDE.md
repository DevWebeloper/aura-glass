# CLAUDE.md — working on aura-glass

Instructions for an AI agent working in this repository. Read this before
touching anything. `README.md` is the *user* document; this is the contributor
one. Deeper detail lives in [docs/](docs/) — start at [docs/README.md](docs/README.md).

---

## What this project is

A GNOME desktop theme installed by a Bash script. There is no build system, no
package, no test runner in the usual sense. `./install.sh` fetches pinned
upstreams, copies stylesheets into `~/.config/aura-glass`, splices them into the
theme's generated CSS, loads a dconf preset, and writes gsettings. Everything
lands under `$HOME` except three optional root steps (dependencies, the
`gnome-rounded-blur` library, the GDM login screen).

Targets GNOME Shell 48 / 49 / 50 / 51, Wayland preferred. Arch/CachyOS, Fedora,
Ubuntu/Debian.

---

## The five rules that matter most

### 1. One place resolves a flag into a file

The precedence chain is **typed flag → `--glass-mode` → per-mode memo →
top-level `$CONF_DIR` memo → default**, and it is implemented exactly once, in
`install.sh`'s resolution block plus the `apply_*` functions in
[lib/steps-dconf.sh](lib/steps-dconf.sh) and [lib/steps-css.sh](lib/steps-css.sh).

The settings window, the setup wizard and `aura-glass-preview` all call *that*
code rather than reimplementing it. Never add a second copy of a resolution
rule. If a GUI needs to know a value before `install.sh` runs (radius bounds,
preset rows), the duplication gets a checker — see rule 3.

### 2. Never edit `~/.themes` or `~/.config/gtk-*` by hand

Those four files are generated. `bin/aura-glass-apply` owns a single marked
block in each:

```
/* >>> aura-glass BEGIN <<< */ … /* >>> aura-glass END <<< */
```

Edit `css/*.css` in the repo, then re-run the installer. Anything written
outside that block is lost on the next apply and breaks uninstall.

### 3. Duplicated numbers are *checked*, never trusted

Radii and blur sigmas appear literally in stylesheets, in `dconf/core.ini`, and
in `gui/aura_glass_settings.py`. GTK4/St/GTK3 have no shared variable mechanism,
so the duplication is unavoidable. [tokens/tokens.sh](tokens/tokens.sh) is the
single source of truth and `tools/check-tokens.sh` fails the commit when a copy
drifts. **Change a value in `tokens/tokens.sh`, then in every consumer its
comment names, then run the checker.**

### 4. Comments are the deliverable

Almost every non-obvious number in `css/`, `dconf/` and `lib/` carries a comment
saying *why it is that number* — usually the result of a bisection against a
screenshot. Those comments are the most valuable thing in the repository. Do not
strip them, do not shorten them, and when you change a value, update the reason
too. If you cannot say why a number is what it is, do not change it.

### 5. Apply theme edits to the live desktop

A repo edit is not a finished change. After editing `css/`, `dconf/` or
`tokens/`:

```bash
./install.sh --settings-only -y
```

That reapplies the dconf preset, the CSS and the gsettings without touching the
theme or extensions. No root, no network, a few seconds. GTK apps need a
restart to pick up the GTK side; the shell reloads itself.

---

## Repository map

| Path | What it is |
|---|---|
| `install.sh` | Entry point: flag parsing, precedence resolution, step orchestration |
| `uninstall.sh` | Restoration, in four scopes (base / `--extensions` / `--assets` / `--gdm`) |
| `lib/` | The steps, split by concern. Definitions only — nothing runs at source time |
| `tokens/tokens.sh` | Single source of truth for every value written down twice |
| `css/` | Stylesheets. Numeric prefix **is** the cascade order |
| `dconf/` | `core.ini` (every extension's settings), `extras.ini`, `solid.ini` |
| `patches/` | Pinned-upstream patches (GNOME 50 compat, Blur My Shell behaviour) |
| `bin/` | User-facing commands installed into `~/.local/bin` |
| `gui/` | GTK4/libadwaita settings window and setup wizard (optional) |
| `extensions/` | The one first-party GNOME extension (`aura-glass-blur@aura-glass.local`) |
| `systemd/` | Four user units: icon sync, panel blur fix, GDM sync, update check |
| `tools/` | Checkers, the headless preview harness, the git hooks |
| `docs/` | Contributor documentation (this file's long form) |

`lib/` breakdown:

```
steps.sh              upstream pins, paths, extension arrays, preflight, install_theme, finish
steps-migrate.sh      moving a pre-rename (tahoe-glass) install onto current names
steps-extensions.sh   EGO downloads, the three pinned builds, gnome-rounded-blur
steps-assets.sh       icon and cursor packs
steps-fonts.sh        --font: Inter, MiSans, SF Pro
steps-modes.sh        the three glass modes and their per-mode memo drawers
steps-css.sh          stylesheet install, tint/opacity/radius rewriters, density
steps-dconf.sh        the dconf preset and every apply_* that writes a key
steps-integration.sh  icon-sync agent, Flatpak override, panel blur unit
steps-gdm.sh          login screen theme and monitor sync
steps-gui.sh          settings window, update-check timer
steps-wizard.sh       runs the GTK setup wizard, reads its flags back
common.sh             output helpers, run/dry-run, backups, pinned fetchers
distro.sh             distro detection, dependency install, AUR helper bootstrap
```

---

## Before you commit

Enable the hooks once per clone:

```bash
tools/install-hooks.sh
```

The pre-commit hook checks the **staged tree** (not the working tree) and runs
shell + Python syntax plus fifteen project checkers. Run them by hand any time:

```bash
tools/check-tokens.sh          # every duplicated value still agrees
tools/check-cascade.sh         # every css/ sheet is installed, applied, previewed, in order
tools/check-radius-preset.sh   # a preset moves the radii and nothing else
tools/check-glass-modes.sh     # --glass-mode resolves to the documented flag table
tools/check-solid-extensions.sh
tools/check-styling-off.sh
tools/check-migration.sh
tools/check-ext-catalogue.sh
tools/check-app-blur-lists.sh
tools/check-update-check.sh
python3 tools/check-gui-flags.py       # window emits flags install.sh accepts
python3 tools/check-wizard-flags.py
python3 tools/check-gui-radius.py      # window's radius copy matches tokens.sh
python3 tools/check-terminal-spawn.py
python3 tools/check-update-channel.py
```

Full detail on what each one asserts: [docs/TESTING.md](docs/TESTING.md).

Visual work goes through the headless preview harness instead of a logout:

```bash
tools/preview.sh                       # screenshot the current tree
tools/preview.sh --solid               # the --no-blur look
python3 tools/check-shots.py --mode glass --accept   # adopt this run as baseline
```

---

## Conventions

**Commits.** Conventional-commit prefixes with a scope:
`feat(gui): …`, `fix(solid): …`, `docs: …`. Subject line is a sentence, lower
case, no trailing period. Do **not** add `Co-Authored-By` trailers, "Generated
with" footers, or any mention of an AI assistant to commits, tags or releases in
this repository.

**Branches and releases.** Feature branch → `git merge --no-ff` into `main` →
tag `vX.Y.Z` → `gh release create`. There is no VERSION file; the git tag *is*
the version, and `bin/aura-glass-update-check` reads it. See
[docs/RELEASING.md](docs/RELEASING.md).

**Scope.** Do what was asked. Do not add validation, checks, defensive branches
or "while I was here" refactors that were not requested. This codebase is
deliberate; unrequested additions cost more to review than they save.

**Bash.** `set -euo pipefail`. Every filesystem mutation goes through `run`, so
`--dry-run` stays honest. Every overwrite goes through `backup_once`, so
uninstall stays complete. Every memo write is guarded by `remembering`, so a dry
run and a live preview leave nothing behind.

**Python.** Standard library plus PyGObject only. The GUI may not import
anything `lib/distro.sh` does not probe for. `gui/` never writes theme files —
it composes a command line and runs `install.sh --settings-only`.

---

## Common tasks

### Add a new flag

1. Declare its variable and `_EXPLICIT` twin at the top of `install.sh`.
2. Parse it in the `case` block.
3. Resolve it in the precedence block: flag → memo → default.
4. Write the memo in the `apply_*` that consumes it, guarded by `remembering`.
5. Document it in `README.md`'s options table.
6. If the GUI or wizard should offer it, add it to **both** windows *and* to
   `install.sh`'s terminal wizard — parity is enforced by comment, not by code.
7. Run `check-gui-flags.py` and `check-wizard-flags.py`.

### Add or change a stylesheet

1. Name it `shell-NN-*.css` or `gtk4-NN-*.css`. The prefix is its cascade
   position and is load-bearing — later sheets are meant to win on equal
   specificity.
2. Add it to the matching `SHELL_SNIPPETS` / `GTK4_SNIPPETS` array in
   `bin/aura-glass-apply`, at the position its cascade needs.
3. `install_css` in `lib/steps-css.sh` globs the numbered sheets; an optional
   sheet (installed or removed by flag) needs its own branch there.
4. Run `tools/check-cascade.sh`.

### Change a radius or a blur sigma

1. Edit `tokens/tokens.sh`.
2. Edit every consumer its comment names.
3. If it is a radius, update the preset rows *and* `RADIUS_PRESET_ROWS` /
   bounds in `gui/aura_glass_settings.py`.
4. `tools/check-tokens.sh && python3 tools/check-gui-radius.py`.
5. Raise a radius against a screenshot (`tools/preview.sh`), never an estimate.

### Add an extension

Add the UUID to `EXT_EXTRA_RECOMMENDED` / `EXT_EXTRA_ALL` in `lib/steps.sh`,
give it an `ext_description`, and run `tools/check-ext-catalogue.sh` — the
settings window builds its list from `aura-glass-ext list`, so an undescribed
UUID is an empty row.

---

## Things that look like bugs and are not

- **Values duplicated between CSS and dconf.** Deliberate; see rule 3.
- **No custom accent hex.** `-st-accent-color` is a read-only St keyword backed
  by a nine-value C enum. A hex would recolour every app window and none of the
  shell. Long version in `tokens/tokens.sh`.
- **`pill` still accepted as a `--radius-preset`.** Retired name, resolved to
  `rounded`, because machines still hold a memo saying `pill`.
- **`--no-blur` ≠ `--glass-mode solid`.** The first is an opaque *themed*
  desktop. The second stands the whole theme down, settings intact.
- **The GUI passes only changed flags.** Anything untouched is resolved by the
  installer, which is the point.
- **Sheets copied to `$CONF_DIR` even in solid mode.** They cost nothing while
  nothing splices them, and it makes the way back one run.
