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

# The blockers that survive. Installing edits the working tree, and these two are
# still cases where pulling would fail confusingly or throw away work.
case("a branch with local edits", True, "feature/gui-post-install@",
     "uncommitted", branch="feature/gui-post-install", dirty=True)

# A detached HEAD has no branch to follow the commits of, so it belongs to the
# released line — and is still refused an install, as it was before.
case("a detached HEAD", False, "v0.1.7", "detached HEAD",
     tags=("v0.1.7",), detach=True)

# The regression this whole change is: being on a branch is not a blocker.
with tempfile.TemporaryDirectory() as tmp:
    repo, _conf = build(tmp, branch="feature/gui-post-install")
    if any("rather than main" in b for b in update_blockers(repo)):
        note("a branch is still refused an install — testers cannot update")
    if current_branch(repo) != "feature/gui-post-install":
        note("current_branch: %r" % current_branch(repo))

if fail:
    print("\nupdate channel FAILED\n")
    sys.exit(1)
print("update channel passed — the window and the update check agree on both lines")
