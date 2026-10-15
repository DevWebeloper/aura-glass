# Testing

There's no unit-test framework. The checks are standalone scripts in `tools/`
that drive the **real** code against fixture `HOME`s, throwaway git repos,
stubbed commands or `--dry-run`, and exit non-zero naming the file and line
that disagree.

As of the 2026-10-15 audit, all 27 hook steps (3 syntax passes + 24 checks) pass on the working tree.

---

## Safety classes (read before running anything)

| Class | Meaning | Who may run |
|---|---|---|
| **Hermetic** | Touches only temp dirs, fixture `HOME`s and stubs. Never the real desktop, dconf or network | anyone, including agents |
| **Live** | Uses the real session, real `HOME`, GPU or screenshots | humans only |

All `check-*` scripts are hermetic **except** `check-preview.sh`,
`check-shots.py` and `check-moga-cursors.sh` (KI-14). The `preview*`,
`gpu-*` and `preview-driver/` files are live tools, not checks.

---

## Running

```bash
tools/install-hooks.sh     # once per clone
git commit                 # the hook runs the suite against the STAGED tree
```

The hook (`tools/hooks/pre-commit`) turns the index into a tree with
`git write-tree`, extracts it with `git archive` into a temp dir, and checks
that copy. Nothing is stashed and the working tree is never touched, so
partially staged work is fine. Every check takes `REPO_ROOT` from its own
location, which is what makes this work.

By hand, hermetic checks only:

```bash
for c in tools/check-*.sh; do case "$c" in *check-preview.sh|*check-moga-cursors.sh) continue;; esac
  echo "== $c"; bash "$c" || echo FAIL; done
for c in tools/check-*.py; do case "$c" in *check-shots.py) continue;; esac
  echo "== $c"; python3 "$c" || echo FAIL; done
```

**Outside a GNOME session** (CI, a container, an agent sandbox), several checks
run `install.sh`, whose `preflight` needs:

- a `gnome-shell` on `PATH` that prints a version (a two-line stub printing `GNOME Shell 50.1` is enough),
- `XDG_CURRENT_DESKTOP=GNOME`,
- PyGObject with Gtk 4, Adw 1 **and pycairo**. Without pycairo, `check-gui-flags.py` and `check-update-channel.py` fail on `import cairo` (KI-04).

Use a throwaway `HOME` as well. The checks don't need the real one.

---

## What each check asserts

### In the pre-commit hook (3 syntax passes + 24 checks)

| Check | Asserts |
|---|---|
| shell syntax | `bash -n` on every `*.sh`, `bin/*` and `tools/hooks/*` |
| python syntax | `py_compile` on every `*.py` |
| preview driver syntax | `node --check tools/preview-driver/extension.js` (only where node exists) |
| `check-tokens.sh` | every `tokens.sh` value matches every consumer listed in `token_manifest.py`, and the `default` preset row equals the literal tokens |
| `check-cascade.sh` | every sheet is installed, spliced and previewed, in prefix order (`install_css` ↔ `*_SNIPPETS` ↔ `preview-session.sh`) |
| `check-radius-preset.sh` | `apply-radius-preset.py` moves exactly the radii it should and nothing else (temp dir) |
| `check-gui-flags.py` | every argument list `Settings.flags_against` can build is accepted by `install.sh --dry-run` (skips without PyGObject) |
| `check-wizard-flags.py` | the same for the setup wizard's full command lines, including `--extensions` |
| `check-gui-radius.py` | the GUI's preset rows and bounds equal `tokens.sh` |
| `check-terminal-spawn.py` | each known terminal gets a runnable argv (launches nothing) |
| `check-ext-catalogue.sh` | `aura-glass-ext list` describes every extension the install can reach |
| `check-app-blur-lists.sh` | per-app patterns survive flag → memo → GVariant literal → GLib parse |
| `check-glass-modes.sh` | `--glass-mode` and blur flags resolve as designed (the dry-run `glass-mode:` line plus dconf write lines) |
| `check-solid-extensions.sh` | legacy `stand_down_extensions`/`restore_extensions` round-trip (stub `gnome-extensions`) |
| `check-styling-off.sh` | `aura-glass-apply` splices, or stands down via the three backup branches (fixture `HOME`) |
| `check-migration.sh` | `tahoe-glass` → `aura-glass` migration and the `backups/` merge (fixture `HOME`s) |
| `check-update-check.sh` | version ordering (`sort -V`), tag filtering, `-beta` (throwaway repos) |
| `check-update-channel.py` | the GUI and `aura-glass-update-check` agree on the release vs branch channel |
| `check-preview-queue.py` | `PreviewQueue` lifecycle: one active op, one pending, and Apply/Revert/Close priority |
| `check-operation-recovery.py` | the writer lock: serialization, inheritance, timeout, signal forwarding |
| `check-apply-publication.py` | `aura-glass-apply` publishes atomically and quietly (identical output isn't rewritten) |
| `check-integration-reconcile.py` | installed helpers and units aren't recopied when unchanged |
| `check-panel-blur-events.py` | bursts of monitor events collapse into one panel rebuild |
| `check-incremental-apply.py` | `--plan-json` classification through the real parser |
| `check-apply-feedback.py` | GUI recovery feedback comes from the backend protocol, not parsed log text |
| `check-adaptive-worker.py` | the worker's reducer: hysteresis, debounce, immediate triggers, profiles |
| `check-adaptive-installer.sh` | `--adaptive-blur active` turns blur off without touching memos, and `restore` brings back the saved state. Uses a fabricated `modes/frosted/blur` memo (KI-02) |

### Hermetic but not in the hook

| Check | Asserts | Note |
|---|---|---|
| `check-apply-lifecycle.py` | committing a live preview from the settings window | passes; add to the hook |
| `check-overview-blur.sh` | overview blur lifecycle regression fixture | passes; add to the hook |

### Live: humans only

| Check | Asserts |
|---|---|
| `check-preview.sh` | `aura-glass-preview` never leaves a memo different from what it found. Runs the real `install_css`/`apply_*` on the installed state |
| `check-shots.py --mode glass\|solid [--accept\|--list]` | screenshot diff of a `tools/preview.sh` run against the accepted baseline |
| `check-moga-cursors.sh` | Moga variant selection and checksum handling are fixture-based, but its last step runs `install.sh --settings-only --dry-run` against the real `HOME` and fails without an install there |
| `preview-extensions.py` | which extensions the preview shell actually loaded |
| `gpu-sample.py`, `gpu-live.sh` | GPU cost on the real session |

---

## Coverage gaps

These are known holes, each tied to a bug in [KNOWN-ISSUES.md](KNOWN-ISSUES.md).
Proposed checks are in [CONSISTENCY.md](CONSISTENCY.md) §5.

- incremental Apply → drawer → next full run (KI-01)
- mode switch on an existing install, all blur components (KI-03)
- adaptive active/restore from a real Performance install (KI-02)
- defaults and recommendations shared by the GUI, both wizards and the installer (KI-05)
- a fresh `--glass-mode frosted` resolving the same level as a flagless run (KI-18)
- uninstall covering every installed path (KI-07)
- GUI imports covered by the toolkit probe (KI-04)

---

## Writing a new check

Only when one is asked for (new files under `tools/` need the maintainer's
OK). When you do write one:

- Take `REPO_ROOT` from the script's own path.
- Never touch the real `HOME`, dconf or network. Use a fixture `HOME`, a temp dir, stubs first on `PATH`, or `--dry-run`.
- Exit non-zero naming the file and line or key that disagrees.
- Add it to `tools/hooks/pre-commit` with a comment saying what class of mistake it catches that nothing else does.


## Code-only blur lifecycle regressions

`python3 tests/check-performance.py` covers the Packages page's empty system
group. `python3 tests/check-bms-patches.py /path/to/blur-my-shell-clone` applies
Aura's three patches to the pinned upstream source in a temporary directory
and exercises window tracking, selective list refresh, effect and signal
cleanup, cancellation, focus restoration, popup toggles and notification
corners. See [tests/README.md](../tests/README.md). Set `BMS_TEST_SOURCE` to run
patched-source checks from the commit hook. The tests never fetch or access
the running desktop.

The optimization retains existing pipelines when list/scope edits leave a
window's blur eligibility unchanged. Pipeline changes still rebuild effects.
No preset, blur strength, opacity, radius, pipeline definition or artifact
handling default changes. Rendering and actual CPU/GPU improvement still need
live validation; fixture allocation counts are not frame-rate measurements.
