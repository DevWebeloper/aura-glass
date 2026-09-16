# Testing

There is no unit-test framework here. The tests are standalone scripts that
drive the real code against fixture `HOME`s, throwaway git repositories, or
`--dry-run`, and exit non-zero naming what disagrees. Most run in under a
second; none of them touch your desktop unless the entry says so.

---

## Running everything

```bash
tools/install-hooks.sh     # once per clone
git commit                 # the hook runs the whole suite
```

The pre-commit hook checks the **staged tree**, not the working tree. It does
that by turning the index into a real tree object (`git write-tree`) and
extracting it with `git archive` into a temp directory — nothing is stashed and
the working tree is never touched, which is what makes the hook safe to fail in.
The distinction matters because this project stages explicitly rather than
`git add -A`, so the working tree routinely holds changes that are not part of
the commit being made.

Bypass for one commit with `git commit --no-verify`; disable entirely with
`tools/install-hooks.sh --off`.

By hand, all at once:

```bash
for c in tools/check-*.sh;  do echo "== $c"; bash "$c" || echo FAIL; done
for c in tools/check-*.py;  do echo "== $c"; python3 "$c" || echo FAIL; done
```

(`check-preview.sh` and `check-shots.py` are the two exceptions — see below.)

---

## What the hook runs

Syntax first, because it catches the one mistake that would otherwise reach a
machine running the installer: a script that cannot be parsed.

| Check | Asserts |
|---|---|
| shell syntax | `bash -n` over every `*.sh`, `bin/*`, `tools/hooks/*` |
| python syntax | `py_compile` over every `*.py` |
| preview driver syntax | `node --check` on `tools/preview-driver/extension.js`, where node happens to exist (node is not a project dependency) |

Then the project's own checks:

### `tools/check-tokens.sh`

Every value in `tokens/tokens.sh` still matches every file that writes it down.
Exits naming the exact file and line that disagrees. This is the mechanism that
makes the CSS/dconf duplication safe — the pairing list comes from
`tools/token_manifest.py`, which is the machine-readable form of the per-token
comments in `tokens.sh` itself.

Also asserts `radius_preset_matches_shipped` — that the `default` preset row and
the eight literal `TOKEN_RADIUS_*` values, which are the same numbers written
twice, actually agree.

### `tools/check-cascade.sh`

Every stylesheet in `css/` is installed, applied and previewed, and the cascade
runs in the order the numeric prefixes ask for. Three separate places decide a
sheet's fate — `install_css`, the `*_SNIPPETS` arrays in `bin/aura-glass-apply`,
and `tools/preview-session.sh` — and only one of them is a glob, so a new sheet
that reaches only two of the three is invisible until someone looks at a
screenshot.

### `tools/check-radius-preset.sh`

`tools/apply-radius-preset.py` rewrites exactly the radii it is meant to and
nothing else. The writer is a regex substitution over installed stylesheets,
which is the same shape as the mistake `check-tokens.sh` exists to catch — with
the difference that this one runs *after* install, so nothing else would notice.
Writes only to a temporary directory.

`check-tokens.sh` asserts the repo sits at the shipped radii; this asserts a
preset can move them and move nothing else.

### `tools/check-glass-modes.sh`

`--glass-mode` resolves into the blur flags the design table says. Runs through
`install.sh --settings-only --dry-run`, which parses and resolves exactly as a
real run would and writes nothing. It reads the one line every dry run prints:

```
glass-mode: frosted blur=1 window=1 popup=1 transparency=0.90 styling=1
```

### `tools/check-solid-extensions.sh`

The record `stand_down_extensions` / `restore_extensions` keep in
`$CONF_DIR/modes/solid/disabled-extensions` round-trips correctly across more
than one run. Separate from `check-glass-modes.sh` because it needs a different
mechanism: that record is only ever written or read under `DRY_RUN=0`, so a dry
run can never exercise it. This calls the two functions directly against a stub
`gnome-extensions`.

### `tools/check-styling-off.sh`

`bin/aura-glass-apply` splices when the theme is up and stands it down when
`$CONF_DIR/styling-off` is there — against a fixture `HOME`, never the real
desktop. Covers all three stand-down branches: restore the `.orig` backup, move
a `.absent`-recorded file aside as `.stood-down`, or strip the marked block when
neither record exists.

### `tools/check-migration.sh`

Moving a pre-rename (`tahoe-glass`) install onto the current names, against
fixture `HOME`s. Nothing touches the real `HOME` and nothing reaches the
network. The `backups/` merge is the part worth guarding: getting it wrong
silently turns a clean uninstall into one that leaves every GTK4 app themed.

### `tools/check-ext-catalogue.sh`

`bin/aura-glass-ext list` describes every extension this project ships. The
settings window builds its Extensions page from that command rather than from a
copy of the arrays, so the command *is* the catalogue as far as the window is
concerned — an extension in `EXT_EXTRA_ALL` with no `ext_description` renders as
an empty row.

### `tools/check-app-blur-lists.sh`

The per-app blur lists survive the trip from a flag, through a memo, to a dconf
array literal, and back out as the same patterns. These lists are the one place
in the project where **arbitrary user text reaches dconf** — a pattern is
whatever someone typed into the settings window. The check builds the literal
and parses it back with GLib's own parser; no live dconf is touched.

### `tools/check-update-check.sh`

`bin/aura-glass-update-check` compares versions the way versions compare, against
throwaway git repositories. No network, never the user's checkout. The failure
modes here are quiet: a lexicographic compare puts `v0.1.10` before `v0.1.9`, so
the release after the ninth would never be announced. Also covers `-beta` tag
filtering.

### `tools/check-update-channel.py`

The settings window and the update check agree on which line a checkout is on.
There are two lines — releases on `main`, commits on a branch someone is testing
— and two independent programs decide which one a checkout is on
(`current_branch` / `is_test_build` / `installed_version` in the window, and
`bin/aura-glass-update-check`). Nothing else would notice them drifting apart.

### `tools/check-gui-flags.py`

The settings window builds `install.sh` arguments `install.sh` accepts. The
window sends only the flags that changed, which keeps it out of the business of
resolving precedence and squarely in the business of not emitting a combination
the installer refuses — and there is at least one such combination. Runs
`install.sh --dry-run`, so it writes nothing; skips itself where PyGObject is
absent, exactly as `install_gui` does.

### `tools/check-wizard-flags.py`

The same for the setup wizard, which composes a whole command line rather than a
diff — so `install.sh` has to accept every line it can produce, including the
`--extensions` list its per-extension switches send.

### `tools/check-gui-radius.py`

The settings window's radius numbers agree with `tokens/tokens.sh`. The window
carries its own copy of the preset rows and the per-surface bounds because the
spin rows need their ranges at build time, before `install.sh` runs. Same
arrangement `tokens.sh` defends for the stylesheets, so it gets the same
treatment: the duplication is checked rather than trusted.

### `tools/check-terminal-spawn.py`

The settings window builds a runnable command line for each terminal it knows.
Whether a spawned terminal really *stays open* is a thing only a desktop can
answer and this does not pretend to; what it catches is the cheap half — a
malformed argv, a builder that drops the command, a wrapper that will not parse.
It launches nothing.

---

## Not in the hook

### `tools/check-preview.sh`

`bin/aura-glass-preview` leaves the desktop showing a candidate without ever
leaving a `$CONF_DIR` memo different from what it found — the single safety
property that script exists to keep. Unlike the other checks it **cannot run in
an isolated tmpdir**: it calls the real `install_css` / `apply_radius_dconf` /
`apply_*` against the real installed state, so it is a deliberate manual run on
a machine with aura-glass installed.

```bash
tools/check-preview.sh
```

### `tools/check-shots.py`

Visual regression, driven by `tools/preview.sh` rather than by the hook.

```bash
python3 tools/check-shots.py --mode glass            # compare, say what moved
python3 tools/check-shots.py --mode glass --accept   # adopt this run as baseline
python3 tools/check-shots.py --mode solid --list     # what is in the baseline
```

`glass` and `solid` keep separate baselines. `screenshots/preview/` is
gitignored — each run is a fresh set of 1080p PNGs.

### `tools/preview-extensions.py`

Reports which extensions the preview shell actually loaded. Worth running when a
preview looks wrong in a suspiciously plausible way: a shell that silently
loaded none of them renders a stock desktop, and the screenshots give no hint
that the thing you meant to test was never enabled.

### `tools/gpu-sample.py` / `tools/gpu-live.sh`

Performance measurement on a real session. See
[DEVELOPING.md](DEVELOPING.md#gpu-cost) — the headless harness structurally
cannot see this class of cost.

---

## Writing a new check

Follow the shape the existing ones use:

- Take `REPO_ROOT` from the script's own location, so an extracted copy checks
  the extracted tree — that is what makes the pre-commit hook's staged-tree
  trick work.
- Never touch the real `HOME`, the real dconf, or the network. Use a fixture
  `HOME`, a temp directory, a stub binary on `PATH`, or `--dry-run`.
- Exit non-zero, and print the exact file and line that disagrees. A check that
  says "failed" without saying where costs more than it saves.
- Add it to `tools/hooks/pre-commit` with a comment saying what class of mistake
  it catches and why the existing checks do not.
