#!/usr/bin/env python3
"""Deterministic checks for collapsing panel-blur monitor events."""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import aura_glass_panel_blur as panel
from aura_glass_panel_blur import PanelBlurReducer


def check_burst_collapses():
    calls = []
    reducer = PanelBlurReducer(3, lambda: True, lambda: True, lambda: calls.append("rebuild"))
    reducer.event(0); reducer.event(1); reducer.event(2); reducer.advance(5)
    assert calls == ["rebuild"]


def check_disabled_and_solid_skip():
    calls = []
    enabled = [True]
    reducer = PanelBlurReducer(3, lambda: enabled[0], lambda: True, lambda: calls.append("rebuild"))
    reducer.event(0); enabled[0] = False; reducer.advance(3)
    assert calls == []
    enabled[0] = True
    reducer.event(4); enabled[0] = False; reducer.advance(7)
    assert calls == []


def check_busy_operation_keeps_one_pending_rebuild():
    calls = []
    free = [False]
    reducer = PanelBlurReducer(3, lambda: True, lambda: free[0], lambda: calls.append("rebuild"))
    reducer.event(0); reducer.advance(3)
    reducer.event(4); free[0] = True; reducer.advance(7)
    assert calls == ["rebuild"]


def check_rebuild_passes_the_real_dconf_key_to_the_shell():
    commands = []
    original = panel.subprocess.run
    panel.subprocess.run = lambda argv, **_kwargs: commands.append(argv) or type("Result", (), {"returncode": 0})()
    try:
        panel.rebuild()
    finally:
        panel.subprocess.run = original
    assert 'dconf write "$1" false' in commands[0][5]


def main():
    check_burst_collapses()
    check_disabled_and_solid_skip()
    check_busy_operation_keeps_one_pending_rebuild()
    check_rebuild_passes_the_real_dconf_key_to_the_shell()
    print("check-panel-blur-events: OK")


if __name__ == "__main__":
    main()
