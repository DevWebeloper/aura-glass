# Contributing

Thanks for looking at aura-glass. This file is the short version; the long
version is in [docs/](docs/).

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how it works and why
- [docs/DEVELOPING.md](docs/DEVELOPING.md) — the working loop, and how to make
  each kind of change
- [docs/TESTING.md](docs/TESTING.md) — what every checker asserts
- [docs/CONFIG-REFERENCE.md](docs/CONFIG-REFERENCE.md) — every path and memo
- [docs/GUI.md](docs/GUI.md) — the two windows and their contracts
- [docs/RELEASING.md](docs/RELEASING.md) — tags, channels, the flow
- [CLAUDE.md](CLAUDE.md) — the same ground rules, written for AI agents

---

## Getting set up

```bash
git clone https://github.com/DevWebeloper/aura-glass.git
cd aura-glass
tools/install-hooks.sh     # once per clone
./install.sh               # you need an installed theme to develop against
```

You need a GNOME 48/49/50/51 desktop to work on this meaningfully. There is no
build step and no dependency beyond bash, python3 and git — plus PyGObject and
libadwaita if you touch `gui/`.

---

## The five rules

1. **One place resolves a flag into a file.** `install.sh` plus the `apply_*`
   functions in `lib/`. The settings window, the setup wizard and
   `aura-glass-preview` all call that code — none of them reimplements it.
2. **Never hand-edit `~/.themes` or `~/.config/gtk-*`.** They are generated.
   `bin/aura-glass-apply` owns one marked block in each. Edit `css/` instead.
3. **Duplicated numbers are checked, not trusted.** `tokens/tokens.sh` is the
   source of truth and `tools/check-tokens.sh` fails a commit that drifts.
4. **Comments explaining why a number is that number are the deliverable.** Most
   of them record a bisection against a screenshot. Do not strip or shorten
   them; when you change a value, change the reason with it.
5. **Apply your change to the live desktop before calling it done:**
   `./install.sh --settings-only -y`.

---

## Before you open a PR

```bash
git commit                 # the hook runs the whole suite against the staged tree
```

The pre-commit hook runs shell and Python syntax plus fifteen project checkers.
If you disabled it, run them by hand — see [docs/TESTING.md](docs/TESTING.md).

Visual changes want a preview pass:

```bash
tools/preview.sh
python3 tools/check-shots.py --mode glass
```

Include the before/after in the PR when a corner, a colour or a blur moved.

---

## Commits

Conventional prefixes with a scope, subject in lower case, no trailing period:

```
feat(gui): per-app blur switches, titlebar button styles, adwaita radius preset
fix(solid): move a theme-created target aside instead of deleting it
docs: point to the v0.2.3 release
```

Scopes in use: `gui`, `solid`, `theme`, `fonts`, `extensions`, `update-check`,
`notification-blur`, and whatever the change is actually about.

Stage explicitly rather than `git add -A` — the hook checks the staged tree, and
this project routinely has unrelated work in progress.

**No AI attribution.** No `Co-Authored-By` trailer, no "generated with" footer,
no mention of an assistant in commits, tags or releases.

---

## Branches

Feature branch → `git merge --no-ff` into `main`. `main`'s history reads as a
list of feature merges. Releases are git tags; see
[docs/RELEASING.md](docs/RELEASING.md).

---

## Scope

Do the change you came for. Unrequested validation, defensive branches and
drive-by refactors cost more to review than they save, and this codebase is
deliberate — most things that look odd have a comment above them explaining why.
Read the comment before you fix the oddity.

If you disagree with a decision the comments record, say so in the PR. Changing
it silently loses the reasoning for whoever comes next.

---

## Reporting a bug

Include:

- GNOME Shell version (`gnome-shell --version`), session type (Wayland or X11),
  and distribution;
- the output of `./install.sh --dry-run`, which prints the resolved glass mode
  line and every step it would take;
- `ls ~/.config/aura-glass` — the memos say what the installer thinks your
  settings are;
- for a visual bug, a screenshot, and whether `aura-glass-apply` alone fixes it.

## Licence

MIT for the scripts, CSS patches and tooling in this repository. Upstream
themes, extensions and assets keep their own licences — see the credits table in
[README.md](README.md).
