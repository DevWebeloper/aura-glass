# Releasing

**There is no VERSION file. The git tag is the version.**

`bin/aura-glass-update-check` reads it with `git describe --tags --abbrev=0`,
and the settings window's Updates page shows the same answer. A release that
exists only as a GitHub release, with no tag on `main`, is invisible to every
installed copy.

---

## Tag format

```
vMAJOR.MINOR.PATCH          v0.2.5
vMAJOR.MINOR.PATCH-beta     v0.2.3-beta
```

The update check filters `refs/tags` with:

```
s#.*refs/tags/\(v[0-9][0-9.]*\(-beta\)\?\)$#\1#p
```

Anything else in `refs/tags` is not a release of this project — and matters,
because `sort -V` would happily rank a stray tag above a real one. Do not push
tags in any other shape to `origin`.

Ordering is `sort -V`, so `v0.1.10` correctly sorts after `v0.1.9`.
`tools/check-update-check.sh` asserts that against throwaway repositories.

---

## The flow

```bash
# 1. work on a branch
git switch -c feature/whatever
#    … commits …

# 2. merge with an explicit merge commit — the history reads as feature units
git switch main
git merge --no-ff feature/whatever

# 3. tag
git tag -a v0.2.6 -m "v0.2.6 — short title"

# 4. push both
git push origin main
git push origin v0.2.6

# 5. release notes
gh release create v0.2.6 --title "v0.2.6 — short title" --notes "…"
```

`--no-ff` is deliberate: `main`'s history is a list of feature merges, not a
flat replay of every commit inside them.

Before tagging, run the whole check suite (the pre-commit hook covers it, but a
tag is worth an explicit pass) and one visual pass:

```bash
tools/preview.sh && python3 tools/check-shots.py --mode glass
tools/preview.sh --solid && python3 tools/check-shots.py --mode solid
```

---

## Update channels

Two lines, and two independent programs decide which one a checkout is on
(`bin/aura-glass-update-check`, and `current_branch` / `is_test_build` /
`installed_version` in the settings window). `tools/check-update-channel.py`
holds them to the same answer, because nothing else would notice them drifting.

| Checkout | Version reported | Question asked of the remote |
|---|---|---|
| `main`, `master`, or detached HEAD | the nearest reachable tag | is there a newer release tag? |
| any other branch | `branch@shortsha` | has that branch moved? |

A detached HEAD lands in the tag case rather than the branch case: it is the
checkout a release tag was checked out into, so the tag is still the right
question.

The remote is asked with `git ls-remote` — one cheap request, no API token, no
rate limit, works for any git remote rather than only GitHub. **Nothing is
fetched into the working tree**, and nothing is ever installed by the timer. The
answer is left in `$CONF_DIR/update-available` so the window can show it
offline; absent means up to date.

The timer notifies **once per release**, not once per day.

---

## Release-note conventions

Commits use conventional prefixes with a scope — `feat(gui):`, `fix(solid):`,
`docs:` — so `git log --oneline main...v0.2.5 --no-merges` is a usable first
draft.

Tag messages and release titles follow `vX.Y.Z — Short Human Title`.

**No AI attribution anywhere.** No `Co-Authored-By` trailer, no "generated
with", no mention of an assistant in a commit, tag, release title or release
body.

---

## After a release

Users update from the settings window's **Updates** page, which pulls the
release and runs the full installer. There is nothing to publish to a package
registry and no artifact to build — the tag is the whole release.

If a release changes anything about how settings are remembered, check that a
`$CONF_DIR` written by the previous version still resolves. The precedents are
in the tree already: `radius_preset_canonical` answering the retired `pill`, and
`install.sh` widening a seven-field `radius-custom` memo to eight when the
button column was added. A memo a previous version wrote is not something a user
should have to know about.
