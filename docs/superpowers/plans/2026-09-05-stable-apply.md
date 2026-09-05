# Stable Apply Implementation Plan

> **For agentic workers:** Use `superpowers:executing-plans` to implement this plan task by task. Work sequentially; this handoff does not request subagents. Check off completed steps and record verification. Re-read `CLAUDE.md` first.

**Goal:** Make login helpers and GUI theme changes reliable, recoverable, and free of unnecessary application work without running benchmarks.

**Architecture:** Preserve the Bash resolver and existing `apply_*` implementations. Introduce a small operation coordinator, serialize preview lifecycle transitions, publish only changed CSS, reconcile installation artifacts by content, and add an explicitly narrow incremental path after the foundation passes.

**Tech stack:** Bash, Python standard library, existing PyGObject/GTK4/libadwaita, GJS, dconf/GSettings, systemd user units.

**Spec:** [2026-09-05-stable-apply-design.md](../specs/2026-09-05-stable-apply-design.md). Read the evidence table and contracts before coding.

## Model and execution recommendation

Use **GPT-5.6 Terra, high reasoning**, for the whole implementation. This is an engineering recommendation based on the shared state and recovery complexity. Official documentation describes [Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra) as balancing intelligence and cost and [Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna) as optimized for cost-sensitive workloads; those descriptions are not a measured comparison on this repository.

Luna is a reasonable later choice for a tightly specified documentation update, label change, or isolated fixture once the interfaces are settled. Do not split ownership of the transaction protocol between models at the same time.

Suggested execution prompt:

```text
Read CLAUDE.md, then docs/superpowers/specs/2026-09-05-stable-apply-design.md
and docs/superpowers/plans/2026-09-05-stable-apply.md. Implement the plan
sequentially, beginning with Task 1. The plan's runtime changes and scoped
functional checks are authorized. Do not run benchmarks, GPU sampling,
stress tests, automatic logouts, or unrelated refactors. Preserve the
current appearance and all existing untracked files. Complete each task's
checks before moving on, update the checklist, and finish with the specified
live apply and honest validation report. Do not commit, publish, change
upstream pins, or add optional roadmap features unless I ask.
```

## Global constraints

- GNOME Shell 48 / 49 / 50 remain the target; preserve the existing Wayland preference and distro support.
- `install.sh` and the existing `lib/` functions remain the sole flag/memo/default resolver.
- Python dependencies remain the standard library plus the existing optional PyGObject GUI stack.
- Preserve current visual tokens, numeric rationale comments, cascade order, legacy aliases, dry-run behavior, and uninstall backups.
- Never hand-edit generated theme files. Use repository source changes and the supported apply path.
- No automatic logout, reboot, application termination, sudo operation, benchmark, or GPU sampling during this work.
- Do not run `tools/gpu-live.sh`, `tools/gpu-sample.py`, or indiscriminate `tools/check-*` loops. `check-preview.sh` changes the live desktop; run it only at the final bounded validation step after inspecting its cleanup.
- Existing untracked files on the planning date: `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, and `docs/{ARCHITECTURE,CONFIG-REFERENCE,DEVELOPING,GUI,README,RELEASING,TESTING}.md`. Do not claim, stage, replace, or remove them as your work. Recheck status because this list may change.
- Keep this plan and spec available if using a worktree. They and the contributor instructions may not yet be committed, so a new worktree will not automatically contain them. Prefer the user's current checkout with path-scoped edits when it still has no conflicting tracked modifications.

## Task 1: Serialize GUI previews and make closing asynchronous

**Modify:** `gui/aura_glass_settings.py` (`_schedule_preview`, `_fire_preview`, `_on_preview_set_done`, `_preview_revert`, `_on_close_request`, `_on_apply`, startup recovery); `lib/steps-gui.sh` to install the new module.

**Create:** `gui/preview_queue.py`, `tools/check-preview-queue.py`.

**Interface:** A standard-library-only `PreviewQueue` controls sequencing, not settings or subprocess construction:

```python
class PreviewQueue:
    def __init__(self, launch): ...
    def request_preview(self, argv): ...
    def request_terminal(self, kind, argv): ...  # kind: apply or revert
    def finish(self, generation): ...
# launch(kind: str, argv: tuple[str, ...], generation: int) -> None
# request methods return None. finish releases only the matching generation.
```

- [ ] Add deterministic checks that hold fake operations open. No real desktop or wall-clock timing. Required example:

```python
started = []
q = PreviewQueue(lambda kind, argv, gen: started.append((kind, argv, gen)))
q.request_preview(("A",))
q.request_preview(("B",))
q.request_preview(("C",))
assert len(started) == 1
q.finish(started[0][2])
assert [entry[1] for entry in started] == [("A",), ("C",)]
q.finish(started[0][2])  # a stale callback cannot finish C
assert len(started) == 2
```

- [ ] Cover these additional sequences: preview A → pending B → Apply drops B; A → Revert drops B; disabling preview during A schedules revert; subprocess creation failure releases the slot exactly once. Once a terminal request is queued, ignore preview requests until it completes. Reject duplicate terminal requests through disabled UI controls.
- [ ] Run `python3 tools/check-preview-queue.py`; confirm the new checks expose the missing queue before implementation.
- [ ] Implement one active request, one replaceable pending preview, and one terminal request. Allocate monotonically increasing generations before launching. Capture `fast/apps-only` metadata per launch, never in a field that a later request can overwrite.
- [ ] Keep existing 200/400 ms debounce values. Debounce controls when a candidate is offered to the queue; it does not control whether processes may overlap.
- [ ] Keep all GTK mutations on the main loop. Use `stream_command` for revert. On Close, retain the window and return `True` while work finishes; ask the existing unsaved-changes dialog before choosing Apply/Discard. Discard waits for the active preview then reverts; Cancel leaves the window usable. Destroy only after the requested successful terminal operation.
- [ ] Show recovery-success feedback inside the successful completion callback. Failure leaves the window and recovery action visible. Do not report a failed preview as successfully active.
- [ ] Install `preview_queue.py` beside the installed GUI file, and retain checkout imports. Run the queue checker and `python3 tools/check-gui-flags.py`.

**Acceptance:** Even callbacks delivered out of order cannot start a second writer or close over an unfinished revert. This task fixes GUI sequencing; cross-process coordination arrives in Task 2.

## Task 2: Coordinate all project writers and own preview recovery in the backend

**Create:** `bin/aura-glass-operation` (Bash launcher), `tools/aura_glass_operation.py` (standard-library coordinator), `tools/check-operation-recovery.py`.

**Modify:** `install.sh`, `uninstall.sh`, `bin/aura-glass-preview`, `bin/aura-glass-apply`, `lib/steps-gui.sh`, `lib/steps-css.sh`, `gui/aura_glass_settings.py`, `extensions/aura-glass-blur@aura-glass.local/extension.js`, `lib/steps-extensions.sh` (helper installation), `tools/hooks/pre-commit` (new Python helper syntax only if needed).

**Command contract:**

```text
aura-glass-operation run -- COMMAND [ARG...]
aura-glass-preview commit --session ID -- INSTALLER [ARG...]
aura-glass-preview revert [--session ID]
aura-glass-preview status --json
aura-glass-operation app-blur --wm-class CLASS --enabled 0|1
```

Existing `preview begin|set|apps|revert|status` remain accepted. `begin` emits an owner/session ID for new callers. New GUI calls attach that ID to mutations. `commit` is a backend-owned apply handoff, not “delete snapshot”: it runs the installer, keeps recovery state until success, and restores on failure where ownership is unchanged.

- [ ] Build fixtures under `tempfile.TemporaryDirectory()`. Supply every subprocess with a child-only `env` pointing HOME/config/cache to that fixture and stub `dconf`, `gsettings`, and system commands. Never export a replacement HOME for the user's shell, and never rely on HOME alone to isolate the session bus.
- [ ] Add controlled two-process tests with pipe/file barriers, not sleep-based timing: A holds the writer lock, B cannot enter, releasing A permits B. Include nested installer → apply, process failure, and dry-run not creating a lock/recovery directory.
- [ ] Implement an advisory lock using `fcntl.flock` in the standard-library helper at `$HOME/.cache/aura-glass/operation.lock`, independent of the theme config directory that uninstall can remove. The launcher runs the Python helper installed under `~/.local/share/aura-glass/`, falling back to the checkout only when called from the checkout. Install this helper before commands that need it; standalone installed apply must continue working if the checkout disappears.
- [ ] Nested commands inherit a real locked descriptor using `pass_fds`; validate it against the expected lock file with `fstat/stat` before treating it as inherited ownership. An environment boolean alone must not bypass locking. Use a bounded 30-second lock wait with “another theme operation is running” on expiry. Forward termination and wait for the child so a lock is not released while a writer continues.
- [ ] Acquire the installer lock after parsing dry-run/help but before `migrate_legacy_names` and the first memo resolution read. Do not lock only `install_css`: resolution reads and mode seeding also participate in the operation. Wrap uninstall before its first mutation. Preview begin/set/apps/revert/commit and direct CSS apply use the same lock.
- [ ] Construct each snapshot in a temporary sibling directory and publish it only when all files/key reads succeed. Store schema version, session ID, committed revision, source checkout identity, exact owned paths/keys, file existence, dconf unset-versus-explicit values, and pre-operation contents. Retain existing uninstall `.orig` and `.absent` records untouched.
- [ ] Snapshot the owned settings before the first preview mutation. During preview, record the last values written as well as the baseline. On revert restore only keys this preview touched and only if their current values still match that last write. Conflicting newer state stays intact and recovery reports the conflict. Do not use `dconf reset -f "$BMS/"` for new snapshots. Handle old snapshot format separately: preserve it and offer an explicit recovery route rather than silently treating it as a new revision.
- [ ] At Apply, retain the original pre-preview recovery record, stop pending preview work, and let backend `commit` invoke the canonical installer under the same operation ownership. Capture any additional owned keys/files that the installer will change before changing them. On failure, restore recorded owned state; if any restore fails retain the journal and report partial recovery. On success publish the new revision and only then remove the preview record.
- [ ] Replace GUI `shutil.rmtree(preview-backup)` and marker deletion with this command contract. Guard startup and close recovery with the session/revision checks. A later CLI apply cannot be undone by an old GUI callback.
- [ ] Route `_toggleBlur` through an asynchronous `Gio.Subprocess` call to `app-blur`. Move its existing membership/wildcard semantics into that command's operation; reuse canonical `apply_app_blur` via a narrow Bash entry in `bin/aura-glass-preview` or a shared library function. The helper reads lists after acquiring ownership; the Shell must not precompute a stale whole-list replacement. Preserve wildcard-removal notifications, read the final state on completion, and report failure without a false checkmark. No synchronous lock wait inside GNOME Shell.
- [ ] Add interruption checks: failed begin publishes no active snapshot; failed commit retains or successfully restores baseline; repeated revert is harmless; older session cannot revert a newer commit; unrelated dconf key survives revert; an app-menu edit during preview is either serialized after a safe preview teardown or rejected with a clear busy message. Do not silently merge an ambiguous conflict.
- [ ] Run `python3 tools/check-operation-recovery.py`, `python3 tools/check-preview-queue.py`, and `bash tools/check-app-blur-lists.sh`.

**Acceptance:** All project-owned theme writers participate; failures leave an honest recovery record. External tools do not honor our lock, so conflict detection remains necessary. Do not claim a globally atomic desktop transaction.

## Task 3: Publish complete CSS and reload Shell only when needed

**Modify:** `bin/aura-glass-apply`, `lib/steps-css.sh`; `tools/aura_glass_operation.py` only for shared publication/recovery primitives.

**Create:** `tools/check-apply-publication.py`.

**Interface:** Retain default text output and add `aura-glass-apply --json` with this result shape:

```json
{"schema_version":1,"changed_targets":[],"shell_reload":"unchanged","gtk_restart_required":false}
```

Allowed `shell_reload` values: `unchanged`, `reloaded`, `unavailable`, `failed`. Nonzero exit on file publication or attempted reload failure. Missing optional targets retain the existing skip behavior and are described in result details.

- [ ] Add fixtures for four targets, one with user GTK3 content outside the marked block; one symlinked GTK target; `.orig`, `.absent`, and `.stood-down` cases; a missing optional snippet; and legacy markers. Stub all live settings commands.
- [ ] Add a no-op check that runs the real script twice and compares target bytes plus `st_mtime_ns` and counts of fake reload commands. Require zero target replacements and reloads on the second run. Change only a GTK snippet and require no Shell reload.
- [ ] Preserve the complete flattening/accent/cascade implementation and its comments. Build every candidate in memory or staging files before publishing any target. Do not substitute the pristine backup as the render baseline on every run: that would discard upstream/user changes made after installation.
- [ ] Replace truncating writes with a helper following this core algorithm, including cleanup on failure:

```python
# Core algorithm; integrate existence/mode handling and rollback with Task 2.
destination = target.resolve(strict=True)
old = destination.read_bytes()
if old == candidate:
    return False
fd, temporary = tempfile.mkstemp(prefix=".aura-glass-", dir=destination.parent)
try:
    with os.fdopen(fd, "wb") as stream:
        os.fchmod(stream.fileno(), stat.S_IMODE(destination.stat().st_mode))
        stream.write(candidate)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, destination)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
return True
```

- [ ] Preserve symlinks, reject unsupported non-regular destinations without replacing them, and handle originally absent files through the established stand-down/revive rules. Stage all candidates first; on a later publish failure use the operation journal to restore already-published files. Document per-file atomicity and recoverable cross-file publication separately.
- [ ] Apply unchanged-content suppression to stand-down restores and stripping as well. Keep the move-aside behavior for files recorded absent.
- [ ] Reload only after a changed active Shell target is published. Retain the existing one-second reload handshake initially; remove redundant reloads before changing its timing. If interrupted after clearing the theme key, restore the captured name only while it remains ours to restore; do not overwrite a newer choice.
- [ ] Add an explicit `--force-reload` option for the existing GUI Re-apply action, so a deliberate repair can reload unchanged files. Ordinary Apply/preview does not force. Do not reload an unrelated theme just because its name is nonempty.
- [ ] Run `python3 tools/check-apply-publication.py`, `bash tools/check-styling-off.sh`, `bash tools/check-cascade.sh`, and `bash tools/check-tokens.sh`.

**Acceptance:** Readers see complete files, unchanged output stays untouched, GTK-only edits avoid Shell reload, and repair remains available.

## Task 4: Reconcile helper installation without restarting unchanged services

**Modify:** `lib/common.sh`, `lib/steps-integration.sh`, `lib/steps-gui.sh`, `lib/steps-css.sh`, `bin/aura-glass-icon-sync`.

**Create:** `tools/check-integration-reconcile.py`.

**Interfaces:**

```bash
install_if_changed SOURCE DEST MODE  # success=0 even when unchanged
# Sets INSTALL_CHANGED=0|1; uses run and existing backup policy.
# It compares bytes AND required mode, not just timestamps.
```

- [ ] Add stub-command fixtures recording install/copy operations, icon-cache regeneration, daemon-reload, enable/start/restart/stop. Require a second reconciliation with identical inputs to generate none of those mutations.
- [ ] Implement `install_if_changed`; route every new mutation through `run`. Do not use a nonzero “unchanged” result with `set -e`. Preserve `backup_once` for owned overwritten files; first-install backups are not a per-apply journal.
- [ ] Apply it to installed commands, GUI modules/icon/desktop entry, service/timer units, and repo-path memo. Build generated desktop-entry bytes before comparing. Rebuild the hicolor cache only if its installed icon actually changed.
- [ ] Accumulate unit changes and issue at most one daemon-reload at the reconciliation boundary. Enable/start a requested missing or inactive unit; restart an active service only if its executable or unit changed. Disable/remove only an integration whose desired state changed to off. Keep update-check reconciliation from forcing a new network check on an unrelated GUI edit.
- [ ] Refresh the icon base inside `apply()` rather than caching it forever at process startup. Preserve environment override precedence, legacy lookup, `keep`, installed-variant fallback, and existing same-value avoidance. On an icon pack change, call the existing `--once` path for immediate correction without restarting an otherwise unchanged daemon.
- [ ] Make each icon correction participate in the operation lock through `aura-glass-operation run -- aura-glass-icon-sync --once`; the `--once` branch recognizes the validated inherited descriptor from Task 2 and runs the correction directly. The long-running monitor never holds the lock. Re-read the pack and appearance after acquiring it, so a queued event cannot overwrite a newer installer choice. Include icon correction versus Apply in the controlled concurrency fixture.
- [ ] Do not perform this artifact reconciliation during ordinary preview ticks. Preview renders candidate CSS using the already-installed helper; it does not reinstall itself or the GUI.
- [ ] Run `python3 tools/check-integration-reconcile.py`, `bash tools/check-update-check.sh`, and `python3 tools/check-update-channel.py`.

**Acceptance:** A tint change cannot restart the panel helper or rebuild the GUI icon cache. A real helper update or changed icon selection still takes effect in the current session.

## Task 5: Coalesce monitor events and honor current blur state

**Modify:** `bin/aura-glass-panel-blur`, `systemd/aura-glass-panel-blur.service`, `lib/steps-integration.sh`.

**Create:** `tools/aura_glass_panel_blur.py`, `tools/check-panel-blur-events.py`. Install the Python worker alongside the operation worker; keep the public `bin/` entry a Bash launcher so the existing hook's shell syntax check remains valid.

**Interface:** Worker consumes `gdbus monitor` as today, with a standard-library selector/event loop, one settle deadline, and the operation lock only during a short rebuild. Preserve `AURA_GLASS_BLUR_SETTLE` and the legacy alias; default remains 3 seconds.

- [ ] Test the event reducer with an injected clock and fake settings/lock functions. Required ordering:

```text
event(0), event(1), event(2), advance(5) -> exactly one rebuild
event(0), user_disables_blur(1), advance(3) -> zero writes
event(0), switch_to_solid(1), advance(3) -> zero writes
event(0), operation_busy(3), event(4), operation_free(7) -> one pending rebuild
```

- [ ] Start observing monitor events before scheduling the login rebuild. Each event replaces the settle deadline; queued lines do not each get their own blocking sleep. A busy operation leaves one pending rebuild and never accumulates a work queue.
- [ ] At the deadline acquire the shared short-operation lock, then re-read the panel key, styling-off/no-blur state, and relevant integration preference. Skip if no longer enabled. Keep readiness based on a working session service/key; do not invent an always-on installer at login.
- [ ] Retain the existing off/on rebuild handshake initially. Observe setting changes during its temporary-off interval: an external change different from the worker's own value cancels restoration. In-project Apply is serialized. Explicitly document the unavoidable ambiguity of an external repeated `false` write while the key is already false; do not claim ownership protection dconf cannot provide.
- [ ] On normal termination restore only a known temporary worker change when still owned, terminate/reap the monitor child, and release resources. Store enough short-operation recovery state before clearing the key to handle an interrupted rebuild on the next worker start. A missing bus exits with a useful message for the existing `Restart=on-failure` policy.
- [ ] Keep `PartOf=graphical-session.target`. Do not introduce a new permanent daemon beyond replacing this helper's internal event loop. Update obsolete comments about the removed twelve-second sleep only where this task changes behavior; preserve numeric rationale elsewhere.
- [ ] Run `python3 tools/check-panel-blur-events.py` and `python3 tools/check-integration-reconcile.py`.

**Acceptance:** Bursts collapse, disabled blur stays disabled, and ordinary GUI edits no longer initiate login-style rebuilds through unnecessary restarts.

## Task 6: Add conservative incremental Apply through the same resolver

**Modify:** `install.sh`, `lib/steps-dconf.sh`, `lib/steps-css.sh`, `gui/aura_glass_settings.py`, `README.md`; update relevant contributor docs only with path-scoped edits that preserve their existing content.

**Create:** `lib/steps-apply-plan.sh`, `tools/check-incremental-apply.py`.

**Interfaces:**

```text
install.sh --settings-only --incremental --yes [existing flags]
install.sh --settings-only --incremental --dry-run [existing flags]
```

`select_apply_actions` in the new library consumes the original typed flag names and the already-resolved variables, produces an ordered Bash `APPLY_ACTIONS` array, and never writes memos or resolves defaults. Capture original flags during parsing because mode loading reuses `*_EXPLICIT` as “settled” markers.

- [ ] Make a fixture trace checker recording invoked setting functions, dconf writes, CSS publication, and integration work. Run real flag parsing/resolution with stubbed effects. Compare final owned state with the full path for each supported narrow edit, while asserting unrelated user keys remain unchanged on the incremental path.
- [ ] Start with only the following closed action table. Any unlisted flag, a glass-mode transition, or a source/schema migration uses the full settings-only path. A union of known flag groups runs each action once in the existing dependency order.

| Typed flags | Existing work selected | Must not run |
|---|---|---|
| `--accent` | Narrow accent write plus existing accent-overrider handling and accent memo | CSS, core preset load, icon/panel restart, color-scheme write |
| `--cursor-size` | `apply_cursor_size` | CSS, core preset load, any service restart |
| `--window-buttons` | `apply_window_buttons` | CSS, core preset load, any service restart |
| `--app-blur-allow`, `--app-blur-block` | `apply_app_blur` with resolved current scope/window-blur values | CSS, core preset load, any service restart |
| `--app-tint-color`, `--shell-tint-color`, `--app-transparency`, `--no-app-transparency`, `--notification-opacity`, `--titlebar-button-style` | Existing CSS renderer with complete resolved settings; publish changed targets | core preset load, color-scheme write, helper restart |

- [ ] Extract the accent subsection from `apply_gsettings` into `apply_accent` called by both paths; preserve current full-install behavior. Do not copy the key/memo logic into the selector. Reuse existing specific functions for other narrow settings. Verify each actual CLI spelling against the current parser before adding it to the table.
- [ ] Record a successful source fingerprint covering resolver libraries, tokens, CSS/dconf inputs, and relevant helper sources. The fingerprint includes working-tree bytes, not only Git HEAD. If it differs or is absent, run the full path and publish the new fingerprint only after success. This preserves “pull/edit the repo, then Apply refreshes installation”.
- [ ] Keep ordinary `--settings-only -y` as the full local refresh. Initially route radius, blur strength, mode, icon/cursor/font pack, panel integration, and update settings through that path. Radius/blur pipelines are coupled and are not a safe place for guessed action pruning.
- [ ] Complete CSS generation still receives the full resolved state even when only one CSS flag changed. Avoid resetting installed snippets without replaying remembered radius/tint/opacity transforms. Task 3 suppresses unchanged final targets.
- [ ] Make GUI `_start_apply` add `--incremental` through backend `commit`; continue sending only changed user flags. Keep preview and committed apply ownership from Task 2.
- [ ] Extend `--dry-run` output with a concise action list and fallback reason. Dry-run creates no fingerprint, lock file, recovery snapshot, or memo. Add flag documentation. This modifier does not require a new setup-wizard question because it changes execution strategy, not a theme preference.
- [ ] Add `--plan-json`, accepted only together with `--settings-only --incremental --dry-run`, to return `{"schema_version":1,"actions":[],"fallback_reason":null}` on stdout with diagnostic text on stderr. Use the same selector; no alternate resolution code. The GUI requests this asynchronously for an expanded pending-details view, caches it for the current candidate/source revision, and ignores stale responses. Merely moving a slider must not spawn an extra planning process on every tick.
- [ ] Run `python3 tools/check-incremental-apply.py`, `python3 tools/check-gui-flags.py`, `python3 tools/check-wizard-flags.py`, `bash tools/check-glass-modes.sh`, and `bash tools/check-radius-preset.sh`.

**Acceptance:** Supported small edits avoid unrelated work and preserve GNOME appearance choices. Complex edits retain the proven full path. No action selection logic lives in the GUI.

## Task 7: Explain changes and expose recovery without adding a dashboard

**Modify:** `gui/aura_glass_settings.py` (`_sync_pending`, apply/recovery bar, result handling), `bin/aura-glass-preview`, `tools/aura_glass_operation.py`, `README.md`.

**Create:** `tools/check-apply-feedback.py`.

**Interfaces:** `preview status --json` is read-only and returns at least:

```json
{"schema_version":1,"state":"idle","session_id":null,"revision":0,"recovery_available":false,"conflicts":[]}
```

State values: `idle`, `previewing`, `applying`, `recovery-needed`. Per-operation result JSON contains the Task 3 CSS result, actual completed actions, failed action if any, and recovery result. Write JSON on a dedicated requested result path or dedicated output channel so progress text cannot corrupt it; do not parse human log phrases as state.

- [ ] Extend the current pending-change popover using `Settings.flags_against` and its existing label mapping. Show old → new values for scalar settings; show added/removed counts for app lists. Keep values presentation-only; backend dry-run/action output owns the execution summary.
- [ ] Add status text for “Preview queued”, “Applying”, “No changes needed”, “Saved; restart open GTK apps”, and “Recovery needs attention”. Display only states backed by a current operation result; a canceled/stale callback cannot overwrite a newer status.
- [ ] Provide “Restore previous preview” when recoverable state exists; use the backend revert contract. Disable it while another operation runs. Show conflicts without discarding the record. Distinguish this feature from a general multi-step Undo history, which is outside this batch.
- [ ] Keep the existing Re-apply button as explicit repair, using Task 3 `--force-reload`. If there is a preview session, serialize repair through its lifecycle instead of bypassing recovery.
- [ ] Add fake-result checks: success with GTK changes requests restart; dconf-only success does not; unavailable Shell reload does not claim Shell updated; failed recovery leaves its button; successful recovery clears it; stale generation cannot replace current status.
- [ ] Run `python3 tools/check-apply-feedback.py`, `python3 tools/check-preview-queue.py`, and `python3 tools/check-gui-flags.py`.

**Acceptance:** The user can understand what Apply did and recover a preview without reading a terminal log. No separate diagnostic daemon, telemetry collection, or settings redesign.

## Task 8: Integrate functional checks and apply once to the live desktop

**Modify:** `tools/hooks/pre-commit` to register the seven new deterministic checkers, and this plan's completion record. Preserve staged-tree testing. If updating the existing untracked contributor docs, explicitly report those path-scoped changes.

- [ ] Run syntax checks on changed Bash/Python files and register the new fixture checkers alongside the existing checks. New tests must never depend on the real dconf database or active desktop.
- [ ] Run the seven new checkers once together after integration, plus the existing related checks listed in Tasks 1–7 and `bash tools/check-solid-extensions.sh`, `bash tools/check-migration.sh`, `python3 tools/check-gui-radius.py`. Repeat only failures or checks affected by subsequent edits. If committing is separately requested, enable hooks with `tools/install-hooks.sh` and let the staged-tree gate run; do not stage unrelated untracked docs.
- [ ] Inspect `git diff --check` and `git status --short`. Review all changed runtime paths for backup, dry-run, ownership, and installation coverage. Confirm the installed GUI includes its new module and standalone apply includes its helper even when GUI installation is disabled.
- [ ] Before live application, read `preview status --json` and complete any pending owned preview through its backend. Preserve existing user selections. Run the required supported command once:

```bash
./install.sh --settings-only -y
```

- [ ] Launch the installed settings app once. Check navigation remains responsive, edit a tint repeatedly then Apply, preview then Discard, and close with a pending preview using the existing close choices. Restore the user's baseline after these bounded checks. If safe cleanup is verified, use the existing `tools/check-preview.sh` for one controlled round trip; a skip is unverified.
- [ ] Inspect user-unit status and recent logs for the changed icon/panel helpers without restarting them merely to measure startup. If a real monitor or login transition is unavailable, record it as unverified and supply the manual checklist below; do not initiate logout or disconnect hardware.
- [ ] Report changed behavior, functional checks passed/failed/skipped, and remaining limitations. Say “avoids redundant writes/reloads” only when the fixture assertions pass. Do not claim a faster login, lower GPU use, or a percentage improvement.

### Manual session checklist for the next normal login

1. Login normally: panel blur settles once; icons match the chosen appearance; no installer/update terminal appears.
2. Switch light/dark: icon variant follows the currently selected pack.
3. Change only cursor size or accent in the app: existing light/dark choice remains; panel helper is not restarted.
4. During ordinary monitor reconnection: a burst settles into one panel rebuild; disabled blur stays off.
5. Reopen after an interrupted preview: recovery outcome is reported accurately and newer saved settings survive.
6. Use Re-apply for an intentional repair; switch frosted → transparent → solid → frosted and verify preferences survive. Restore the original mode afterward.

## Completion record

Planning completed: 2026-09-05 against working tree based on `502a795`.

Execution continued in the same dirty checkout on 2026-09-05; existing tracked
and untracked work was preserved and nothing was committed or staged.

- Runtime implementation: preview queue, operation coordinator, atomic/no-op
  CSS publication, helper reconciliation, panel event reducer, conservative
  incremental selector, and feedback/status fixtures implemented in the working
  tree. The seven new deterministic fixture checks passed together.
- Benchmarks/GPU sampling: not run and excluded.
- Live application/session checks: `./install.sh --settings-only -y` ran twice;
  the second run installed the panel-worker quoting fix. CSS targets were
  unchanged, icon sync was active, and the current panel worker remained active
  after its settle interval. The installed settings launcher was invoked; full
  interactive navigation/preview-click coverage remains a manual desktop check.
- Optional roadmap features: not included in this implementation batch.
