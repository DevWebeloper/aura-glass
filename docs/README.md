# aura-glass documentation

Contributor documentation. For **using** aura-glass, see the top-level
[README.md](../README.md) — installation, every CLI flag, the settings window,
troubleshooting and credits.

---

## Start here

| If you want to… | Read |
|---|---|
| Understand how any of this works | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Change something | [DEVELOPING.md](DEVELOPING.md) |
| Know what the checks assert | [TESTING.md](TESTING.md) |
| Find where a setting is stored | [CONFIG-REFERENCE.md](CONFIG-REFERENCE.md) |
| Touch either GTK window | [GUI.md](GUI.md) |
| Cut a release | [RELEASING.md](RELEASING.md) |
| Contribute a PR | [../CONTRIBUTING.md](../CONTRIBUTING.md) |
| Work on this as an AI agent | [../CLAUDE.md](../CLAUDE.md) / [../AGENTS.md](../AGENTS.md) |

---

## The five rules, in one place

1. **One place resolves a flag into a file** — `install.sh` plus the `apply_*`
   functions in `lib/`. Every front end calls that code; none reimplements it.
2. **Never hand-edit the generated CSS** in `~/.themes` or `~/.config/gtk-*`.
   `bin/aura-glass-apply` owns one marked block in each. Edit `css/`.
3. **Duplicated numbers are checked, not trusted** — `tokens/tokens.sh` plus
   `tools/check-tokens.sh`.
4. **The comments explaining why a number is that number are the deliverable.**
5. **A repo edit is not a finished change** — run
   `./install.sh --settings-only -y`.

---

## Ten-second orientation

```
install.sh          flags in, resolved settings out, steps orchestrated
  lib/*.sh          the steps, split by concern
  tokens/tokens.sh  every value written down more than once
  css/              stylesheets; the NN prefix IS the cascade order
  dconf/            core.ini (every extension's settings), extras, solid
  patches/          pinned-upstream patches
bin/aura-glass-apply   splices css/ into the four generated CSS targets
bin/aura-glass-ext     the extension catalogue, one UUID at a time
bin/aura-glass-preview live preview that never leaves a memo behind
gui/                   setup wizard + settings window — front ends for flags
tools/                 checkers, the headless preview harness, the git hooks
uninstall.sh           four scopes, all reversible from backups/
```

---

## Design records

Longer-form specs and plans written while features were being built. They record
the reasoning at the time and are not maintained as the code moves — the code
and its comments are the current truth.

- [superpowers/specs/2026-08-18-glass-modes-design.md](superpowers/specs/2026-08-18-glass-modes-design.md)
  — the three glass modes: the flag table, the per-mode drawers, what `solid`
  does and does not stand down
- [superpowers/plans/2026-08-18-glass-modes.md](superpowers/plans/2026-08-18-glass-modes.md)
  — the implementation plan for the above

---

## Quick command index

```bash
# install / retune
./install.sh                      # interactive wizard
./install.sh --settings-only -y   # reapply CSS + dconf + gsettings, no root, no network
./install.sh --dry-run            # print what would happen, change nothing
./uninstall.sh [--extensions] [--assets] [--gdm] [--all]

# after an edit
aura-glass-apply                  # re-splice the CSS onto the installed theme

# checks
tools/install-hooks.sh            # enable the pre-commit suite (once per clone)
tools/check-tokens.sh             # duplicated values still agree
tools/check-cascade.sh            # every sheet installed, applied, previewed, in order

# visuals
tools/preview.sh [--solid|--gtk-only|--gpu|--keep]
python3 tools/check-shots.py --mode glass [--accept]

# performance
tools/gpu-live.sh --label before

# extensions
aura-glass-ext list | install UUID | remove UUID | recommended | full
```
