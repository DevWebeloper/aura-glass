# Adaptive Performance and Appearance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development for independent implementation tasks. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reversible adaptive blur profiles, context-aware Appearance controls, clearer extension package names, and two reinstall actions without including Moga cursors.

**Architecture:** A dedicated GNOME Shell extension supplies the top-bar profile control and focused-fullscreen signal. A standard-library user service reduces only the resolved live blur through an installer-owned transient path; GTK stays a thin frontend for installer-owned selections and repair commands.

**Tech Stack:** Bash, Python standard library, GJS, GTK4/libadwaita, dconf/GSettings, systemd user units.

**Spec:** [2026-09-15-adaptive-performance-design.md](../specs/2026-09-15-adaptive-performance-design.md)

## Global Constraints

- Preserve the normal installer resolver and the user's saved blur/profile values.
- Do not add Moga cursors or touch the current cursor asset pipeline in this batch.
- Do not edit `docs/TESTING.md`, any `tools/check-*` file, or any test file; do not run tests or check commands.
- Preserve all pre-existing untracked files, including contributor documentation.
- Do not hand-edit generated live theme files; finish with the repository-required `./install.sh --settings-only -y` deployment.
- Do not commit, publish, install external dependencies, alter upstream pins, reboot, or log out.

---

### Task 1: Add the transient adaptive blur backend

**Files:**
- Create: `tools/aura_glass_adaptive.py`, `bin/aura-glass-adaptive`, `systemd/aura-glass-adaptive.service`
- Modify: `install.sh`, `lib/steps-apply-plan.sh`, `lib/steps-dconf.sh`, `lib/steps-integration.sh`

**Interfaces:**

```text
aura-glass-adaptive profile auto|full|performance
aura-glass-adaptive refresh
install.sh --settings-only --incremental --adaptive-blur active|restore --yes
```

- [x] Add private `--adaptive-blur active|restore` parsing and an incremental
  action that calls the existing blur-strength writer only.
- [x] Resolve the normal mode/memo value before deriving the active value;
  active writes `max(25, normal / 2)`, restore writes normal. Add a transient
  writer guard so neither action changes the normal blur-strength memo.
- [x] Create an adaptive worker that reads the profile memo, battery sysfs,
  optional DRM `gpu_busy_percent`, and the Shell D-Bus fullscreen method.
  Model Auto, Full Glass, and Performance as explicit states with 80/65 GPU
  hysteresis and a sustained transition gate.
- [x] Write `active` and `reason` only after a successful transition. Use the
  operation helper around the installer command, never around the monitoring
  loop. Treat unavailable hardware/D-Bus as no trigger.
- [x] Install/reconcile the launcher, worker, and user service through a new
  integration function. Enable/start only in a graphical user session and
  disable the old unit cleanly when the feature is unavailable.

### Task 2: Add a dedicated adaptive Shell extension and lifecycle ownership

**Files:**
- Create: `extensions/aura-glass-adaptive@aura-glass.local/extension.js`, `extensions/aura-glass-adaptive@aura-glass.local/metadata.json`
- Modify: `lib/steps.sh`, `lib/steps-extensions.sh`, `bin/aura-glass-ext`, `uninstall.sh`

**Interfaces:**

```text
io.github.DevWebeloper.AuraGlass.Adaptive1.GetFullscreen() -> (b fullscreen)
io.github.DevWebeloper.AuraGlass.Adaptive1.FullscreenChanged(b fullscreen)
```

- [x] Build a `PanelMenu.Button` with the three profiles, a profile-appropriate
  symbolic icon, and active/reason status text loaded from Aura Glass state.
- [x] Track the focused Meta window and emit only changes to its fullscreen
  state. All subprocess calls from menu actions use asynchronous GJS APIs.
- [x] Add the extension as an Aura-owned core helper but deliberately keep it
  out of solid-mode stand-down so the panel menu can restore glass. Make its
  install, enable, catalogue description, and uninstall ownership explicit.
- [x] Ensure a missing extension or D-Bus owner degrades to no fullscreen
  trigger instead of failing the service or blocking the panel.

### Task 3: Make Appearance controls contextual and rename package presentation

**Files:**
- Modify: `gui/aura_glass_settings.py`, `gui/aura_glass_setup_wizard.py`, `install.sh`, `README.md`

**Interfaces:**

```python
def _refill_contextual_choice(row, options, current, key): ...
```

- [x] Generalize the existing dependent icon-colour row rather than adding a
  second resolver. Icon family changes refill colour choices; cursor and
  titlebar rows refresh their enabled/current context from their metadata.
- [x] Preserve `keep`/`original` behavior, current cursor-size independence,
  and installer flag emission. Do not add any Moga value or cursor download.
- [x] Change user-facing package labels and descriptions to Core, Minimal, and
  Complete Experience in the settings app, GTK setup wizard, terminal wizard,
  help, and README. Keep legacy command-line flags and underlying arrays
  unchanged so saved installations retain their membership.

### Task 4: Add the two Update repair actions and deploy the finished change

**Files:**
- Modify: `gui/aura_glass_settings.py`, `lib/steps-gui.sh` only if installed helper ownership needs updating

**Interfaces:**

```text
Reapply settings: install.sh --settings-only -y
Full reinstall with settings app: install.sh --force --gui --yes
```

- [x] Add a permanently visible Repair installation group to Updates with
  separate buttons, clear scope copy, running-state interlocks, and log/status
  feedback consistent with the existing update operation.
- [x] Run Reapply settings through the existing in-window streamed command
  path. Launch Full reinstall with settings app in a real terminal so any
  root-owned rounded-blur prompt remains usable; do not use `--full`.
- [x] Keep a pending release update's existing pull-and-full-install behavior
  unchanged.
- [x] Review the changed source manually for flag spelling, installed-path
  ownership, Shell API compatibility, and user-facing labels. Do not run tests
  or check commands.
- [x] Apply the finished repository change to the live desktop with
  `./install.sh --settings-only -y`. Report the command outcome and any
  runtime state that cannot be confirmed without the prohibited test work.
