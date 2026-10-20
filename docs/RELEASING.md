# Releasing

**There's no VERSION file. The git tag is the version.** `bin/aura-glass-update-check`
and the settings window's Updates page both read it with
`git describe --tags --abbrev=0`. A release that exists only on GitHub, with no
tag on `main`, is invisible to every installed copy. A package install (the
AUR's `aura-glass-git`) follows `main`'s commits instead, through `.packaged`.

---

## Tag format

```
vMAJOR.MINOR.PATCH          v0.2.9
vMAJOR.MINOR.PATCH-beta     v0.3.0-beta
```

The update check keeps only tags matching
`s#.*refs/tags/\(v[0-9][0-9.]*\(-beta\)\?\)$#\1#p` and orders them with
`sort -V`, so `v0.1.10` correctly comes after `v0.1.9` (`check-update-check.sh`).
**Don't push tags of any other shape.** They're filtered, but they shouldn't be
there (`wip` and `zz-experiment` were removed for KI-17).

## Flow

```bash
git switch -c feature/whatever          # work on a branch
git switch main && git merge --no-ff feature/whatever     # history reads as feature merges
git tag -a v0.3.0 -m "v0.3.0 — Short Human Title"
git push origin main && git push origin v0.3.0
gh release create v0.3.0 --title "v0.3.0 — Short Human Title" --notes "…"
```

Publishing the release triggers `.github/workflows/release-assets.yml`, which
attaches `aura-glass-vX.Y.Z.tar.gz` and `.zip` (`git archive` of the tag). The
`traffic-tracker.yml` workflow updates the download badges in
`.github/badges/` on its own schedule.

## Before tagging

1. The hermetic suite passes (the hook covers it; do one explicit run anyway).
2. A human runs the visual pass:
   ```bash
   tools/preview.sh && python3 tools/check-shots.py --mode glass
   tools/preview.sh --solid && python3 tools/check-shots.py --mode solid
   ```
3. If anything about **how settings are remembered** changed, check that a `$CONF_DIR` written by the previous release still resolves. Precedents: `radius_preset_canonical` maps the retired `pill`, a 7-field `radius-custom` memo is widened to 8, and `migrate_solid_era` turns a legacy `solid`/`transparent` `glass-mode` into `performance`/`frosted`.
4. [KNOWN-ISSUES.md](KNOWN-ISSUES.md) is up to date, with fixed entries moved down.
5. If the packaging is maintained, `packaging/aur/PKGBUILD` matches (KI-13).

## Update channels

| Checkout | Reported version | Question asked of the remote (`git ls-remote`) |
|---|---|---|
| `main`, `master`, detached HEAD | nearest tag | is there a newer release tag? |
| `main`, `master` with `update-channel` = `latest` | `main@shortsha` | has `main` moved? A newer release tag still takes the notification headline |
| any other branch | `branch@shortsha` | has the branch moved? |

The two programs that decide this (`aura-glass-update-check`, and
`current_branch` / `is_test_build` / `installed_version` in the GUI) are held
together by `check-update-channel.py`. The timer notifies **once per release**
and never installs. The result is cached in `$CONF_DIR/update-available`.
Users update from the Updates page, which pulls the checkout and runs the
installer in a terminal.

## Conventions

- Commit subjects: `type(scope): lower-case sentence, no trailing period`. Scopes in use include `gui`, `modes`, `apply`, `extension(s)`, `css`, `adaptive`, `quick-settings`, `solid`, `fonts`, `update-check` and `ci`. `git log --oneline vPREV..main --no-merges` makes a usable first draft of the notes.
- Tag messages and release titles: `vX.Y.Z — Short Human Title`.
- **No AI attribution anywhere.** No `Co-Authored-By` trailer, no "generated with", and no mention of an assistant in commits, tags, release titles or bodies.
