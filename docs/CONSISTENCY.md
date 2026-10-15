# Consistency: keeping the app, the scripts and the theme in agreement

Aura Glass has **seven front ends**:

1. `install.sh` typed by hand
2. the text wizard inside `install.sh`
3. the GTK setup wizard
4. the settings app
5. the live preview
6. the adaptive worker and its top-bar menu
7. "Blur This App" in the window menu

They all produce the same theme. "Stable" means that for any user choice, every
path that can express it ends in the same files, the same dconf keys, and the
same memos, and every reader then shows that same state back. This document
holds the contract, the register of facts that are written down more than once,
and the drift found as of this rewrite.

---

## 1. The contract

| # | Rule | Why | Enforced by |
|---|---|---|---|
| C1 | **One resolver.** Only `install.sh` and the `apply_*` in `lib/` turn a flag into a file, key or memo. | A second copy of precedence drifts within a release. | review; `check-gui-flags.py`, `check-wizard-flags.py` (the flags they emit are accepted) |
| C2 | **Front ends emit flags, nothing else.** GUI and wizards never write theme files or `$C` memos. | Writes that bypass the resolver bypass validation, the lock and the drawers. | review. Documented exceptions in §1.1 |
| C3 | **Every memo write is guarded by `remembering()`.** | Dry runs, previews and adaptive transitions must leave no trace. | review; `check-preview.sh` (live), `check-adaptive-installer.sh` |
| C4 | **Every project writer holds the operation lock.** | The installer, preview, apply, adaptive worker and window menu all write the same files. | re-exec guards in `install.sh`, `uninstall.sh`, `aura-glass-apply`, `aura-glass-preview`; `check-operation-recovery.py` |
| C5 | **Readers read where the resolver reads.** If `install.sh` resolves a field from the mode drawer, the settings app shows it from the drawer, and both must be up to date after *every* writer (full, incremental, preview commit, adaptive). | Otherwise the window shows one value while the next run applies another. | `check-glass-modes.sh` (installer side only). **Gap: no check covers incremental → drawer** (KI-01) |
| C6 | **A duplicated fact has a checker.** | Untested copies drift silently. | §2 register |
| C7 | **Wizard parity.** Every question in the GTK wizard exists in the text wizard with the same options and the same recommended answer, and the reverse. | Half the machines (SSH, no PyGObject) only ever see one of them. | **comment only**, unenforced. Drift closed against the GTK wizard as canonical (KI-24, §3) |
| C8 | **Every install artifact has an uninstall counterpart.** | Uninstall must be complete. | review (drift in §3) |
| C9 | **A mode switch is complete.** Switching modes moves every blur component, sheet and drawer field the mode owns, on a fresh install and on an existing one. | A partial switch is a mode that's neither. | **gap** (KI-03) |
| C10 | **Transient states are invisible.** Preview and adaptive change the desktop, never what the next run resolves to, and their undo restores exactly the normal mode. | They run on top of the user's real choices. | `check-preview.sh`, `check-adaptive-installer.sh` (but it fabricates a memo, KI-02) |

### 1.1 Documented exceptions to C2

| Writer | Writes | Why it's allowed | Risk |
|---|---|---|---|
| Settings app, Per-app blur → games | `$C/adaptive-fullscreen-apps` directly (atomic replace), then `aura-glass-adaptive refresh` | not an installer setting; the worker owns it | no lock; `refresh` is found via `PATH` |
| Settings app, live window opacity | D-Bus `SetWindowOpacity` / `RefreshOpacity` | in-session feedback while dragging | none persisted |
| Settings app, preview CSS providers | in-process `Gtk.CssProvider` | shows GTK changes in its own window | cleared on Apply |
| `aura-glass-adaptive profile` | `$C/adaptive-profile` | worker state | none |

---

## 2. Register: facts written down more than once

| Fact | Copies | Checker | Status |
|---|---|---|---|
| Token values (radii, sigmas, transparency, tint) | `tokens/tokens.sh`, `css/*.css`, `dconf/core.ini`, the pipelines blob | `check-tokens.sh` (via `token_manifest.py`) | ✅ |
| Radius preset rows and per-surface bounds | `tokens.sh` (`radius_preset_values`, `radius_bounds`), `gui/aura_glass_settings.py` (`RADIUS_PRESET_VALUES`, `RADIUS_SURFACES`) | `check-gui-radius.py`, `check-radius-preset.sh` | ✅ |
| Stylesheet set and order | `install_css`, `SHELL_SNIPPETS`/`GTK4_SNIPPETS`, `tools/preview-session.sh` | `check-cascade.sh` | ✅ |
| Flags the GUI and wizard emit | `flags_against`, `Answers.to_argv`, `parse_flags` | `check-gui-flags.py`, `check-wizard-flags.py` | ✅ (acceptance only, not meaning) |
| Extension catalogue | `lib/steps.sh` arrays + `ext_description`; `aura-glass-ext list`; GUI page | `check-ext-catalogue.sh` | ✅ for the GUI. ❌ text-wizard prose, `--help` text, uninstall list |
| App-blur list literal | `app_blur_literal`, extension comment, preview | `check-app-blur-lists.sh` | ✅ |
| Update channel (release vs branch) | `aura-glass-update-check`, GUI `current_branch`/`is_test_build`/`installed_version` | `check-update-channel.py`, `check-update-check.sh` | ✅ |
| Glass mode names and derivation | `steps-modes.sh`, GUI `GLASS_MODES` + `Settings.__init__`, `apply_adaptive_blur`, adaptive worker | `check-glass-modes.sh` (installer) | ❌ adaptive still keys on `solid` / a `blur` memo (KI-02) |
| Drawer field list | `seed/load/save_glass_mode_memos`, GUI `Settings.modes`, `apply_adaptive_blur restore` | none | ❌ not saved on the incremental path (KI-01) |
| Defaults when a memo is missing | `install.sh` / `lib`, `seed_glass_mode`, GUI `Settings()`, setup wizard `Answers()`, text wizard | none | ✅ pointer default settled (§3, KI-05); frosted seed level fixed (KI-18) |
| Numeric bounds (transparency 70–100, blur 25–200, brightness 50–150, notification 10–85, cursor 16–128) | `install.sh`/`lib`, GUI constants | none | ✅ today, unchecked |
| Pack families | install/uninstall (`lib/steps-assets.sh`, `uninstall.sh`), GUI `ICON_PACK_FAMILIES` | none | ❌ Moga missing in the GUI |
| Installed commands | `install_css`, `install_gui`, `install_*` units, `uninstall.sh` removal list | none | ❌ `aura-glass-operation`, `aura-glass-preview` not removed |
| GUI runtime requirements | `gui_toolkit_present` + `GUI_TOOLKIT_PKGS_*` (`lib/distro.sh`), GUI imports | none | ❌ `import cairo` not probed (KI-03) |
| Launcher resolution (checkout vs installed copy) | `aura-glass-operation` (checkout first), `aura-glass-adaptive` and `aura-glass-panel-blur` (installed first) | none | ⚠ inconsistent (KI-09) |
| Supported GNOME versions | `preflight` (48–51), `metadata.json`, README, PKGBUILD | none | ✅ |
| Licence | `LICENSE` (MIT), README, CONTRIBUTING, PKGBUILD | none | ❌ PKGBUILD says GPL (KI-13) |

---

## 3. Drift found during this rewrite

Each item has an entry in [KNOWN-ISSUES.md](KNOWN-ISSUES.md) with the fix
direction.

**Recommended pointer and icons.** Resolved (KI-05): both wizards and the
settings app recommend **Reversal + Moga**, with the same options in the same
order. A flagless `install.sh` deliberately keeps **Colloid + Adwaita**, so a
bare scripted run fetches no packs it wasn't asked for.

| Source | Icons | Pointer |
|---|---|---|
| `install.sh` flagless default | Colloid | Adwaita |
| Text wizard, "Complete Experience" and "Customize" default | Reversal | Moga |
| GTK setup wizard (`Answers`) | Reversal | Moga |
| Settings app when `cursor-pack` is missing | | Moga |

**Extension catalogue prose.** Resolved (KI-06). The text wizard still lists "Magic Lamp Effect"
(replaced by Quick Settings Audio Panel). `--help` says "all 14 extra
extensions" (there are 8).

**Blur scope default.** Resolved (KI-06): the prose now matches. Code and `core.ini` use **all apps** (`APP_BLUR_SCOPE="all"`,
`enable-all=true`). `--help` and an `install.sh` comment still call GTK-only the
default. `--help` also says app transparency is "Off by default", but a fresh
install resolves to 0.90.

**Modes.** Two modes in code. Docs, GUI comments ("three tabs") and the
`shell-80-solid.css` header still describe three, or "only by --no-blur". The
adaptive path still special-cases `solid`.

**Fresh-install transparency: two answers.** A flagless run resolves 0.90, but
a fresh frosted drawer seeds 0. So `--glass-mode frosted` and the text wizard's
Customize path (whose transparency answer isn't marked explicit) produce opaque
windows (KI-18).

**Dry run.** Resolved (KI-08): dry runs seed a scratch copy of `modes/` and the symlink goes through `run`. Before that, "a dry run writes nothing", but `seed_glass_mode` creates drawers
and `install_css` creates the `tahoe-glass-apply` symlink under `--dry-run`
(KI-08).

---

## 4. Stability checklist for any change

Before calling a change done, walk the paths it can be reached from:

1. **CLI.** Does `./install.sh --settings-only --dry-run <flag>` resolve as intended? Does the `glass-mode:` line say what you expect?
2. **Incremental.** Is the flag classified in `select_apply_actions`? If it is, does the narrow path also update **every** memo and drawer field the full path updates?
3. **Mode switch.** Does it survive frosted → performance → frosted on an **existing** install, where `load_dconf` skips the preset?
4. **Settings app.** After Apply, does `Settings()` re-read the value from the same place the installer will read it next time?
5. **Wizards.** If it's a first-run question: same options, same default, same recommendation in both.
6. **Preview.** Does `aura-glass-preview set` show it without writing a memo? Does `revert` put it back?
7. **Adaptive.** After `active` then `restore`, is the desktop identical to before? In both modes?
8. **Uninstall.** Is everything the change installs also removed?
9. **Checks.** Add or extend the checker for any new duplicated fact (C6).

## 5. Checks worth adding (proposals, not yet written)

- `check-incremental-drawer`: an incremental `css`/`window-brightness` Apply, then a full retune, must keep the new values (KI-01).
- `check-mode-switch`: frosted ↔ performance on a fixture that already has BMS `pipelines`, asserting every component's `blur` key and sheet (KI-03).
- `check-adaptive-performance`: `active`/`restore` from a real Performance install (no fabricated memo) must leave `shell-80-solid.css` and every blur key unchanged (KI-02).
- `check-defaults`: `Settings()` defaults, `Answers()` defaults and the text wizard's choices agree with a single declared table.
- `check-uninstall-coverage`: every path written by `install_*` appears in `uninstall.sh`.
- `check-gui-imports`: every top-level import in `gui/*.py` is covered by `gui_toolkit_present`.

Per the project rule, new checks are added only when you ask for them.
