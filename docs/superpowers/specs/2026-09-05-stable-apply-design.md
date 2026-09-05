# Stable application from login to GUI edits

Status: proposed implementation design, prepared at the user's request for a coding handoff. No runtime changes have been made by this planning task.

## Outcome

Keep Aura Glass looking the same while making changes predictable: one writer at a time, complete CSS files, fewer unnecessary reloads, recoverable previews, and login helpers that respect the latest user choice. No benchmarks, GPU sampling, stress tests, or numerical speed claims.

The implementation plan is [2026-09-05-stable-apply.md](../plans/2026-09-05-stable-apply.md).

## Current evidence

Inspected working tree based on commit `502a795`, 2026-09-05. These are code observations and failure scenarios, not reproduced live failures or measured performance results.

| Location | Observation | Consequence to address |
|---|---|---|
| `gui/aura_glass_settings.py`, `_fire_preview` | Starts a subprocess without checking whether `_preview_proc` is already occupied. | Debouncing alone does not prevent overlapping slow previews; the stored process reference can be replaced. |
| Same file, `_on_apply` | Deletes `preview-backup` before the installer reports success, even before an in-flight preview completes. | Failure can lose the recovery point. |
| Same file, `_on_close_request` | Runs synchronous revert with a 15-second timeout and does not wait for the preview writer first. | The UI can block and revert can overlap a writer. |
| Same file, startup preview recovery | Shows a successful recovery toast before the subprocess result arrives. | Feedback can claim recovery that failed. |
| `bin/aura-glass-preview`, `cmd_revert` | Resets the entire Blur My Shell subtree and restores old memos. No shared writer lock or ownership revision. | Another writer's newer settings can be overwritten. |
| `bin/aura-glass-apply`, `apply` | Opens each generated target with `w` even if output is identical. | Readers can encounter incomplete output; identical applies cause filesystem changes. |
| Same file, final reload | Toggles User Themes and sleeps one second whenever its current theme is nonempty. | Unchanged CSS and GTK-only changes can still trigger a Shell reload. |
| `install.sh`, settings-only branch | Reloads the preset, installs CSS, reapplies global settings, refreshes the GUI, and reconciles three integrations. | A small GUI edit has effects outside its setting family. |
| `lib/steps-dconf.sh`, `apply_gsettings` | Writes `color-scheme=prefer-dark` on every call. | An unrelated edit can undo the user's subsequent light-mode choice. Preserve full-install semantics; narrow ordinary edits. |
| `lib/steps-integration.sh` | Copies unit files, daemon-reloads, and restarts icon/panel services on ordinary applies. | A tint edit can restart the panel helper and trigger another rebuild. |
| `bin/aura-glass-panel-blur`, `rebuild` | Tests enabled state before sleeping, then writes false/true; handles each monitor event serially. | Event bursts queue rebuilds; a choice made during the wait can be overwritten. |
| `bin/aura-glass-icon-sync` | Reads icon base once at startup. | Removing unnecessary service restarts also requires refreshing the base when its memo changes. |
| `extensions/aura-glass-blur@aura-glass.local/extension.js`, `_toggleBlur` | Writes both lists and memos directly. | Locking the installer alone cannot coordinate all project-owned writes. |

Useful foundations already exist: canonical flag resolution, per-mode memos, shared `apply_*` functions, ordered CSS snippets, uninstall backups, event-driven services, preview debouncing, an apps-only preview path, and GUI pending-change labels. Extend these; do not rebuild them.

## Approaches considered

1. **Patch the orchestration in place — recommended.** Keep Bash as the resolver, add small standard-library helpers for coordination, and retain the current GUI. Deliver the reliability fixes before introducing an incremental path.
2. **Only adjust sleeps and slider delays.** Smaller diff, but leaves overlapping writers, truncated files, lost snapshots, and repeated installation work. Insufficient for this request.
3. **Replace the installer with an always-running settings daemon.** Could centralize all writes, but creates a new service/API/migration obligation. Unnecessary for a theme that already has a working command interface.

## Contracts

- GNOME Shell 48 / 49 / 50 remain the target; preserve the existing Wayland preference and distro support.
- `install.sh` and the existing `lib/` functions remain the sole flag/memo/default resolver. An action selector decides which existing functions run; it does not resolve values.
- Python dependencies remain the standard library plus the existing optional PyGObject GUI stack. Helpers needed without the GUI use the standard library.
- Preserve current visual tokens, numeric rationale comments, cascade order, legacy aliases, dry-run behavior, and uninstall backups.
- Retain `--settings-only` as the complete local refresh. A new opt-in `--incremental` modifier gives GUI edits a narrow path and falls back to the complete path for modes, migrations, or unclassified flags.
- Coordinate installer, preview, CSS apply, uninstall, and the first-party window-menu writer. Never block GNOME Shell's main loop waiting for a lock.
- Preview scheduling allows one active operation and one replaceable pending candidate. Apply, Revert, and Close take precedence over pending preview work.
- Preview recovery belongs to the command backend. GUI code requests operations and displays their results; it does not delete transaction directories.
- Publish each CSS target through a same-directory temporary file and atomic replacement of the resolved regular-file destination. Preserve symlinks and file mode. Skip replacement when bytes match. This is per-file atomicity, not an atomic transaction across dconf and four files.
- Keep a recovery record until success. Recovery changes only the exact files/keys owned by the operation and detects conflicting newer edits. Never reset the complete `/org/gnome/` database.
- A successful Shell reload is reported only after the reload writes succeed. A missing session/schema yields “saved; reload pending/unavailable”, not “already applied”.
- Login helpers stay event-driven. No installer run, polling loop, asset download, or automatic update installation at login.
- No automatic logout, reboot, application termination, sudo operation, benchmark, or GPU sampling during this work.

## Features included with the reliability work

1. **Preview recovery:** reopen after an interrupted preview and see whether it was restored or needs attention; keep recovery data on failure.
2. **Explain Apply:** expand the existing pending popover with old/new values and the backend-selected actions; distinguish live Shell changes from GTK changes needing an app restart.
3. **Quiet apply:** identical output causes no target rewrite, theme reload, service restart, or icon-cache rebuild. This is a correctness property checked with fixtures, not a timed benchmark.

## Later feature candidates

These are ideas, not implementation requirements for this batch:

- **Named looks:** save a user's full resolved theme choices as “Night Glass”, “Clear Day”, or a custom name; reuse the resolver on load. Versioned data only, no shell commands in imported profiles.
- **Focus look:** a manual recipe using existing blur/transparency controls to reduce visual distraction. Do not call it faster without evidence and do not invent new blur constants.
- **Try for 20 seconds:** Keep/Revert confirmation built on backend-owned recovery; expiry must work if the GUI closes before this can be advertised as automatic safety.
- **Follow system appearance:** opt-in light/dark recipes, preserving the existing icon-sync behavior and manual overrides. No automatic battery-based or application-based switching in the first version.

## Delivery boundaries

Ship the reliability foundation independently. Add incremental apply only after concurrency/recovery checks pass. Add the small GUI feedback features last. Do not undertake a CSS redesign, rewrite the 6,000-line GUI, retune shaders, update pinned upstreams, or combine this with release work.

Validation is functional: fixture files, stubbed commands, controlled callback ordering, interrupted-operation recovery, existing project checkers, then one live settings-only application and a small manual GUI/session checklist. Report untested login or monitor transitions explicitly.
