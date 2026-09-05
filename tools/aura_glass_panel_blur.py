#!/usr/bin/env python3
"""Coalesce monitor-layout events before rebuilding Blur My Shell's panel."""
import os
import selectors
import subprocess
import sys
import time


class PanelBlurReducer:
    """One settle deadline, never an unbounded queue of monitor events."""

    def __init__(self, settle, enabled, try_lock, rebuild):
        self.settle = settle
        self.enabled = enabled
        self.try_lock = try_lock
        self.rebuild = rebuild
        self.deadline = None

    def event(self, now):
        self.deadline = now + self.settle

    def advance(self, now):
        if self.deadline is None or now < self.deadline:
            return
        if not self.enabled():
            self.deadline = None
            return
        if not self.try_lock():
            self.deadline = now + min(1, self.settle)
            return
        self.deadline = None
        if self.enabled():
            self.rebuild()


KEY = "/org/gnome/shell/extensions/blur-my-shell/panel/blur"


def config_dir():
    return os.environ.get("AURA_GLASS_DIR", os.path.join(os.path.expanduser("~"), ".config", "aura-glass"))


def enabled():
    directory = config_dir()
    if os.path.exists(os.path.join(directory, "styling-off")):
        return False
    try:
        if open(os.path.join(directory, "panel-blur-fix"), encoding="utf-8").read().strip() != "1":
            return False
    except FileNotFoundError:
        pass
    value = subprocess.run(["dconf", "read", KEY], text=True, capture_output=True,
                           timeout=3).stdout.strip()
    return value == "true"


def rebuild():
    # The operation launcher owns the advisory writer lock for the complete
    # false/true handshake. An external repeated false write while false is
    # still inherently indistinguishable from ours; dconf has no ownership API.
    operation = os.environ.get("AURA_GLASS_OPERATION", "aura-glass-operation")
    command = 'dconf write "$1" false; sleep 1; dconf write "$1" true'
    result = subprocess.run([operation, "run", "--", "bash", "-c", command, "_", KEY],
                            text=True, timeout=35)
    if result.returncode:
        raise RuntimeError("panel blur rebuild did not complete")


def main():
    settle = float(os.environ.get("AURA_GLASS_BLUR_SETTLE",
                                  os.environ.get("TAHOE_GLASS_BLUR_SETTLE", "3")))
    reducer = PanelBlurReducer(settle, enabled, lambda: True, rebuild)
    monitor = subprocess.Popen(
        ["gdbus", "monitor", "--session", "--dest", "org.gnome.Mutter.DisplayConfig",
         "--object-path", "/org/gnome/Mutter/DisplayConfig"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    assert monitor.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(monitor.stdout, selectors.EVENT_READ)
    reducer.event(time.monotonic())
    try:
        while True:
            now = time.monotonic()
            timeout = 1 if reducer.deadline is None else max(0, min(1, reducer.deadline - now))
            for _, _ in selector.select(timeout):
                line = monitor.stdout.readline()
                if not line:
                    raise RuntimeError("Mutter monitor session bus is unavailable")
                if "MonitorsChanged" in line:
                    reducer.event(time.monotonic())
            reducer.advance(time.monotonic())
            if monitor.poll() is not None:
                raise RuntimeError("Mutter monitor exited")
    finally:
        monitor.terminate()
        try:
            monitor.wait(timeout=2)
        except subprocess.TimeoutExpired:
            monitor.kill()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("aura-glass-panel-blur:", error, file=sys.stderr)
        raise SystemExit(1)
