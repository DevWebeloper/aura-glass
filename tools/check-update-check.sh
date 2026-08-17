#!/usr/bin/env bash
# Assert aura-glass-update-check compares versions the way versions compare.
#
# The whole feature is one question — is the remote tag newer than the local one
# — and the ways to get it wrong are quiet. A lexicographic compare puts v0.1.10
# before v0.1.9, so the release after the ninth would never be announced. A
# too-loose tag filter lets a `nightly` or a `v2-old-backup` rank above every
# real release and announces an update that does not exist. Neither shows up as
# an error; both just make the notification wrong forever.
#
# So this builds throwaway git repositories with known tags and runs the real
# script against them. Nothing here touches the network, the user's checkout, or
# the user's $CONF_DIR: origin is a second local repository, and $AURA_GLASS_CONF
# points at a temporary directory.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO_ROOT/bin/aura-glass-update-check"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

git_quiet() { git -c init.defaultBranch=main -c user.email=t@t -c user.name=t "$@" >/dev/null 2>&1; }

# A bare "remote" holding the given tags, and a checkout sitting on `local_tag`.
build() {
    local local_tag="$1"; shift
    rm -rf "$TMP/remote" "$TMP/work" "$TMP/conf"
    mkdir -p "$TMP/remote" "$TMP/conf"

    git_quiet init "$TMP/work"
    ( cd "$TMP/work"
      : > file
      git -c user.email=t@t -c user.name=t add file >/dev/null 2>&1
      git -c user.email=t@t -c user.name=t commit -m one >/dev/null 2>&1
      for t in "$@"; do git tag "$t" >/dev/null 2>&1; done ) || return 1

    git_quiet init --bare "$TMP/remote"
    git_quiet -C "$TMP/work" remote add origin "$TMP/remote"
    git_quiet -C "$TMP/work" push origin main --tags

    # The local checkout keeps only its own tag, so `describe` cannot see the
    # newer ones the remote has. That is the real situation: a checkout from
    # before a release has no knowledge of it until it fetches.
    for t in "$@"; do
        [ "$t" = "$local_tag" ] || git_quiet -C "$TMP/work" tag -d "$t"
    done
    # Cutting a release makes the local tag first and pushes it later, so the
    # local tag is not necessarily one the remote has. Create it after the push
    # when that is the case being set up.
    git_quiet -C "$TMP/work" tag "$local_tag" || true
    printf '%s\n' "$TMP/work" > "$TMP/conf/repo-path"
}

# expect EXIT LABEL LOCAL_TAG REMOTE_TAGS...
expect() {
    local want="$1" label="$2" local_tag="$3"; shift 3
    build "$local_tag" "$@" || { note "$label: could not build the fixture"; return; }
    local out rc=0
    out="$(AURA_GLASS_CONF="$TMP/conf" bash "$CHECK" 2>&1)" || rc=$?
    if [ "$rc" != "$want" ]; then
        note "$label: exit $rc, want $want — $out"
        return
    fi
    # The state file is what the settings window reads, so it has to agree with
    # the exit code rather than merely existing.
    if [ "$rc" = 10 ] && [ ! -s "$TMP/conf/update-available" ]; then
        note "$label: reported an update but wrote no update-available"
    fi
    if [ "$rc" = 0 ] && [ -e "$TMP/conf/update-available" ]; then
        note "$label: up to date but left an update-available behind"
    fi
}

# 0 = up to date, 10 = update available, 1 = could not tell.
expect 0  "same tag on both sides"          v0.1.7 v0.1.7
expect 10 "one patch release ahead"         v0.1.7 v0.1.7 v0.1.8
expect 10 "a minor release ahead"           v0.1.7 v0.1.7 v0.2.0
expect 10 "a major release ahead"           v0.1.7 v0.1.7 v1.0.0

# The one a lexicographic compare gets wrong, and the reason sort -V is used.
expect 10 "v0.1.10 is newer than v0.1.9"    v0.1.9 v0.1.9 v0.1.10
expect 0  "v0.1.9 is not newer than v0.1.10" v0.1.10 v0.1.9 v0.1.10

# Mid-release: the local checkout is on a tag the remote has not been given yet.
expect 0  "local ahead of the remote"       v0.2.0 v0.1.7

# Tags that are not releases must not rank above one. These four are the ones
# that matter, because sort -V puts every one of them ABOVE v0.1.7 — a tag that
# sorts below it would pass this check without the filter existing at all.
#
# v0.2.0-rc1 is the interesting one: it is a real tag of a real future release,
# and announcing it would push a release candidate onto everyone running the
# stable line.
expect 0  "a wip tag is ignored"            v0.1.7 v0.1.7 wip
expect 0  "an experiment tag is ignored"    v0.1.7 v0.1.7 zz-experiment
expect 0  "a backup tag is ignored"         v0.1.7 v0.1.7 v0.1.7-backup
expect 0  "a release candidate is ignored"  v0.1.7 v0.1.7 v0.2.0-rc1
expect 10 "a real release beside junk"      v0.1.7 v0.1.7 zz-experiment v0.1.8

# Nothing to compare against.
expect 1  "no tags on the remote at all"    v0.1.7

# A missing repo-path is a broken install, not "up to date" — reporting no
# update there would hide the breakage forever.
rm -rf "$TMP/conf"; mkdir -p "$TMP/conf"
rc=0
AURA_GLASS_CONF="$TMP/conf" bash "$CHECK" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || note "no repo-path: exit $rc, want 1"

if [ "$fail" = 1 ]; then
    printf '\nupdate check FAILED\n\n'
    exit 1
fi
printf 'update check passed — version ordering, tag filtering and state file agree\n'
