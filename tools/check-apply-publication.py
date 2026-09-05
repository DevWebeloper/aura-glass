#!/usr/bin/env python3
"""Fixture checks for atomic, quiet Aura Glass CSS publication."""
import json
import os
import stat
import subprocess
import tempfile


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPLY = os.path.join(ROOT, "bin", "aura-glass-apply")


def write(path, content, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as stream:
        stream.write(content)
    os.chmod(path, mode)


def fixture():
    temp = tempfile.TemporaryDirectory()
    home = os.path.join(temp.name, "home")
    config = os.path.join(home, ".config", "aura-glass")
    theme = os.path.join(home, ".themes", "Aura-Glass", "gnome-shell", "gnome-shell.css")
    gtk4 = os.path.join(home, ".config", "gtk-4.0", "gtk.css")
    gtk4_dark = os.path.join(home, ".config", "gtk-4.0", "gtk-dark.css")
    gtk3 = os.path.join(home, ".config", "gtk-3.0", "gtk.css")
    for path in (theme, gtk4, gtk4_dark):
        write(path, ".surface { box-shadow: 0 1px; background-image: linear-gradient(#3584e4, #3484e2); }\n")
    write(gtk3, "/* User GTK3 rule that must survive. */\n.user { color: red; }\n")
    write(os.path.join(config, "shell-00-flat.css"), ".shell { color: white; }\n")
    write(os.path.join(config, "gtk4-00-flat.css"), ".gtk { color: white; }\n")
    write(os.path.join(config, "gtk3-tweaks.css"), ".gtk3 { color: white; }\n")
    link_target = os.path.join(temp.name, "linked-dark.css")
    os.rename(gtk4_dark, link_target)
    os.symlink(link_target, gtk4_dark)

    bindir = os.path.join(temp.name, "bin")
    os.makedirs(bindir)
    log = os.path.join(temp.name, "commands.log")
    write(os.path.join(bindir, "dconf"), "#!/bin/sh\nprintf 'dconf %s\\n' \"$*\" >> \"$AURA_TEST_LOG\"\n", 0o755)
    write(os.path.join(bindir, "gsettings"), "#!/bin/sh\nprintf 'gsettings %s\\n' \"$*\" >> \"$AURA_TEST_LOG\"\ncase \"$1\" in get) printf \"'Aura-Glass'\\n\";; esac\n", 0o755)
    write(os.path.join(bindir, "sleep"), "#!/bin/sh\nprintf 'sleep %s\\n' \"$*\" >> \"$AURA_TEST_LOG\"\n", 0o755)
    os.makedirs(os.path.join(home, ".local", "share", "gnome-shell", "extensions", "user-theme@gnome-shell-extensions.gcampax.github.com", "schemas"))
    env = os.environ | {
        "HOME": home,
        "PATH": bindir + os.pathsep + os.environ["PATH"],
        "AURA_TEST_LOG": log,
        "AURA_GLASS_THEME": "Aura-Glass",
    }
    return temp, env, (theme, gtk4, gtk4_dark, gtk3), log, config


def run(env, *args):
    result = subprocess.run([APPLY, "--json", *args], env=env, text=True,
                            capture_output=True, timeout=15)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def reload_count(log):
    with open(log, encoding="utf-8") as stream:
        return sum(line.startswith("gsettings set ") for line in stream)


def check_quiet_reapply_and_gtk_only_reload():
    temp, env, targets, log, config = fixture()
    try:
        first = run(env)
        assert first["schema_version"] == 1
        assert set(first["changed_targets"]) == set(targets)
        assert first["shell_reload"] == "reloaded"
        assert first["gtk_restart_required"] is True
        assert os.path.islink(targets[2]), "publication replaced a GTK symlink"
        assert ".user { color: red; }" in open(targets[3], encoding="utf-8").read()
        before = [(open(path, "rb").read(), os.stat(path).st_mtime_ns) for path in targets]
        first_reloads = reload_count(log)
        second = run(env)
        after = [(open(path, "rb").read(), os.stat(path).st_mtime_ns) for path in targets]
        assert second["changed_targets"] == []
        assert second["shell_reload"] == "unchanged"
        assert before == after
        assert reload_count(log) == first_reloads
        write(os.path.join(config, "gtk4-00-flat.css"), ".gtk { color: black; }\n")
        gtk_only = run(env)
        assert gtk_only["changed_targets"] == [targets[1], targets[2]]
        assert gtk_only["shell_reload"] == "unchanged"
        assert gtk_only["gtk_restart_required"] is True
        assert reload_count(log) == first_reloads
        forced = run(env, "--force-reload")
        assert forced["changed_targets"] == []
        assert forced["shell_reload"] == "reloaded"
    finally:
        temp.cleanup()


def main():
    check_quiet_reapply_and_gtk_only_reload()
    print("check-apply-publication: OK")


if __name__ == "__main__":
    main()
