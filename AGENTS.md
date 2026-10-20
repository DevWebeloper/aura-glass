# AGENTS.md

Instructions for any AI coding agent in this repository. **The full version is
[CLAUDE.md](CLAUDE.md).** It's written for agents of any vendor. This file
exists so the `AGENTS.md` convention finds it.

**What it is.** Aura Glass is a frosted-glass desktop for GNOME Shell 48–51,
installed by `install.sh` from pinned upstreams plus its own CSS, dconf
presets, patches, a first-party extension, user services and a GTK settings
app. Two glass modes: frosted and performance.

## Non-negotiables

1. **One resolver.** Only `install.sh` and the `apply_*`/`install_*` functions in `lib/` turn a flag into a file, key or memo. Every front end goes through them.
2. **Never hand-edit generated CSS** (`~/.themes/Aura-Glass/…`, `~/.config/gtk-*/…`) or the installed copies in `~/.config/aura-glass/`. Edit `css/`.
3. **Duplicated numbers are checked.** `tokens/tokens.sh` is the truth. Run `tools/check-tokens.sh`.
4. **"Why this number" comments are the deliverable.** Keep them, and update them with the value.
5. **Put theme edits on the desktop** with `./install.sh --settings-only -y`. No full installs, uninstall, `--force` or `sudo` steps unless asked.
6. **`tools/` has three kinds of file.** Runtime helpers (part of the theme: don't move or rename without updating callers). Hermetic `check-*` scripts (safe to run). Live-session tools (`preview*`, `gpu-*`, `check-preview.sh`, `check-shots.py`), which you may run to verify a change live, as their docs say, putting back any desktop state they change (`check-shots.py --accept` only when the user says). Create no new files in `tools/` unless asked.
7. **Keep every path consistent:** CLI, incremental Apply, mode switch, settings-app re-read, both wizards, preview, adaptive, uninstall ([docs/CONSISTENCY.md](docs/CONSISTENCY.md)).
8. **Stay in scope.** No unrequested validation, refactors or defensive code.
9. **No AI attribution** in commits, tags or releases.

## Start here

- Feature → files: [docs/FEATURE-MAP.md](docs/FEATURE-MAP.md) (check it before grepping)
- Known bugs, with repros: [docs/KNOWN-ISSUES.md](docs/KNOWN-ISSUES.md)
- Documentation index: [docs/README.md](docs/README.md)
