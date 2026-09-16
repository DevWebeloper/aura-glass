# AGENTS.md

Instructions for any AI coding agent working in this repository.

**The full instructions are in [CLAUDE.md](CLAUDE.md).** Read that file first —
it is written for agents regardless of vendor, and this file exists only so the
`AGENTS.md` convention finds it.

## The short version

1. **One place resolves a flag into a file.** `install.sh` plus the `apply_*`
   functions in `lib/`. The GUI, the wizard and the preview call that code; they
   never reimplement it.
2. **Never hand-edit `~/.themes` or `~/.config/gtk-*`.** They are generated.
   `bin/aura-glass-apply` owns one marked block in each. Edit `css/` instead.
3. **Duplicated numbers are checked, not trusted.** `tokens/tokens.sh` is the
   source of truth; `tools/check-tokens.sh` fails a commit that drifts.
4. **Comments explaining *why a number is that number* are the deliverable.**
   Do not strip or shorten them.
5. **Apply your edit to the live desktop** with `./install.sh --settings-only -y`
   — a repo edit alone is not a finished change.
6. **Stay in scope.** No unrequested validation, refactors or defensive code.
7. **No AI attribution** in commits, tags or releases.

## Verify before committing

```bash
tools/install-hooks.sh   # once per clone; then git commit runs everything
```

Documentation index: [docs/README.md](docs/README.md).
