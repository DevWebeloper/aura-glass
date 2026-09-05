#!/usr/bin/env python3
"""Controlled process checks for the Aura Glass writer coordinator."""
import os
import fcntl
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OPERATION = os.path.join(ROOT, "tools", "aura_glass_operation.py")
sys.path.insert(0, os.path.join(ROOT, "tools"))

from aura_glass_operation import parse_app_blur


def check_writer_lock_and_release():
    with tempfile.TemporaryDirectory() as tmp:
        env = os.environ | {"HOME": tmp, "AURA_GLASS_OPERATION_TIMEOUT": "0.1"}
        first = subprocess.Popen(
            [sys.executable, OPERATION, "run", "--", sys.executable, "-c",
             "import sys; print('ready', flush=True); sys.stdin.read(1)"],
            env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        try:
            assert first.stdout.readline().strip() == "ready"
            second = subprocess.run(
                [sys.executable, OPERATION, "run", "--", sys.executable,
                 "-c", "print('entered')"], env=env, text=True,
                capture_output=True, timeout=35)
            assert second.returncode == 1
            assert "another theme operation is running" in second.stderr
            first.stdin.write("x")
            first.stdin.flush()
            assert first.wait(timeout=5) == 0
            third = subprocess.run(
                [sys.executable, OPERATION, "run", "--", sys.executable,
                 "-c", "print('entered')"], env=env, text=True,
                capture_output=True, timeout=5)
            assert third.returncode == 0
            assert third.stdout.strip() == "entered"
        finally:
            if first.poll() is None:
                first.kill()
                first.wait()


def check_held_requires_the_real_lock_descriptor():
    with tempfile.TemporaryDirectory() as tmp:
        env = os.environ | {"HOME": tmp}
        assert subprocess.run([sys.executable, OPERATION, "held"], env=env,
                              capture_output=True).returncode == 1
        path = os.path.join(tmp, ".cache", "aura-glass", "operation.lock")
        os.makedirs(os.path.dirname(path))
        fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            held_env = env | {"AURA_GLASS_OPERATION_FD": str(fd)}
            held = subprocess.run([sys.executable, OPERATION, "held"],
                                  env=held_env, pass_fds=(fd,),
                                  capture_output=True)
            assert held.returncode == 0
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)


def check_app_blur_contract():
    assert parse_app_blur([
        "--wm-class", "org.example.Editor", "--enabled", "1",
    ]) == ("org.example.Editor", "1")
    assert parse_app_blur([
        "--enabled", "0", "--wm-class", "org.example.Editor",
    ]) == ("org.example.Editor", "0")
    for argv in (
            [], ["--wm-class", "org.example.Editor"],
            ["--enabled", "1"],
            ["--wm-class", "", "--enabled", "1"],
            ["--wm-class", "org.example.Editor", "--enabled", "yes"],
            ["--unknown", "x"]):
        try:
            parse_app_blur(argv)
        except ValueError:
            pass
        else:
            raise AssertionError("invalid app-blur arguments accepted: %r" % (argv,))


def check_app_blur_uses_the_canonical_backend():
    launcher = os.path.join(ROOT, "bin", "aura-glass-operation")
    with tempfile.TemporaryDirectory() as tmp:
        home = os.path.join(tmp, "home")
        bindir = os.path.join(tmp, "bin")
        config = os.path.join(home, ".config", "aura-glass")
        os.makedirs(bindir)
        os.makedirs(config)
        with open(os.path.join(config, "repo-path"), "w", encoding="utf-8") as stream:
            stream.write(ROOT + "\n")
        with open(os.path.join(config, "app-blur-allow"), "w", encoding="utf-8") as stream:
            stream.write("*editor*\n")
        with open(os.path.join(config, "app-blur-block"), "w", encoding="utf-8") as stream:
            stream.write("*editor*\n")
        dconf = os.path.join(bindir, "dconf")
        with open(dconf, "w", encoding="utf-8") as stream:
            stream.write("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$AURA_TEST_DCONF_LOG\"\n")
        os.chmod(dconf, 0o755)
        log = os.path.join(tmp, "dconf.log")
        env = os.environ | {
            "HOME": home,
            "PATH": bindir + os.pathsep + os.environ["PATH"],
            "AURA_TEST_DCONF_LOG": log,
        }
        result = subprocess.run(
            [launcher, "app-blur", "--wm-class", "org.example.Editor",
             "--enabled", "1"], env=env, text=True, capture_output=True,
            timeout=10)
        assert result.returncode == 0, result.stderr
        assert open(os.path.join(config, "app-blur-allow"), encoding="utf-8").read().splitlines() == [
            "io.github.DevWebeloper.AuraGlassSettings", "*editor*"]
        block = open(os.path.join(config, "app-blur-block"), encoding="utf-8").read().splitlines()
        assert not any(block), block
        assert "write /org/gnome/shell/extensions/blur-my-shell/applications/whitelist" in open(
            log, encoding="utf-8").read()


def check_window_menu_delegates_app_blur():
    extension = os.path.join(
        ROOT, "extensions", "aura-glass-blur@aura-glass.local", "extension.js")
    source = open(extension, encoding="utf-8").read()
    toggle = source[source.index("    _toggleBlur("):source.index(
        "    // ---- D-Bus bridge", source.index("    _toggleBlur("))]
    assert "aura-glass-operation" in toggle
    assert "communicate_utf8_async" in toggle
    assert "set_strv('whitelist'" not in toggle
    assert "set_strv('blacklist'" not in toggle


def check_preview_does_not_reinstall_operation_helpers():
    source = open(os.path.join(ROOT, "lib", "steps-css.sh"),
                  encoding="utf-8").read()
    install = source[source.index("install_css() {"):]
    start = install.index('if [ "${PREVIEW_MODE:-0}" != 1 ]; then')
    end = install.index("    fi", start)
    artifact_install = install[start:end]
    assert 'aura_glass_operation.py' in artifact_install
    assert 'aura-glass-operation' in artifact_install
    assert 'aura-glass-apply' in artifact_install
    assert 'tahoe-glass-apply' in artifact_install


def main():
    check_writer_lock_and_release()
    check_held_requires_the_real_lock_descriptor()
    check_app_blur_contract()
    check_app_blur_uses_the_canonical_backend()
    check_window_menu_delegates_app_blur()
    check_preview_does_not_reinstall_operation_helpers()
    print("check-operation-recovery: OK")


if __name__ == "__main__":
    main()
