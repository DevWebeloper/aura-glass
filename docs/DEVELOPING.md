# Developing

The working loop, and how to make each kind of change.

Read [ARCHITECTURE.md](ARCHITECTURE.md) first if you have not — most of the
rules below only make sense once you know why one place resolves a flag.

---

## Setup

```bash
git clone https://github.com/DevWebeloper/aura-glass.git
cd aura-glass
tools/install-hooks.sh        # once per clone — points core.hooksPath at tools/hooks
./install.sh                  # you need an installed theme to develop against
```

`tools/install-hooks.sh --off` undoes the hook. `git commit --no-verify` skips
it for one commit.

No dependencies beyond what the installer already needs: bash, python3, git,
plus PyGObject and libadwaita if you touch `gui/`.

---

## The loop

```bash
# 1. edit css/, dconf/, lib/, tokens/ …

# 2. put it on the desktop you are sitting in front of
./install.sh --settings-only -y

# 3. check the numbers still agree everywhere
tools/check-tokens.sh && tools/check-cascade.sh

# 4. commit — the hook runs the whole suite against the staged tree
git commit
```

Step 2 is not optional. **A repo edit is not a finished change**; the
stylesheets that matter are the copies in `~/.config/aura-glass` spliced into
`~/.themes`. `--settings-only` reapplies the dconf preset, the CSS and the
gsettings and leaves the theme and extensions alone: no root, no network, a few
seconds. The shell reloads itself; GTK apps need a restart.

Full re-install when you changed something `--settings-only` skips (a pinned
upstream, an extension, an icon or cursor pack):

```bash
./install.sh --full          # or the specific flags you need
./install.sh --dry-run       # print what would happen, change nothing
```

---

## Seeing a visual change without logging out

### The headless preview harness

```bash
tools/preview.sh                       # shell screenshots from the current tree
tools/preview.sh --gtk-only [app]      # one GTK app on your own session
tools/preview.sh --solid               # render the --no-blur look
tools/preview.sh --transparency 0.85   # translucent windows at that level
tools/preview.sh --tint 70             # how much theme colour survives vs black
tools/preview.sh --style adwaita       # a different titlebar button style
tools/preview.sh --gpu                 # sample GPU busy% while it runs
tools/preview.sh --keep                # leave the session up
tools/preview.sh --res 2560x1440
```

It renders the **real shell against the real theme** in about a minute and drops
PNGs in `screenshots/preview/` (gitignored). It needs an installed theme — it
previews a working copy, it does not build one from scratch.

Isolation is four separate things and all four are needed:
`dbus-run-session` (a private bus so the preview owns `org.gnome.Shell`), `HOME`
(User Themes reads `~/.themes` relative to it, governed by no XDG variable),
`XDG_{CONFIG,DATA,CACHE}_HOME`, and `XDG_RUNTIME_DIR` — that last one is not
optional, because the live session leaves
`$XDG_RUNTIME_DIR/gnome-shell-disable-extensions` lying around and sharing it
renders a stock desktop that looks exactly like the theme having failed.

This is a **headless render, not a window you can click**. `mutter --nested` is
gone from mutter 18, so a shell started inside your session takes the native
backend and dies with EBUSY. `--headless --virtual-monitor` is the mode that
works, and only the screenshot API can see its output.

`tools/preview-session.sh` is the inside of that harness and expects `HOME` and
the XDG variables to be redirected already. **Do not run it directly** — against
your own `HOME` it would overwrite the GSettings keyfile and theme of the
desktop you are using.

### Comparing runs

Every run is compared against the last accepted run of the same mode:

```bash
python3 tools/check-shots.py --mode glass            # what moved
python3 tools/check-shots.py --mode glass --accept   # adopt this run as baseline
python3 tools/check-shots.py --mode solid --list     # what is in the baseline
```

`glass` and `solid` keep separate baselines.

### One GTK window, fast

`.claude/scene.py` (local, gitignored) renders a single GTK window headlessly in
about a second — for when a CSS edit needs *guessing* which selector paints
which surface. See `.claude/README.md`. It cannot show blur or window
transparency truthfully: with no compositor behind the window everything
composites against black.

### GPU cost

```bash
tools/gpu-live.sh --label before      # on the session you actually use
tools/gpu-live.sh --quick             # skip the scenarios needing your hands
python3 tools/gpu-sample.py --probe   # is there a counter on this machine
```

The headless harness **cannot** see this class of cost — it renders to a virtual
monitor and never pays the repaint a real display does. Panel sigma was tuned
against the harness for an afternoon and moved nothing for exactly that reason.
Sigma changes are design decisions with a measurable cost: change one, measure
it, record the number in `tokens/tokens.sh`, and do not batch them.

---

## How to make each kind of change

### Add a flag

1. Declare the variable and its `*_EXPLICIT` twin at the top of `install.sh`.
2. Parse it in the argument `case` block; set `_EXPLICIT` there and nowhere else.
3. Resolve it in the precedence block: `_EXPLICIT` wins, then the mode drawer if
   it is a mode-owned setting, then `$CONF_DIR/<name>`, then the default.
   Validate there — a typo must die before anything has been written.
4. Consume it in an `apply_*` in `lib/steps-css.sh` or `lib/steps-dconf.sh`, and
   write the memo back as that function's last step, guarded by `remembering`.
5. Add the row to `README.md`'s options table.
6. If it belongs in the UI, add it to **all three**: the settings window, the
   setup wizard, and `install.sh`'s terminal wizard. Wizard parity is a stated
   rule, not something code enforces — a question added to one and not the other
   is a setting half your users are never offered.
7. `python3 tools/check-gui-flags.py && python3 tools/check-wizard-flags.py`.

### Add or change a stylesheet

1. Name it `shell-NN-*.css` or `gtk4-NN-*.css`. **The prefix is the cascade
   position** and is load-bearing — put a new sheet where its cascade needs it,
   not at the end.
2. Add it to `SHELL_SNIPPETS` or `GTK4_SNIPPETS` in `bin/aura-glass-apply`, in
   prefix order.
3. `install_css` globs the numbered sheets automatically. An **optional** sheet
   (one a flag installs or removes) needs its own branch there — it must be
   installed or deleted, never switched on at read time, because
   `aura-glass-apply` concatenates what it finds and cannot know your flags.
4. Add it to `tools/preview-session.sh` if the preview should render it.
5. `tools/check-cascade.sh`.

### Change a radius, sigma or transparency value

1. Edit `tokens/tokens.sh` — the token *and* the comment saying why.
2. Edit every consumer the comment names.
3. Radii: update all seven preset rows in `radius_preset_values`, the bounds in
   `radius_bounds`, **and** the window's own copy in
   `gui/aura_glass_settings.py`.
4. `tools/check-tokens.sh && python3 tools/check-gui-radius.py &&
   tools/check-radius-preset.sh`
5. **Raise a radius against a screenshot, never an estimate.** The OSD ceiling
   in particular has nothing to do with the other seven — it is set by the
   height of the box being blurred, and past half of it the corner arcs overlap
   into an ellipse.

Remember the project rule: a painted radius must equal the blur radius behind
it, so `apply_radius_css` and `apply_radius_dconf` always move together.

### Add an extension

1. Append the UUID to `EXT_EXTRA_RECOMMENDED` and/or `EXT_EXTRA_ALL` in
   `lib/steps.sh`.
2. Give it an `ext_description` — the settings window builds its Extensions page
   from `aura-glass-ext list`, so an undescribed UUID is an empty row.
3. If it must never arrive switched on by a pack, add it to `EXT_NO_AUTO_ENABLE`
   and say why in the comment.
4. If it needs settings, add them to `dconf/extras.ini`.
5. `tools/check-ext-catalogue.sh`.

### Bump a pinned upstream

Pins live at the top of `lib/steps.sh`. Bump the ref, re-apply any patch in
`patches/` that no longer applies cleanly, then:

```bash
./install.sh --full --force
tools/preview.sh
python3 tools/check-shots.py --mode glass
```

A theme that changes under the CSS tweaks produces a half-applied look with **no
error message**, which is why these are pinned in the first place. Diff the
screenshots before you accept the bump.

### Touch the GUI

`gui/` never writes theme files. It composes `install.sh --settings-only --yes
<changed flags>` and runs it. Constraints:

- Standard library plus PyGObject only. The setup wizard may not import
  anything `lib/distro.sh` does not probe for — not even pycairo.
- The setup wizard's **stdout is the flag list, one token per line, and nothing
  else may ever be printed there.** Human output goes to stderr. Exit 0 =
  answered, 2 = cancelled (install stops, nothing changed), anything else falls
  back to the terminal wizard.
- `install.sh` blocks on the wizard. The settings window spawns terminals it
  never waits for. Do not swap those.
- Anything needing root opens a real terminal. `sudo` down a pipe nothing can
  type into blocks forever.

Then run `check-gui-flags.py`, `check-wizard-flags.py`, `check-gui-radius.py`
and `check-terminal-spawn.py`.

---

## House style

**Bash.** `set -euo pipefail`. Every filesystem mutation goes through `run()` so
`--dry-run` stays honest. Every overwrite goes through `backup_once` so
uninstall stays complete. Every memo write is guarded by `remembering()` so dry
runs and live previews leave nothing behind. Output uses `step/info/ok/warn/
skip/die` from `lib/common.sh`, never bare `echo`.

**Comments.** Every non-obvious number carries a comment saying why it is that
number — usually the result of a bisection against a screenshot. Those comments
are the deliverable. When you change a value, change the reason with it. If you
cannot state the reason, do not change the value.

**Scope.** Do the change that was asked for. No unrequested validation, defensive
branches, or drive-by refactors.

**Naming.** Both `aura-glass` and the pre-rename `tahoe-glass` are honoured at
read time in `bin/aura-glass-apply` and `uninstall.sh`. New code writes only the
current name; do not remove a legacy read path without checking
`tools/check-migration.sh`.
