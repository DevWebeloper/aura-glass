# Developing and fixing bugs

The working loop, a bug-fixing protocol, and recipes for each kind of change.
Read [ARCHITECTURE.md](ARCHITECTURE.md) first. Most rules here only make sense
once you know why one place resolves a flag.

---

## Setup

```bash
git clone https://github.com/DevWebeloper/aura-glass.git && cd aura-glass
tools/install-hooks.sh        # once per clone: core.hooksPath → tools/hooks (pre-commit runs the checks)
./install.sh                  # you develop against a real install
```

You need bash, python3 and git, plus PyGObject, libadwaita and pycairo for
`gui/`. `tools/install-hooks.sh --off` disables the hook, and
`git commit --no-verify` skips it once.

## The loop

```bash
# 1. edit css/ dconf/ lib/ tokens/ gui/ …
# 2. hermetic checks (safe anywhere)
tools/check-tokens.sh && tools/check-cascade.sh        # plus whichever checks own the area (TESTING.md)
# 3. put it on the desktop you are sitting at (offline, rootless, seconds)
./install.sh --settings-only -y
# 4. commit; the hook re-runs the suite on the staged tree
git commit
```

**A repo edit isn't a finished change.** What the desktop loads are the copies
in `~/.config/aura-glass` spliced into `~/.themes` and `~/.config/gtk-*`.
`--settings-only` refreshes them in seconds with no root and no network. The
shell reloads itself, but GTK apps need a restart. Use a full `./install.sh`
(or `--force`) when you've changed something a retune skips: a pin, an
extension, a pack. A `dconf/core.ini` or `extras.ini` change reaches an
existing install through `merge_dconf_preset`, but only for keys the user
hasn't changed; `--force` reloads `core.ini` over everything.

---

## Bug-fixing protocol

### 1. Classify the bug by its path

Most bugs here are one front end disagreeing with another, so first find
**which path** produced the wrong state:

| The user did… | Path | Start reading |
|---|---|---|
| Ran `./install.sh` | full install | `install.sh` bottom section, then the step's file |
| Pressed Apply in the settings app | `--settings-only --incremental` (narrow, or full fallback) | `lib/steps-apply-plan.sh`, the incremental branch of `install.sh` |
| Dragged a slider and saw it live | `aura-glass-preview set/apps` | `bin/aura-glass-preview`, `gui/preview_queue.py` |
| Switched mode | full retune with `--glass-mode` | `lib/steps-modes.sh`, `load_dconf` |
| Nothing (battery, GPU, game, top-bar menu) | adaptive worker → `--adaptive-blur` | `tools/aura_glass_adaptive.py`, `apply_adaptive_blur` |
| Used "Blur This App" | `aura-glass-operation app-blur` | `extension.js` `_toggleBlur`, `aura-glass-preview app-blur`, `apply_app_blur` |
| Changed monitors or logged in | services, Blur My Shell | Blur My Shell's own panel code, `bin/aura-glass-icon-sync`, `bin/aura-glass-gdm-sync` |
| Updated the theme or upstream | `aura-glass-apply` | `bin/aura-glass-apply` |

### 2. Find the owner

Use [FEATURE-MAP.md](FEATURE-MAP.md) to go from a feature to its files and
function, and the ownership map in [STRUCTURE.md](STRUCTURE.md) §4 for who
writes the state you're looking at.

### 3. Capture the state before touching anything

```bash
gnome-shell --version; echo "$XDG_SESSION_TYPE"
./install.sh --settings-only --dry-run          # prints the resolved "glass-mode:" line
ls ~/.config/aura-glass ~/.config/aura-glass/modes/*
head -n 50 ~/.config/aura-glass/{glass-mode,app-transparency,app-tint-color,app-blur-scope} 2>/dev/null
dconf dump /org/gnome/shell/extensions/blur-my-shell/ | grep -E '^\[|^blur=|^notification='
```

### 4. Reproduce off the desktop when you can

Most of the installer runs fine against a **fixture `HOME`**. That's how the
existing checks work. You need a temp `HOME` with:

- `~/.themes/Aura-Glass/gnome-shell/gnome-shell.css`
- `~/.config/gtk-4.0/gtk.css`
- `~/.config/aura-glass/backups/*.absent`

and stub `dconf`, `gsettings`, `gnome-extensions`, `systemctl` and
`gnome-shell` (printing `GNOME Shell 50.1`) first on `PATH`, plus
`XDG_CURRENT_DESKTOP=GNOME`. Then run `install.sh --settings-only …`
**without** `--dry-run`, and inspect the memo files and the stub log. The
reproductions in [KNOWN-ISSUES.md](KNOWN-ISSUES.md) were made this way. Don't
add new scripts under `tools/` for this unless asked.

### 5. Fix at the owner, not at the symptom

- Wrong value resolved → fix the resolution block or the `apply_*`, never the front end.
- Front end shows the wrong value → make it read where the resolver reads (C5 in [CONSISTENCY.md](CONSISTENCY.md)).
- One path forgets a step another path does → share the step, don't copy it.
- Keep the scope to the bug. No drive-by refactors, no unrequested validation.

### 6. Verify on every path the fix touches

Walk the stability checklist in [CONSISTENCY.md](CONSISTENCY.md) §4: CLI,
incremental, mode switch on an existing install, settings app re-read, wizards,
preview, adaptive, uninstall. Then run the hermetic suite. Then apply it live
with `./install.sh --settings-only -y` and look at it.

### 7. Record it

Move the entry in [KNOWN-ISSUES.md](KNOWN-ISSUES.md) to **Fixed**, with the
commit. If the reason for a number changed, update its comment.

---

## Recipes

### Add or change a flag

1. Declare `VAR` and `VAR_EXPLICIT` at the top of `install.sh`.
2. Parse it in `parse_flags`, setting `_EXPLICIT` there and nowhere else.
3. Resolve and validate it in the resolution block (flag → drawer if mode-owned → memo → default). A typo must `die` before anything is written.
4. Consume it in an `apply_*`, and write the memo last, under `remembering`.
5. If it's mode-owned, add it to `seed_glass_mode`, `load_glass_mode_memos` and `save_glass_mode_memos`, to `Settings.modes` in the GUI, and to the restore branch of `apply_adaptive_blur`.
6. If the GUI sends it, decide its incremental class in `select_apply_actions`. If it's narrow, make sure the narrow path writes everything the full path does.
7. Add it to `--help` (`usage`), [CONFIG-REFERENCE.md](CONFIG-REFERENCE.md), and, if user-facing, the settings app plus **both** wizards.
8. Run `python3 tools/check-gui-flags.py && python3 tools/check-wizard-flags.py && python3 tools/check-incremental-apply.py`.

### Add or change a stylesheet

1. Name it `shell-NN-*.css` / `gtk4-NN-*.css`. The prefix is the cascade position.
2. Add it to `SHELL_SNIPPETS` / `GTK4_SNIPPETS` in `bin/aura-glass-apply`, in prefix order.
3. Numbered sheets are globbed by `install_css`. An optional sheet needs an explicit install-or-delete branch.
4. Add it to `tools/preview-session.sh` if the preview should render it.
5. Run `tools/check-cascade.sh`. If it carries a token value, also `tools/check-tokens.sh` and a `token_manifest.py` entry.

### Change a radius, sigma or transparency value

1. Edit `tokens/tokens.sh`: the value **and** its reason.
2. Edit every consumer its comment names (see FEATURE-MAP §8).
3. Radii: also the preset rows (`radius_preset_values`), the bounds (`radius_bounds`) and the GUI copy (`RADIUS_PRESET_VALUES`, `RADIUS_SURFACES`).
4. Run `tools/check-tokens.sh && python3 tools/check-gui-radius.py && tools/check-radius-preset.sh`.
5. Raise a radius against a screenshot, never an estimate. Measure sigma changes on a real session (`tools/gpu-live.sh`, humans only) and record the number.

The rule: a painted radius equals the blur radius behind it, so
`apply_radius_css` and `apply_radius_dconf` always move together.

### Add an extension

1. Append the UUID to `EXT_EXTRA_RECOMMENDED` and/or `EXT_EXTRA_ALL` (`lib/steps.sh`) and give it an `ext_description`.
2. `EXT_NO_AUTO_ENABLE` if a pack must never switch it on. Settings go in `dconf/extras.ini`.
3. Update the text wizard's prose list, `--help` counts, and `uninstall.sh`'s removal list.
4. Run `tools/check-ext-catalogue.sh`.

### Bump a pinned upstream

Change the ref in `lib/steps.sh`. Re-make any patch in `patches/` that no
longer applies. Then a human runs `./install.sh --full --force`, then
`tools/preview.sh` and `python3 tools/check-shots.py --mode glass`, and diffs
the screenshots before accepting. Upstreams are pinned because a theme that
moves under the CSS fails silently.

### Touch the GUI

See [GUI.md](GUI.md). In short: it emits flags only, sends only what changed,
reads state where the installer reads it, and opens a real terminal for
anything that needs root. Run `check-gui-flags.py`, `check-wizard-flags.py`,
`check-gui-radius.py`, `check-terminal-spawn.py`, `check-preview-queue.py` and
`check-apply-lifecycle.py`.

### Touch the adaptive worker

Its launcher prefers the **installed** copy in `~/.local/share/aura-glass/`.
After editing `tools/aura_glass_adaptive.py`, a retune reinstalls it. Then
`systemctl --user restart aura-glass-adaptive`.
Checks: `check-adaptive-worker.py`, `check-adaptive-installer.sh`.

---

## Seeing a change without logging out (humans only)

| Tool | What it does |
|---|---|
| `tools/preview.sh [--solid\|--gtk-only APP\|--transparency L\|--tint N\|--style S\|--gpu\|--keep\|--res WxH]` | Renders the real shell against the real theme headlessly (`dbus-run-session`, private `HOME`/XDG dirs, `mutter --headless --virtual-monitor`) into `screenshots/preview/`. Needs an installed theme. Never run `tools/preview-session.sh` directly: against your own `HOME` it overwrites your desktop's settings. |
| `python3 tools/check-shots.py --mode glass [--accept\|--list]` | Visual diff against the last accepted run. Glass and solid keep separate baselines. |
| `.claude/scene.py NAME [--css\|--live]` | Local helper that renders one GTK window in about a second, to find which selector paints which surface. Without a compositor, blur and transparency render against black. |
| `tools/gpu-live.sh --label before`, `python3 tools/gpu-sample.py --probe` | GPU cost on the real session. The headless harness can't see repaint cost. |

---

## House style

- **Bash.** `set -euo pipefail`. Mutations go through `run` (dry-run honesty). Overwrites go through `backup_once` (uninstall completeness). Memo writes go through `remembering` (dry-run, preview and adaptive invisibility). Output uses `step/info/ok/warn/skip/die`, never bare `echo`.
- **Python.** Standard library + PyGObject (+ pycairo in the settings app). The setup wizard may import only what `lib/distro.sh` probes for.
- **Comments are the deliverable.** Every non-obvious number says why it's that number, usually the result of a bisection against a screenshot. Change the reason with the value. Don't change a value whose reason you can't state.
- **Naming.** New code writes only `aura-glass`. Legacy `tahoe-glass` read paths stay until `check-migration.sh` says otherwise.
- **Commits.** `type(scope): lower-case sentence, no trailing period`, e.g. `fix(modes): …`, `feat(gui): …`, `docs: …`. No AI attribution anywhere (see [RELEASING.md](RELEASING.md)).
