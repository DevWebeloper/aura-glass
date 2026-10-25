# CLAUDE.md: working on Aura Glass

Instructions for an AI agent (or a new contributor) in this repository. Read
this first. [README.md](README.md) is the user document. The long-form
contributor docs start at [docs/README.md](docs/README.md).

---

## What this is, in one paragraph

Aura Glass is a frosted-glass desktop for **GNOME Shell 48–51**, delivered by a
Bash installer rather than a package. `install.sh` fetches **pinned** upstreams
(the GNOME-macOS-Tahoe theme, adopted as `Aura-Glass`, plus Blur My Shell v73
with three patches and a patched Custom OSD). It copies `css/` into
`~/.config/aura-glass`, rewrites those copies for the user's choices, splices
them into four generated CSS files with `bin/aura-glass-apply`, loads dconf
presets, writes gsettings, and installs a first-party extension (Aura Glass
Helper), user services (icon sync, GDM sync, update check,
adaptive performance) and a GTK settings app. Every choice is remembered as a
memo, so a flagless re-run reproduces it. Two glass modes exist: **frosted** and
**performance**. Adaptive performance is a transient overlay on frosted.

**The goal** is one consistent material across shell, GTK4 and GTK3 that stays
consistent across every front end, re-run, mode switch, preview and adaptive
transition, and that uninstalls cleanly. Most bugs are a breach of that
consistency. See [docs/CONSISTENCY.md](docs/CONSISTENCY.md).

---

## Where to look

| Need | Go to |
|---|---|
| Which file draws X / owns setting Y | [docs/FEATURE-MAP.md](docs/FEATURE-MAP.md), **before** grepping |
| Every file, install location, call graph, who writes what | [docs/STRUCTURE.md](docs/STRUCTURE.md) |
| How a run works (precedence, modes, CSS pipeline, lock) | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| A flag, memo, path, env var, key | [docs/CONFIG-REFERENCE.md](docs/CONFIG-REFERENCE.md) |
| Bugs already found, with repros and fix directions | [docs/KNOWN-ISSUES.md](docs/KNOWN-ISSUES.md) |
| How to fix a bug, recipes for changes | [docs/DEVELOPING.md](docs/DEVELOPING.md) |
| Which checks exist and which are safe to run | [docs/TESTING.md](docs/TESTING.md) |
| The two GTK windows | [docs/GUI.md](docs/GUI.md) |

```
install.sh  uninstall.sh            entry points
lib/        the steps (steps.sh first: pins, paths, extension arrays)
tokens/     every number written twice
css/        stylesheets, NN- prefix = cascade order
dconf/      core.ini (BMS + Custom OSD), solid.ini (no-blur), extras.ini
bin/        commands installed to ~/.local/bin
gui/        setup wizard + settings app (front ends for flags)
extensions/ Aura Glass Helper (window menu, D-Bus bridge, adaptive menu)
systemd/    user units
tools/      runtime helpers + hermetic checks + live-session tools (see rule 6)
```

---

## Rules

### 1. One resolver

Only `install.sh` (parse → resolution block) and the `apply_*`/`install_*`
functions in `lib/` turn a flag into a file, key or memo. The settings app, both
wizards, `aura-glass-preview`, the adaptive worker and the window menu all go
through that code. Precedence is: **typed flag → `--glass-mode` → mode drawer
`modes/<mode>/<key>` → top-level memo → default**. Never add a second copy. If a
front end must know a value early (radius rows, bounds), duplicate it **and**
add or extend a checker.

### 2. Never hand-edit generated files

`~/.themes/Aura-Glass/gnome-shell/gnome-shell.css`,
`~/.config/gtk-4.0/gtk.css`, `gtk-dark.css` and `~/.config/gtk-3.0/gtk.css` are
generated. `bin/aura-glass-apply` owns one
`/* >>> aura-glass BEGIN <<< */ … END` block in each. Edit `css/` and re-apply.
Never edit the installed copies in `~/.config/aura-glass/` either. They're
recopied every run.

### 3. Duplicated numbers are checked, not trusted

`tokens/tokens.sh` is the source of truth for radii, sigmas and transparency.
Change the token, then every consumer its comment names (FEATURE-MAP §8), then
run `tools/check-tokens.sh` (plus `check-gui-radius.py` and
`check-radius-preset.sh` for radii). A painted radius must equal the blur
radius behind it.

### 4. Comments are the deliverable

Non-obvious numbers in `css/`, `dconf/`, `lib/` and `tokens/` carry a comment
saying **why** (usually a bisection against a screenshot). Don't strip or
shorten them. Update the reason when you change the value. If you can't say
why a number is what it is, don't change it.

### 5. A repo edit isn't a finished change

After editing `css/`, `dconf/` or `tokens/`, the change has to reach the
desktop: `./install.sh --settings-only -y` (offline, rootless, seconds). On the
user's own machine you may run exactly that retune. **Don't** run a full
install, `--force`, `uninstall.sh`, anything that needs `sudo`, or GDM steps
unless the user asks. Remember that `core.ini` changes reach an existing
install only for keys the user hasn't changed, and `--force` reloads it over
everything (ARCHITECTURE §7).

### 6. `tools/` holds three kinds of file, treated differently

- **Runtime helpers** (10): `rescale-transparency.py`, `apply-tint-color.py`, `apply-shell-tint.py`, `apply-notification-opacity.py`, `apply-radius-preset.py`, `apply-popup-brightness.py`, `token_manifest.py`, `moga_cursor.py`, `aura_glass_operation.py`, `aura_glass_adaptive.py`. These are **part of the theme**. `lib/` and `bin/` call them. Don't move or rename one without updating every caller, and don't add new ones unless asked.
- **Hermetic checks** (`check-*` except the live ones below). Fixture `HOME`, temp dirs, stubs, `--dry-run`. **Agents may run these.**
- **Live-session tools.** `preview.sh`, `preview-session.sh`, `preview-shot.py`, `preview-extensions.py`, `preview-driver/`, `gpu-live.sh`, `gpu-sample.py`, `check-preview.sh`, `check-shots.py`. Agents **may** run these to verify a change live (the nested preview shell, screenshots, GPU sampling). Run them only as their docs say (`preview-session.sh` only through `preview.sh`), and put back any live-desktop state a run changed. `check-shots.py --accept` replaces the baseline, so only on the user's say-so.
- **Don't create new files in `tools/`** (new checks, new scripts) unless the user asks for them.

### 7. Keep every path consistent

Any change to a setting must hold on every path that can reach it: CLI,
`--incremental` (the settings app's Apply), a mode switch on an **existing**
install, the settings app's re-read, both wizards, the preview, adaptive
active/restore, and uninstall. Walk the checklist in
[docs/CONSISTENCY.md](docs/CONSISTENCY.md) §4. Key sub-rules:

- **Readers read where the resolver reads**, with the same missing-memo defaults.
- **Wizard parity.** The GTK wizard and the text wizard in `install.sh` ask the same questions with the same options and recommendations.
- Every memo write is under `remembering()`. Every project writer holds the `aura-glass-operation` lock.
- Everything installed is uninstalled.

### 8. Stay in scope

Do what was asked. No unrequested validation, defensive branches,
refactors or "while I was here" edits. This codebase is deliberate, and most
oddities have a comment above them explaining why. Read it before "fixing"
it. If you disagree with a recorded decision, say so instead of changing it
silently.

### 9. No AI attribution

No `Co-Authored-By` trailers, "generated with" footers or assistant mentions in
commits, tags or releases. Commit subjects follow
`type(scope): lower-case sentence, no trailing period`.

---

## Fixing a bug

1. Check [docs/KNOWN-ISSUES.md](docs/KNOWN-ISSUES.md). It may already be diagnosed.
2. Identify the **path** that produced the bad state (table in [docs/DEVELOPING.md](docs/DEVELOPING.md)) and its **owner** (FEATURE-MAP, STRUCTURE §4).
3. Reproduce off the desktop where possible (fixture `HOME` + stubs, as the checks do).
4. Fix at the owner, not the symptom. Keep the "why" comments true.
5. Run the hermetic checks for the area. Ask the user to verify live (or run the retune from rule 5).
6. Update KNOWN-ISSUES (move the entry to **Fixed**) and any doc the fix made wrong.

## Bash and Python conventions

- Bash: `set -euo pipefail`. Mutations go through `run`, overwrites through `backup_once`, memos through `remembering`, output through `step/info/ok/warn/skip/die`.
- Python: standard library + PyGObject (the settings app also uses pycairo). `gui/` never writes theme files.
- New code writes only the `aura-glass` names. Legacy `tahoe-glass` read paths stay.

## Things that look like bugs and aren't

- **Values duplicated between CSS, dconf and the GUI.** Deliberate (rule 3), and checked.
- **No custom accent hex.** `-st-accent-color` is a read-only St keyword. A hex would recolour apps but not the shell.
- **`pill` accepted as a radius preset.** A retired name, mapped to `rounded` for old memos.
- **The settings app sends only changed flags.** The installer resolves the rest. That's the point.
- **Sheets copied to `$CONF_DIR` even when unused.** Cheap, and it makes switching back one run.
- **`load_dconf` skips `core.ini` on an existing install.** It preserves the user's extension settings and merges instead (`merge_dconf_preset`): only keys still on a shipped value move. Use `--force` to reload. But see KI-03 for what that does to mode switches.
- **`refresh_bms_after_dconf` does nothing on GNOME ≥ 51.** Disabling Blur My Shell live segfaults Mutter there. The adaptive path turns pipelines off instead of disabling the extension, for the same reason.
- **Every full apply writes `color-scheme=prefer-dark`.** The theme is dark-only, so a retune deliberately puts dark back over a light choice (KI-16, by design).
