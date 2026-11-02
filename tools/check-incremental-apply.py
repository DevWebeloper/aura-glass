#!/usr/bin/env python3
"""Exercise the incremental selector and the update's parts through the real installer.

Three questions, all under a fixture HOME with stubs for the desktop's commands:

  - Does each flag classify as it should, and does a source change select the
    parts it should and no others?
  - Is every step of install.sh's full sequence and every repository file
    accounted for by a part, so an update cannot silently leave one out?
  - Does a narrow Apply leave the same memos, keys and stylesheets as the full
    retune it replaces? That is the promise a narrow class makes, so each one is
    compared rather than trusted.
"""
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STUB = r'''#!/usr/bin/env python3
"""dconf and gsettings over one JSON file; anything else succeeds silently."""
import json, os, sys
tool = os.path.basename(sys.argv[0])
args = sys.argv[1:]
path = os.environ["AG_STATE"]
state = json.load(open(path)) if os.path.exists(path) else {}
def save():
    json.dump(state, open(path, "w"), sort_keys=True)
if tool == "dconf":
    verb = args[0] if args else ""
    if verb == "read":
        print(state.get(args[-1], ""))
    elif verb == "write":
        state[args[1]] = args[2]; save()
    elif verb == "reset":
        for key in [k for k in state if k == args[-1] or (args[1] == "-f" and k.startswith(args[-1]))]:
            del state[key]
        save()
    elif verb == "load":
        section = ""
        for line in sys.stdin:
            line = line.rstrip("\n")
            if line.startswith("["):
                section = line[1:-1]
                section = "" if section == "/" else section + "/"
            elif "=" in line and not line.startswith("#"):
                key, value = line.split("=", 1)
                state[args[1] + section + key] = value
        save()
    elif verb == "dump":
        sections = {}
        for key, value in sorted(state.items()):
            if key.startswith(args[1]):
                head, _, name = key[len(args[1]):].rpartition("/")
                sections.setdefault(head or "/", []).append("%s=%s" % (name, value))
        for head, lines in sections.items():
            print("[%s]" % head); print("\n".join(lines)); print()
    elif verb == "list":
        pass
elif tool == "gsettings":
    verb = args[0] if args else ""
    if verb == "get":
        print(state.get("gs:%s %s" % (args[1], args[2]), "''"))
    elif verb == "set":
        state["gs:%s %s" % (args[1], args[2])] = args[3]; save()
    elif verb == "reset":
        state.pop("gs:%s %s" % (args[1], args[2]), None); save()
elif tool == "sudo":
    open(os.environ["AG_STATE"] + ".sudo", "a").write(" ".join(args) + "\n")
elif tool == "gnome-shell":
    print("GNOME Shell 50.0")
elif tool == "fc-match":
    print(args[-1] if args else "")
elif tool == "pgrep":
    # No settings window: the updater would close and reopen the real one.
    sys.exit(1)
sys.exit(0)
'''
STUBBED = ("dconf", "gsettings", "gnome-shell", "gnome-extensions", "systemctl",
           "gdbus", "busctl", "fc-match", "fc-cache", "flatpak", "notify-send",
           "sudo", "gtk-update-icon-cache", "update-desktop-database",
           "pgrep", "pkill", "setsid")

LIBS = ("lib/common.sh lib/distro.sh lib/steps.sh lib/steps-*.sh lib/progress.sh "
        "tokens/tokens.sh")


def fixture(temp):
    """A HOME the installer takes for an existing install, and its environment."""
    home = os.path.join(temp, "home")
    stubs = os.path.join(temp, "stubs")
    os.makedirs(stubs)
    for name in STUBBED:
        path = os.path.join(stubs, name)
        with open(path, "w", encoding="utf-8") as stream:
            stream.write(STUB)
        os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)
    os.makedirs(os.path.join(home, ".config", "aura-glass"))
    for sheet in (".themes/Aura-Glass/gnome-shell/gnome-shell.css",
                  ".themes/Aura-Glass/gtk-4.0/gtk.css",
                  ".themes/Aura-Glass/gtk-3.0/gtk.css",
                  ".config/gtk-4.0/gtk.css", ".config/gtk-4.0/gtk-dark.css",
                  ".config/gtk-3.0/gtk.css"):
        path = os.path.join(home, sheet)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as stream:
            stream.write("/* base */\n")
    return home, stubs


def environ(home, stubs):
    return {"HOME": home, "PATH": stubs + ":" + os.environ["PATH"],
            "AG_STATE": os.path.join(home, "state.json"),
            "XDG_CURRENT_DESKTOP": "GNOME", "XDG_RUNTIME_DIR": home,
            "DBUS_SESSION_BUS_ADDRESS": "disabled:"}


def run(env, *args):
    return subprocess.run([os.path.join(ROOT, "install.sh"), *args],
                          env=env, text=True, capture_output=True, timeout=120,
                          stdin=subprocess.DEVNULL)


def plan(env, *args):
    result = run(env, *args, "--dry-run", "--plan-json")
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout.strip().splitlines()[-1])


def apply_plan(env, *args):
    return plan(env, "--settings-only", "--incremental", *args)


def in_libs(env, script, root=ROOT):
    """script with every library sourced from root, as install.sh sources them."""
    body = 'REPO_ROOT=%s; cd "$REPO_ROOT"; for f in %s; do . "$f"; done\n%s' % (
        root, LIBS, script)
    return subprocess.run(["bash", "-c", body], env=env, text=True,
                          capture_output=True, timeout=30)


def stamp_everything(env, root=ROOT):
    """Say every part is current, as the end of a full install does."""
    result = in_libs(env, """
        update_part_hashes
        for part in "${UPDATE_PARTS[@]}"; do update_stamp "$part"; done
        update_stamp other
        update_stamp other-local other
    """, root)
    assert result.returncode == 0, result.stderr


def check_classes(env):
    assert apply_plan(env, "--accent", "teal")["actions"] == ["full"], \
        "with nothing recorded, an Apply is the complete refresh"
    stamp_everything(env)
    expected = {
        ("--accent", "teal"): ["accent", "icons"],
        ("--cursor-size", "32"): ["cursor-size"],
        ("--app-tint-color", "#101820"): ["css"],
        ("--dock-tint-color", "#101820"): ["css"],
        ("--panel-tint-color", "#101820"): ["css"],
        ("--maximized-panel-tint-color", "main"): ["css"],
        ("--app-transparency", "0.82"): ["css", "app-opacity"],
        ("--no-app-transparency",): ["css", "app-opacity"],
        ("--radius-preset", "soft"): ["css", "radius"],
        ("--maximized-blur", "dynamic"): ["maximized-blur"],
        ("--maximized-brightness", "70"): ["blur-pipelines"],
        ("--maximized-blur-strength", "main"): ["blur-pipelines"],
        ("--no-update-check",): ["update-check"],
        ("--no-window-menu",): ["window-menu"],
        ("--no-top-bar-icon",): ["top-bar-icon"],
        ("--top-bar-icon",): ["top-bar-icon"],
        ("--no-popup-blur",): ["css", "popup-blur"],
        ("--no-window-blur",): ["css", "app-blur", "app-opacity"],
        ("--glass-style", "liquid"): ["glass-style"],
        # A mode switch moves every setting at once; it stays the whole retune.
        ("--glass-mode", "performance"): ["full"],
    }
    for flags, actions in expected.items():
        got = apply_plan(env, *flags)["actions"]
        assert got == actions, "%s: expected %s, got %s" % (flags, actions, got)


def check_coverage(env):
    """Every step and every file belongs to a part."""
    with open(os.path.join(ROOT, "install.sh"), encoding="utf-8") as stream:
        install = stream.read()
    sequence = install[install.index("progress_start theme\nrun_update_part theme"):]
    parts = in_libs(env, 'printf "%s\\n" "${UPDATE_PARTS[@]}"').stdout.split()
    run_here = set(re.findall(r"run_update_part ([\w-]+)", sequence))
    assert run_here == set(parts), \
        "full sequence and UPDATE_PARTS differ: %s" % (run_here ^ set(parts))
    bare = re.findall(r"^\s*((?:install|apply|load|enable|sync|flatpak|remove)_\w+)",
                      sequence, re.M)
    assert not bare, "a step outside any part: %s" % bare
    listed = in_libs(env, "UPDATE_LIST_UNCLAIMED=1 update_part_hashes")
    assert listed.returncode == 0, listed.stderr
    tracked = subprocess.run(["git", "ls-files"], cwd=ROOT, text=True,
                             capture_output=True).stdout.splitlines()
    unclaimed = [line for line in listed.stderr.splitlines() if line in tracked]
    assert not unclaimed, "files no part claims or ignores: %s" % unclaimed


def check_selection(temp, env):
    """Changes in a copy of the repository select the parts they should."""
    copy = os.path.join(temp, "repo")
    shutil.copytree(ROOT, copy, ignore=shutil.ignore_patterns(
        ".git", "screenshots", "wallpapers", "__pycache__", "docs"))
    os.makedirs(os.path.join(copy, "wallpapers"))
    # Everything on disk that a part checks for, so what is selected below is
    # only what each change selected.
    seeded = run(env, "--settings-only", "--yes")
    assert seeded.returncode == 0, seeded.stdout + seeded.stderr
    wanted = in_libs(env, 'update_wanted_extensions; printf "%s\\n" "${EXT_EXTRA_ALL[@]}"').stdout.split()
    for uuid in wanted:
        os.makedirs(os.path.join(env["HOME"], ".local/share/gnome-shell/extensions", uuid),
                    exist_ok=True)
    conf = os.path.join(env["HOME"], ".config/aura-glass")
    for memo in ("icon-pack", "cursor-pack"):
        with open(os.path.join(conf, memo), "w", encoding="utf-8") as stream:
            stream.write("keep\n")
    stamp_everything(env, copy)

    def update_plan():
        result = subprocess.run(
            ["bash", os.path.join(copy, "install.sh"), "--update", "--dry-run",
             "--plan-json"], env=env, text=True, capture_output=True, timeout=30)
        assert result.returncode == 0, result.stderr
        return json.loads(result.stdout.strip().splitlines()[-1])

    def edit(path, text):
        with open(os.path.join(copy, path), "a", encoding="utf-8") as stream:
            stream.write(text)

    def expect(change, reason, *parts):
        got = update_plan()
        assert got["fallback_reason"] == reason, (change, got)
        assert set(got["parts"]) == set(parts), (change, got)
        stamp_everything(env, copy)

    expect("nothing", None)
    edit("lib/steps-css.sh", "\n# only a comment\n")
    expect("a comment in a library", None)
    edit("README.md", "\nwords\n")
    expect("documentation", None)
    edit("css/10-probe.css", "/* probe */\n")
    expect("a stylesheet", None, "look")
    edit("gui/aura_glass_settings.py", "\n# probe\n")
    expect("the settings window", None, "gui")
    edit("patches/custom-osd-gnome50.patch", "\n")
    expect("a patch", None, "extensions", "enable")
    edit("extensions/aura-glass-blur@aura-glass.local/extension.js", "\n// probe\n")
    expect("the helper", None, "extensions", "enable", "adaptive")
    # A helper three calls down counts: only install_theme reaches adopt_theme_dir.
    edit("lib/steps-migrate.sh", '\nadopt_theme_dir() { echo changed; }\n')
    expect("a helper of the theme step", None, "theme", "look")
    edit("lib/steps.sh", '\nTHEME_REF="deadbeef"\n')
    expect("a pin", None, "theme", "look")
    edit("new-top-level-file", "x\n")
    got = update_plan()
    assert got["fallback_reason"] == "a file changed that no part claims", got

    # The login screen only for someone who has one themed, and then a stylesheet
    # reaches it too. Root is what asking for this part costs.
    stamp_everything(env, copy)
    open(os.path.join(conf, "gdm-installed"), "w").close()
    stamp_everything(env, copy)
    edit("css/10-probe.css", "/* login */\n")
    assert {"look", "gdm"} <= set(update_plan()["parts"])
    os.remove(os.path.join(conf, "gdm-installed"))

    # An Apply never installs the theme, so a theme with no stamp must not make it
    # run the whole look: that is every install until its first update.
    stamp_everything(env, copy)
    with open(os.path.join(conf, "installed-parts"), encoding="utf-8") as stream:
        kept = [line for line in stream if not line.startswith("theme ")]
    with open(os.path.join(conf, "installed-parts"), "w", encoding="utf-8") as stream:
        stream.writelines(kept)
    applied = subprocess.run(
        ["bash", os.path.join(copy, "install.sh"), "--settings-only", "--incremental",
         "--dry-run", "--plan-json", "--no-update-check"],
        env=env, text=True, capture_output=True, timeout=30)
    assert applied.returncode == 0, applied.stderr
    answer = json.loads(applied.stdout.strip().splitlines()[-1])
    assert answer["parts"] == [] and answer["pending_update"] == [], answer

    # Nothing changed in the sources, but what the part installed is gone.
    stamp_everything(env, copy)
    assert "theme" not in update_plan()["parts"]
    sheet = os.path.join(env["HOME"], ".themes/Aura-Glass/gnome-shell/gnome-shell.css")
    os.rename(sheet, sheet + ".away")
    assert "theme" in update_plan()["parts"]
    os.rename(sheet + ".away", sheet)


def check_update_run(temp, env):
    """A real --update, stubs under it: only the changed part, no sudo, no logout."""
    copy = os.path.join(temp, "repo")
    conf = os.path.join(env["HOME"], ".config/aura-glass")
    stamp_everything(env, copy)
    probe = os.path.join(copy, "bin/aura-glass-settings")
    with open(probe, "a", encoding="utf-8") as stream:
        stream.write("\n# probe\n")
    events = os.path.join(temp, "progress")
    os.makedirs(events, exist_ok=True)
    for name in ("events", "log"):
        open(os.path.join(events, name), "w").close()
    done = subprocess.run(
        ["bash", os.path.join(copy, "install.sh"), "--update", "--gui", "--yes"],
        env={**env, "AURA_GLASS_PROGRESS_DIR": events}, text=True,
        capture_output=True, timeout=120, stdin=subprocess.DEVNULL)
    assert done.returncode == 0, done.stdout + done.stderr
    assert "running only what changed: gui" in done.stdout, done.stdout
    installed = os.path.join(env["HOME"], ".local/bin/aura-glass-settings")
    with open(installed, encoding="utf-8") as stream:
        assert "# probe" in stream.read(), "the changed file did not arrive"
    assert not os.path.exists(env["AG_STATE"] + ".sudo"), "asked for sudo needlessly"
    with open(os.path.join(events, "events"), encoding="utf-8") as stream:
        seen = [json.loads(line) for line in stream]
    skipped = {e["id"] for e in seen if e["t"] == "end" and e["status"] == "skip"}
    assert {"theme", "extensions", "look", "enable"} <= skipped, skipped
    finish = [e for e in seen if e["t"] == "finish"]
    assert finish and finish[-1]["logout"] == "0", finish
    # Now current: the next plan has nothing to do.
    result = subprocess.run(
        ["bash", os.path.join(copy, "install.sh"), "--update", "--dry-run",
         "--plan-json"], env=env, text=True, capture_output=True, timeout=30)
    assert json.loads(result.stdout.strip().splitlines()[-1])["parts"] == [], result.stdout
    assert os.path.exists(os.path.join(conf, "installed-parts"))


def check_updater(temp, env):
    """bin/aura-glass-update from a real remote: partial, and an old release."""
    source = os.path.join(temp, "repo")
    remote = os.path.join(temp, "remote.git")
    clone = os.path.join(temp, "clone")
    conf = os.path.join(env["HOME"], ".config/aura-glass")
    git_env = {**env, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
               "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}

    def git(where, *args):
        done = subprocess.run(["git", "-C", where, *args], env=git_env, text=True,
                              capture_output=True, timeout=60)
        assert done.returncode == 0, (args, done.stderr)

    git(source, "init", "-q", "-b", "main")
    git(source, "add", "-A", "-f", ".")
    git(source, "commit", "-qm", "one")
    subprocess.run(["git", "clone", "-q", "--bare", source, remote], check=True, env=git_env)
    subprocess.run(["git", "clone", "-q", remote, clone], check=True, env=git_env)
    done = subprocess.run(["bash", os.path.join(clone, "install.sh"), "--settings-only", "--yes"],
                          env=env, text=True, capture_output=True, timeout=120,
                          stdin=subprocess.DEVNULL)
    assert done.returncode == 0, done.stdout + done.stderr
    stamp_everything(env, clone)

    def update_to(target):
        # The updater stashes the checkout repo-path names and resets its branch,
        # and every run of install.sh rewrites repo-path to its own directory. Run
        # against this repository it would take the working tree with it.
        with open(os.path.join(conf, "repo-path"), encoding="utf-8") as stream:
            named = os.path.realpath(stream.read().strip())
        assert named == os.path.realpath(clone), "repo-path left the fixture: %s" % named
        return subprocess.run(["bash", os.path.join(clone, "bin/aura-glass-update"), target],
                              env=env, text=True, timeout=180, capture_output=True,
                              stdin=subprocess.DEVNULL)

    git(source, "remote", "add", "origin", remote)
    with open(os.path.join(source, "bin/aura-glass-settings"), "a", encoding="utf-8") as stream:
        stream.write("\n# from the remote\n")
    git(source, "commit", "-qam", "two")
    git(source, "push", "-q", "origin", "main")
    # A release from before there were parts: its install.sh knows no --update.
    git(source, "checkout", "-qb", "old")
    with open(os.path.join(source, "install.sh"), "w", encoding="utf-8") as stream:
        stream.write('#!/bin/sh\necho "$@" > "$HOME/old-install-ran"\n')
    git(source, "commit", "-qam", "old release")
    git(source, "tag", "v0.0.1")
    git(source, "push", "-q", "origin", "v0.0.1")

    sudo_log = env["AG_STATE"] + ".sudo"
    if os.path.exists(sudo_log):
        os.remove(sudo_log)
    done = update_to("main")
    assert done.returncode == 0, done.stdout + done.stderr
    assert "running only what changed: gui" in done.stdout, done.stdout[-1500:]
    assert not os.path.exists(sudo_log), "asked for sudo with nothing outside the home folder"
    with open(os.path.join(env["HOME"], ".local/bin/aura-glass-settings"), encoding="utf-8") as stream:
        assert "# from the remote" in stream.read()

    done = update_to("v0.0.1")
    assert done.returncode == 0, done.stdout + done.stderr
    with open(os.path.join(env["HOME"], "old-install-ran"), encoding="utf-8") as stream:
        assert stream.read().strip() == "--gui"
    # Nothing recorded survives a copy that does not keep the record.
    assert not os.path.exists(os.path.join(conf, "installed-parts"))


def snapshot(home):
    """What a run leaves behind that the desktop or the next run reads."""
    seen = {}
    with open(os.path.join(home, "state.json"), encoding="utf-8") as stream:
        seen.update({"key " + k: v for k, v in json.load(stream).items()})
    for base in (".config/aura-glass", ".config/gtk-4.0", ".config/gtk-3.0",
                 ".themes/Aura-Glass/gnome-shell"):
        top = os.path.join(home, base)
        for folder, _dirs, names in os.walk(top):
            for name in names:
                path = os.path.join(folder, name)
                rel = os.path.relpath(path, home)
                if name in ("installed-parts",) or "last-install" in rel \
                        or "backups" in rel or name.endswith(".lock"):
                    continue
                with open(path, "rb") as stream:
                    seen["file " + rel] = stream.read()
    return seen


def check_equivalence(temp, home, stubs):
    """A narrow Apply must leave what the retune it replaces would."""
    # Seed once with a real retune, then each flag starts from a copy of that.
    env = environ(home, stubs)
    # A pack that follows the accent, in both colours, so --accent has to move it.
    for colour in ("purple", "green"):
        os.makedirs(os.path.join(home, ".local/share/icons/Reversal-%s-dark" % colour))
    with open(os.path.join(home, ".config/aura-glass/icon-pack"), "w", encoding="utf-8") as stream:
        stream.write("reversal\n")
    # Twice: the first run from an empty fixture seeds the drawers, and only the
    # second comes back to what they say, as every run on a real install does.
    for _ in range(2):
        seeded = run(env, "--settings-only", "--yes")
        assert seeded.returncode == 0, seeded.stdout + seeded.stderr
    stamp_everything(env)
    seed = snapshot(home)

    cases = (
        ("--accent", "green"),
        ("--app-tint-color", "#112233"),
        ("--app-transparency", "0.82"),
        ("--radius-preset", "soft"),
        ("--no-popup-blur",),
        ("--no-window-blur",),
        ("--gtk-apps-blur",),
        ("--glass-style", "liquid"),
        ("--liquid-windows",),
        ("--no-update-check",),
        ("--no-window-menu",),
        ("--no-top-bar-icon",),
        ("--no-icons",),
        ("--font", "inter"),
        ("--window-buttons", "all"),
        ("--blur-strength", "120"),
        ("--maximized-blur", "dynamic"),
        ("--osd-style", "tab"),
        ("--system-icons", "pack"),
    )
    failures = []
    for flags in cases:
        results = []
        for mode in (("--settings-only",), ("--settings-only", "--incremental")):
            work = os.path.join(temp, "work")
            shutil.rmtree(work, ignore_errors=True)
            shutil.copytree(home, work, symlinks=True)
            case_env = environ(work, stubs)
            if len(mode) == 2:
                # With a part selected the whole look would run, and pass this
                # comparison without the narrow step doing anything.
                selected = apply_plan(case_env, *flags)
                assert selected["parts"] == [], (flags, selected)
            done = run(case_env, *mode, "--yes", *flags)
            assert done.returncode == 0, (flags, mode, done.stdout, done.stderr)
            if len(mode) == 2:
                assert "Applying changed settings only" in done.stdout, \
                    (flags, done.stdout[-400:])
            results.append(snapshot(work))
        full, narrow = results
        assert full != seed, "%s changed nothing, so this proves nothing" % (flags,)
        for key in sorted(set(full) | set(narrow)):
            if full.get(key) != narrow.get(key):
                failures.append("%s: %s differs" % (" ".join(flags), key))
    assert not failures, "narrow Apply is not the retune:\n  " + "\n  ".join(failures)


def main():
    with tempfile.TemporaryDirectory() as temp:
        home, stubs = fixture(temp)
        env = environ(home, stubs)
        check_classes(env)
        check_coverage(env)
        check_selection(temp, env)
        check_update_run(temp, env)
        check_updater(temp, env)
    with tempfile.TemporaryDirectory() as temp:
        home, stubs = fixture(temp)
        check_equivalence(temp, home, stubs)
    print("check-incremental-apply: OK")


if __name__ == "__main__":
    main()
