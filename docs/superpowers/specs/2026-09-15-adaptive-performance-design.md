# Adaptive performance and appearance controls

Status: approved for implementation on 2026-09-15.

## Outcome

Aura Glass gains a reversible adaptive-performance mode with a GNOME top-bar
profile menu. It reduces blur while the focused window is fullscreen, while a
laptop is on battery, or while a supported GPU reports sustained high load,
then restores the user's normal resolved blur level. Appearance gains
context-aware selectors, extension packages receive clearer names, and Updates
gets two repair actions.

Moga cursors are explicitly deferred from this work.

## Contracts

- Keep `install.sh` and its `apply_*` functions as the only resolver of a
  normal blur setting. Adaptive code may request a transient application, but
  may not overwrite the user's blur memo or a per-mode memo.
- Target GNOME Shell 48, 49, and 50; use GJS in the Shell and only Python's
  standard library outside the existing GTK application.
- The top-bar control remains enabled in solid mode so that a user can select
  Full Glass or Auto without first finding the settings application.
- `Auto`, `Full Glass`, and `Performance` are the three profiles. Auto reacts
  to the three triggers; Full Glass never downshifts; Performance keeps the
  reduced blur active. Auto is the installed default.
- A fullscreen trigger means the focused GNOME Shell window reports
  fullscreen. It deliberately does not try to guess whether an application is
  a game.
- GPU use is optional. Read a supported DRM `gpu_busy_percent` source when
  present; an unavailable source is no trigger, not an idle reading. Enter at
  80 percent and clear below 65 percent, with a short sustained/debounce gate
  so a one-sample spike does not toggle the desktop.
- The reduced blur is one half of the resolved normal blur strength, bounded by
  the existing minimum of 25. This preserves a visible but substantially
  lighter effect without inventing a second visual profile.
- State files under `$CONF_DIR/adaptive-performance/` record only runtime
  active/reason state. `$CONF_DIR/adaptive-profile` records the user's selected
  profile. Neither records a replacement blur baseline.
- Add private installer plumbing for an adaptive transient apply. It must use
  the existing `apply_blur_strength` writer with memo writes disabled and must
  be classified as a narrow incremental action.
- The background worker uses `aura-glass-operation run -- ...` only around a
  state transition. It never holds the writer lock while monitoring hardware
  or GNOME Shell.
- The Appearance controls remain a frontend for installer-owned choices. A
  shared data-driven selector updates dependent choices and context text; it
  must not duplicate icon/cursor resolution rules.
- Package presentation becomes **Core** (the existing six curated optional
  extensions plus the foundation), **Minimal** (foundation only), and
  **Complete Experience** (all optional extensions). Existing flags, arrays,
  and saved selections remain compatible.
- Updates exposes **Reapply settings** running exactly
  `install.sh --settings-only -y`, and **Full reinstall with settings app**
  running `install.sh --force --gui --yes` in a real terminal. The latter is a
  reinstall of the current selection, not `--full`, which would change it.
- Do not edit `docs/TESTING.md`, any test file, or run any test/check command.
  Do not claim automated verification for this change.

## Components and flow

1. A dedicated Shell extension owns the panel menu and publishes the focused
   fullscreen state over a small session D-Bus interface. Menu actions start
   the installed adaptive command asynchronously, never block GNOME Shell, and
   immediately reflect the chosen profile.
2. A systemd user service runs a standard-library worker. It samples battery
   state and optional GPU load, reads fullscreen state from the extension, uses
   a reducer/debounce state machine, and calls the private transient installer
   action only when the desired state changes.
3. `install.sh` resolves the normal profile first. For an adaptive transition
   it derives the temporary strength from that normal value and calls the
   existing dconf writer without persisting it. On restore it resolves and
   writes the normal value the same way.
4. The settings app uses a common contextual selection helper for icons,
   cursors, and titlebar controls. Icons continue to refill colour choices;
   cursor and titlebar rows update their available/current explanatory content
   from the same metadata rather than carrying independent resolution code.
5. Installation and uninstallation own every new command, worker, unit, and
   extension. A settings-only live apply installs/reconciles those artifacts.

## Boundaries

This does not add cursor assets, change visual tokens, auto-install updates,
terminate fullscreen applications, tune GPU thresholds per device, or add a
new public dependency. Hardware state that cannot be observed is reported as
unavailable and leaves the normal profile intact.
