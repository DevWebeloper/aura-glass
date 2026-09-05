#!/usr/bin/env python3
"""Small process coordinator for Aura Glass's project-owned writers."""
import fcntl
import os
import signal
import stat
import subprocess
import sys
import time


LOCK_ENV = "AURA_GLASS_OPERATION_FD"


def lock_path():
    return os.path.join(os.path.expanduser("~"), ".cache", "aura-glass",
                        "operation.lock")


def inherited_lock(path):
    raw = os.environ.get(LOCK_ENV)
    if raw is None:
        return None
    try:
        fd = int(raw)
        got, expected = os.fstat(fd), os.stat(path)
    except (OSError, ValueError):
        return None
    if not stat.S_ISREG(got.st_mode) or (got.st_dev, got.st_ino) != (
            expected.st_dev, expected.st_ino):
        return None
    return fd


def acquire(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    timeout = float(os.environ.get("AURA_GLASS_OPERATION_TIMEOUT", "30"))
    deadline = time.monotonic() + timeout
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd, True
        except BlockingIOError:
            if time.monotonic() >= deadline:
                os.close(fd)
                raise TimeoutError("another theme operation is running")
            time.sleep(min(.05, max(0, deadline - time.monotonic())))


def run(command):
    path = lock_path()
    fd = inherited_lock(path)
    owned = False
    if fd is None:
        try:
            fd, owned = acquire(path)
        except TimeoutError as exc:
            print("aura-glass-operation: %s" % exc, file=sys.stderr)
            return 1
    os.set_inheritable(fd, True)
    env = os.environ.copy()
    env[LOCK_ENV] = str(fd)
    child = subprocess.Popen(command, env=env, pass_fds=(fd,))

    def forward(signum, _frame):
        if child.poll() is None:
            child.send_signal(signum)

    old_int = signal.signal(signal.SIGINT, forward)
    old_term = signal.signal(signal.SIGTERM, forward)
    try:
        return child.wait()
    finally:
        signal.signal(signal.SIGINT, old_int)
        signal.signal(signal.SIGTERM, old_term)
        if owned:
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)


def parse_app_blur(argv):
    """Validate the narrow window-menu operation before it reaches Bash."""
    wm_class = None
    enabled = None
    index = 0
    while index < len(argv):
        option = argv[index]
        if option not in ("--wm-class", "--enabled") or index + 1 >= len(argv):
            raise ValueError("expected --wm-class CLASS and --enabled 0|1")
        value = argv[index + 1]
        if option == "--wm-class":
            if wm_class is not None or not value or "\n" in value or "\r" in value:
                raise ValueError("--wm-class must be one non-empty line")
            wm_class = value
        else:
            if enabled is not None or value not in ("0", "1"):
                raise ValueError("--enabled must be 0 or 1")
            enabled = value
        index += 2
    if wm_class is None or enabled is None:
        raise ValueError("expected --wm-class CLASS and --enabled 0|1")
    return wm_class, enabled


def run_app_blur(argv):
    try:
        wm_class, enabled = parse_app_blur(argv)
    except ValueError as exc:
        print("aura-glass-operation: %s" % exc, file=sys.stderr)
        return 2
    preview = os.environ.get(
        "AURA_GLASS_OPERATION_PREVIEW",
        os.path.join(os.path.expanduser("~"), ".local", "bin",
                     "aura-glass-preview"))
    return run([preview, "app-blur", "--wm-class", wm_class,
                "--enabled", enabled])


def main(argv):
    if len(argv) == 2 and argv[1] == "held":
        return 0 if inherited_lock(lock_path()) is not None else 1
    if len(argv) >= 2 and argv[1] == "app-blur":
        return run_app_blur(argv[2:])
    if len(argv) < 3 or argv[1] != "run" or argv[2] != "--":
        print("usage: aura-glass-operation run -- COMMAND [ARG...]", file=sys.stderr)
        return 2
    return run(argv[3:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
