#!/usr/bin/env python3
"""Deterministic lifecycle checks for the settings preview queue."""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "gui"))

from preview_queue import PreviewQueue


def check_replaces_pending_preview():
    started = []
    queue = PreviewQueue(
        lambda kind, argv, generation: started.append((kind, argv, generation)))
    queue.request_preview(("A",))
    queue.request_preview(("B",))
    queue.request_preview(("C",))
    assert len(started) == 1
    queue.finish(started[0][2])
    assert [entry[1] for entry in started] == [("A",), ("C",)]
    queue.finish(started[0][2])
    assert len(started) == 2


def check_terminal_drops_pending_preview():
    started = []
    queue = PreviewQueue(
        lambda kind, argv, generation: started.append((kind, argv, generation)))
    queue.request_preview(("A",))
    queue.request_preview(("B",))
    queue.request_terminal("apply", ("apply",))
    queue.request_preview(("C",))
    queue.finish(started[0][2])
    assert [(kind, argv) for kind, argv, _ in started] == [
        ("preview", ("A",)), ("apply", ("apply",))]
    queue.finish(started[1][2])
    assert len(started) == 2


def check_revert_drops_pending_preview():
    started = []
    queue = PreviewQueue(
        lambda kind, argv, generation: started.append((kind, argv, generation)))
    queue.request_preview(("A",))
    queue.request_preview(("B",))
    queue.request_terminal("revert", ("revert",))
    queue.finish(started[0][2])
    assert [(kind, argv) for kind, argv, _ in started] == [
        ("preview", ("A",)), ("revert", ("revert",))]


def check_terminal_is_not_duplicated():
    started = []
    queue = PreviewQueue(
        lambda kind, argv, generation: started.append((kind, argv, generation)))
    queue.request_preview(("A",))
    queue.request_terminal("apply", ("apply",))
    queue.request_terminal("revert", ("revert",))
    queue.finish(started[0][2])
    assert [(kind, argv) for kind, argv, _ in started] == [
        ("preview", ("A",)), ("apply", ("apply",))]


def check_launch_failure_releases_once():
    started = []

    def launch(kind, argv, generation):
        started.append((kind, argv, generation))
        raise RuntimeError("cannot create subprocess")

    queue = PreviewQueue(launch)
    queue.request_preview(("A",))
    queue.request_preview(("B",))
    assert [entry[1] for entry in started] == [("A",), ("B",)]


def check_terminal_launch_failure_does_not_block_later_preview():
    started = []

    def launch(kind, argv, generation):
        started.append((kind, argv, generation))
        if kind == "apply":
            raise RuntimeError("cannot create subprocess")

    queue = PreviewQueue(launch)
    queue.request_terminal("apply", ("apply",))
    queue.request_preview(("A",))
    assert [(kind, argv) for kind, argv, _ in started] == [
        ("apply", ("apply",)), ("preview", ("A",))]


def main():
    check_replaces_pending_preview()
    check_terminal_drops_pending_preview()
    check_revert_drops_pending_preview()
    check_terminal_is_not_duplicated()
    check_launch_failure_releases_once()
    check_terminal_launch_failure_does_not_block_later_preview()
    print("check-preview-queue: OK")


if __name__ == "__main__":
    main()
