#!/usr/bin/env python3
"""Assert the settings window and the update check agree on which line a checkout is on.

There are two lines — releases on main, and commits on a branch someone is
testing — and two programs decide which one a checkout is on: the window, in
current_branch/is_test_build/installed_version, and bin/aura-glass-update-check,
in the case statement it opens with. Neither can read the other, so nothing stops
them drifting apart, and the ways they would drift are all quiet:

  the window naming a test build after a release tag it merely inherited, so a
      tester reads "v0.1.7" and believes they are running the release;

  the check following tags on a branch, so a tester is offered a release that
      does not contain the thing they are testing;

  the window refusing to install on a branch, which is the whole feature.

So this builds throwaway git repositories, asks both programs what they think is
installed, and holds them to the same answer. Nothing here touches the network,
the user's checkout or the user's $CONF_DIR: origin is a second local repository
and $AURA_GLASS_CONF points at a temporary directory.
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "gui"))
CHECK = os.path.join(ROOT, "bin", "aura-glass-update-check")

try:
    import gi  # noqa: F401
except ImportError:
    print("check-update-channel: PyGObject is not installed — skipping (the "
          "settings window is optional, and install.sh skips it here too)")
    sys.exit(0)

import aura_glass_settings  # noqa: E402
from aura_glass_settings import (  # noqa: E402
    current_branch, installed_version, is_test_build, update_blockers)

fail = 0


def note(msg):
    global fail
    print("  %s" % msg)
    fail = 1


def git(repo, *args):
    """Run git in repo, quietly. Raises if it fails — fixtures must build."""
    subprocess.run(
        ["git", "-C", repo, "-c", "user.email=t@t", "-c", "user.name=t",
         "-c", "init.defaultBranch=main"] + list(args),
        check=True, capture_output=True, text=True)


def build(tmp, branch="main", tags=(), detach=False, dirty=False):
    """A checkout on `branch`, tracking a bare origin it has been pushed to."""
    work, remote, conf = (os.path.join(tmp, n) for n in ("work", "remote", "conf"))
    for d in (work, remote, conf):
        shutil.rmtree(d, ignore_errors=True)
    os.makedirs(conf)

    subprocess.run(["git", "init", "-q", "-b", "main", work], check=True)
    open(os.path.join(work, "file"), "w").close()
    git(work, "add", "file")
    git(work, "commit", "-m", "one")
    if branch != "main":
        git(work, "checkout", "-b", branch)
    for t in tags:
        git(work, "tag", t)

    subprocess.run(["git", "init", "-q", "--bare", remote], check=True)
    git(work, "remote", "add", "origin", remote)
    git(work, "push", "-u", "origin", branch)
    if tags:
        git(work, "push", "origin", *tags)

    if detach:
        git(work, "checkout", "--detach", "HEAD")
    if dirty:
        with open(os.path.join(work, "file"), "w") as fh:
            fh.write("edited\n")

    with open(os.path.join(conf, "repo-path"), "w") as fh:
        fh.write(work + "\n")
    return work, conf


def checker_version(conf):
    """The version bin/aura-glass-update-check reports, or None if it could not tell.

    Only the up-to-date wording is parsed, because every fixture here is level
    with its origin — what is being compared is the name, not the verdict.
    """
    env = dict(os.environ, AURA_GLASS_CONF=conf)
    res = subprocess.run(["bash", CHECK], env=env, capture_output=True, text=True)
    out = res.stdout.strip()
    if res.returncode != 0 or not out.startswith("up to date ("):
        return None
    return out[len("up to date ("):-1]


def case(label, want_test, want_version, want_blocker, **kw):
    """Both programs are asked the same question and held to the same answer."""
    with tempfile.TemporaryDirectory() as tmp:
        repo, conf = build(tmp, **kw)
        # The window's side reads its memos (update-channel) out of CONF_DIR,
        # which is the real ~/.config/aura-glass at import: pointed at the
        # fixture here as the checker's side is, through AURA_GLASS_CONF.
        aura_glass_settings.CONF_DIR = conf

        got_test = is_test_build(repo)
        if got_test != want_test:
            note("%s: is_test_build %r, want %r" % (label, got_test, want_test))

        got = installed_version(repo)
        # A commit hash is not known in advance, so a want of "BRANCH@" is a
        # prefix and the seven characters after it are only checked for length.
        if want_version.endswith("@"):
            if not got or not got.startswith(want_version) \
                    or len(got) != len(want_version) + 7:
                note("%s: installed_version %r, want %r plus a 7-char sha"
                     % (label, got, want_version))
        elif got != want_version:
            note("%s: installed_version %r, want %r" % (label, got, want_version))

        # The point of the whole file: the two programs name the same checkout
        # the same way, so what the window shows is what the check compared.
        theirs = checker_version(conf)
        if theirs != got:
            note("%s: the window says %r and the update check says %r"
                 % (label, got, theirs))

        blockers = update_blockers(repo)
        if want_blocker is None:
            if blockers:
                note("%s: refused to install — %s" % (label, blockers[0]))
        elif not any(want_blocker in b for b in blockers):
            note("%s: blockers %r, want one mentioning %r"
                 % (label, blockers, want_blocker))


# The released line. Unchanged behaviour: a tag is what is installed.
case("main on a release", False, "v0.1.7", None, tags=("v0.1.7",))

# The test line. The tag is reachable and deliberately not used: naming this
# checkout v0.1.7 would claim it holds a release cut before the branch existed.
case("a branch with an inherited tag", True, "feature/gui-post-install@", None,
     branch="feature/gui-post-install", tags=("v0.1.7",))
case("a branch with no tag at all", True, "feature/fresh@", None,
     branch="feature/fresh")

# Local edits and a detached HEAD used to block an install, and were the reason
# the Install button went grey for people who had done nothing wrong. They are
# not blockers any more: bin/aura-glass-update stashes the edits and moves a
# detached HEAD itself.
case("a branch with local edits", True, "feature/gui-post-install@", None,
     branch="feature/gui-post-install", dirty=True)

# A detached HEAD has no branch to follow the commits of, so it belongs to the
# released line.
case("a detached HEAD", False, "v0.1.7", None,
     tags=("v0.1.7",), detach=True)

# The regression this whole change is: being on a branch is not a blocker.
with tempfile.TemporaryDirectory() as tmp:
    repo, _conf = build(tmp, branch="feature/gui-post-install")
    if any("rather than main" in b for b in update_blockers(repo)):
        note("a branch is still refused an install — testers cannot update")
    if current_branch(repo) != "feature/gui-post-install":
        note("current_branch: %r" % current_branch(repo))

# bin/aura-glass-update, against the states that used to stop a pull dead.
UPDATE = os.path.join(ROOT, "bin", "aura-glass-update")


def update(conf, target):
    env = dict(os.environ, AURA_GLASS_CONF=conf, GIT_AUTHOR_NAME="t",
               GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
               GIT_COMMITTER_EMAIL="t@t")
    return subprocess.run(["bash", UPDATE, "--no-install", target], env=env,
                          capture_output=True, text=True)


def out(repo, *args):
    return subprocess.run(["git", "-C", repo] + list(args), check=True,
                          capture_output=True, text=True).stdout.strip()


with tempfile.TemporaryDirectory() as tmp:
    # A dirty, detached checkout with a newer release on the remote: switched
    # to the release, the edit stashed rather than lost.
    repo, conf = build(tmp, tags=("v0.1.7",), detach=True, dirty=True)
    git(repo, "checkout", "-q", "main")
    git(repo, "stash")
    git(repo, "commit", "--allow-empty", "-m", "two")
    git(repo, "tag", "v0.1.8")
    git(repo, "push", "-q", "origin", "main", "v0.1.8")
    git(repo, "checkout", "-q", "--detach", "v0.1.7")
    git(repo, "stash", "pop")
    res = update(conf, "v0.1.8")
    if res.returncode != 0:
        note("update to a tag from a dirty detached HEAD failed: %s"
             % (res.stderr.strip() or res.stdout.strip()))
    elif out(repo, "describe", "--tags", "--exact-match") != "v0.1.8":
        note("update to v0.1.8 left HEAD at %s" % out(repo, "describe", "--tags"))
    elif "aura-glass update" not in out(repo, "stash", "list"):
        note("the local edit was not stashed under an aura-glass message")
    elif current_branch(repo) is not None:
        note("a release install should leave a detached HEAD")

with tempfile.TemporaryDirectory() as tmp:
    # main diverged from origin: reset to origin's main, the local commit kept
    # on a backup branch, upstream set so the commits line works afterwards.
    repo, conf = build(tmp)
    remote = os.path.join(tmp, "remote")
    other = os.path.join(tmp, "other")
    subprocess.run(["git", "clone", "-q", "-b", "main", remote, other], check=True)
    git(other, "commit", "--allow-empty", "-m", "theirs")
    git(other, "push", "-q", "origin", "main")
    git(repo, "commit", "--allow-empty", "-m", "mine")
    res = update(conf, "main")
    if res.returncode != 0:
        note("update of a diverged main failed: %s"
             % (res.stderr.strip() or res.stdout.strip()))
    else:
        if out(repo, "log", "-1", "--format=%s") != "theirs":
            note("diverged main was not moved to origin's main")
        backups = out(repo, "branch", "--list", "aura-glass-backup/*")
        if not backups or out(repo, "log", "-1", "--format=%s",
                              backups.split()[-1]) != "mine":
            note("the local commit on main was not kept on a backup branch")
        if out(repo, "rev-parse", "--abbrev-ref", "@{upstream}") != "origin/main":
            note("main does not track origin/main after the update")

with tempfile.TemporaryDirectory() as tmp:
    # A tag re-cut on the remote must replace the stale local one, not stop the
    # fetch with "would clobber existing tag".
    repo, conf = build(tmp, tags=("v0.1.7",))
    other = os.path.join(tmp, "other")
    subprocess.run(["git", "clone", "-q", "-b", "main", os.path.join(tmp, "remote"), other],
                   check=True)
    git(other, "commit", "--allow-empty", "-m", "recut")
    git(other, "tag", "-f", "v0.1.7")
    git(other, "push", "-q", "--force", "origin", "main", "v0.1.7")
    res = update(conf, "v0.1.7")
    if res.returncode != 0:
        note("update to a re-cut tag failed: %s"
             % (res.stderr.strip() or res.stdout.strip()))
    elif out(repo, "log", "-1", "--format=%s") != "recut":
        note("a re-cut tag did not replace the local one")

if fail:
    print("\nupdate channel FAILED\n")
    sys.exit(1)
print("update channel passed — the window and the update check agree on both lines")
