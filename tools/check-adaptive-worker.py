#!/usr/bin/env python3
"""Deterministic unit and integration tests for aura-glass-adaptive worker."""
import os
import sys
import tempfile
from unittest.mock import patch

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from aura_glass_adaptive import (
    AdaptiveReducer,
    read_fullscreen_apps,
    write_fullscreen_apps,
    selected_profile,
    set_profile,
    sample,
)


def test_reducer_profiles():
    reducer = AdaptiveReducer(sustained=3)

    # Full profile always disables performance mode regardless of triggers
    active, reason = reducer.desired(
        profile="full",
        fullscreen_now=True,
        focused_wm_class="steam_app_123",
        battery_now=True,
        gpu_load=95,
        fullscreen_apps={"steam_app_123"},
    )
    assert not active, "full profile must never be active"
    assert reason == "full-glass"

    # Performance profile is always active with reason "performance"
    active, reason = reducer.desired(
        profile="performance",
        fullscreen_now=False,
        focused_wm_class=None,
        battery_now=False,
        gpu_load=10,
        fullscreen_apps=set(),
    )
    assert active, "performance profile must always be active"
    assert reason == "performance"


def test_reducer_battery_trigger():
    reducer = AdaptiveReducer(sustained=3)

    # Auto profile: on battery discharge triggers immediately
    active, reason = reducer.desired(
        profile="auto",
        fullscreen_now=False,
        focused_wm_class=None,
        battery_now=True,
        gpu_load=15,
        fullscreen_apps=set(),
    )
    assert active
    assert reason == "battery"

    # Back on AC power
    active, reason = reducer.desired(
        profile="auto",
        fullscreen_now=False,
        focused_wm_class=None,
        battery_now=False,
        gpu_load=15,
        fullscreen_apps=set(),
    )
    assert not active
    assert reason == "normal"


def test_reducer_gpu_hysteresis():
    reducer = AdaptiveReducer(sustained=3)

    # Sample 1: high GPU, but need 3 consecutive samples
    active, reason = reducer.desired("auto", False, None, False, 85, set())
    assert not active
    assert reason == "normal"

    # Sample 2: high GPU
    active, reason = reducer.desired("auto", False, None, False, 88, set())
    assert not active
    assert reason == "normal"

    # Sample 3: high GPU -> triggers!
    active, reason = reducer.desired("auto", False, None, False, 82, set())
    assert active
    assert reason == "gpu"

    # Hysteresis: stays active above 65% even if below 80%
    active, reason = reducer.desired("auto", False, None, False, 75, set())
    assert active
    assert reason == "gpu"

    active, reason = reducer.desired("auto", False, None, False, 66, set())
    assert active
    assert reason == "gpu"

    # Drops below 65% -> clears
    active, reason = reducer.desired("auto", False, None, False, 60, set())
    assert not active
    assert reason == "normal"


def test_reducer_fullscreen_app():
    reducer = AdaptiveReducer(sustained=3)
    apps = {"hl2_linux", "steam_app_400"}

    # Not fullscreen
    active, reason = reducer.desired("auto", False, "hl2_linux", False, 20, apps)
    assert not active

    # Fullscreen and focused
    active, reason = reducer.desired("auto", True, "hl2_linux", False, 20, apps)
    assert active
    assert reason == "game"

    # Focus lost to another non-game app
    active, reason = reducer.desired("auto", True, "firefox", False, 20, apps)
    assert not active

    # Unfullscreened
    active, reason = reducer.desired("auto", False, "hl2_linux", False, 20, apps)
    assert not active


def test_reducer_multiple_reasons():
    reducer = AdaptiveReducer(sustained=1)
    apps = {"game.exe"}

    # Trigger all three: battery, gpu, game
    # Sustained is 1 so GPU triggers on 1st sample
    active, reason = reducer.desired("auto", True, "game.exe", True, 90, apps)
    assert active
    assert reason == "battery, gpu, game"

    # Battery removed, game still running
    active, reason = reducer.desired("auto", True, "game.exe", False, 50, apps)
    assert active
    # GPU cleared (<65) so only game remains
    assert reason == "game"


def test_reducer_missing_data():
    reducer = AdaptiveReducer(sustained=3)

    # Hardware/Shell data missing (None values) should not fail or trigger
    active, reason = reducer.desired("auto", None, None, None, None, set())
    assert not active
    assert reason == "normal"


def test_config_persistence():
    with tempfile.TemporaryDirectory() as tmp:
        # Profile persistence
        assert selected_profile(tmp) == "auto"
        set_profile(tmp, "performance")
        assert selected_profile(tmp) == "performance"
        set_profile(tmp, "full")
        assert selected_profile(tmp) == "full"

        # Fullscreen apps atomic write and read
        test_apps = {"retroarch", "steam_app_1234", "super_tux"}
        write_fullscreen_apps(tmp, test_apps)
        loaded = read_fullscreen_apps(tmp)
        assert loaded == test_apps

        # App list formatting handles blank lines and comments
        path = os.path.join(tmp, "adaptive-fullscreen-apps")
        with open(path, "a", encoding="utf-8") as f:
            f.write("\n# Comment\n  \n")
        assert read_fullscreen_apps(tmp) == test_apps


def test_sample_lifecycle():
    with tempfile.TemporaryDirectory() as tmp:
        reducer = AdaptiveReducer(sustained=1)
        calls = []

        def mock_installer(directory, action):
            calls.append(action)

        with patch("aura_glass_adaptive.on_battery", return_value=True), \
             patch("aura_glass_adaptive.gpu_busy_percent", return_value=None), \
             patch("aura_glass_adaptive.focus_state", return_value=(False, "")), \
             patch("aura_glass_adaptive.installer", side_effect=mock_installer):

            # Battery discharging triggers transition to active
            sample(reducer, tmp, force=True)
            assert calls == ["active"]
            assert os.path.exists(os.path.join(tmp, "adaptive-performance", "active"))
            with open(os.path.join(tmp, "adaptive-performance", "active")) as f:
                assert f.read().strip() == "1"
            with open(os.path.join(tmp, "adaptive-performance", "reason")) as f:
                assert f.read().strip() == "battery"

            # Repeat sample with same state: no duplicate installer call
            calls.clear()
            sample(reducer, tmp, force=False)
            assert calls == []

        # Now switch to on AC power
        with patch("aura_glass_adaptive.on_battery", return_value=False), \
             patch("aura_glass_adaptive.gpu_busy_percent", return_value=None), \
             patch("aura_glass_adaptive.focus_state", return_value=(False, "")), \
             patch("aura_glass_adaptive.installer", side_effect=mock_installer):

            sample(reducer, tmp, force=True)
            assert calls == ["restore"]
            with open(os.path.join(tmp, "adaptive-performance", "active")) as f:
                assert f.read().strip() == "0"
            with open(os.path.join(tmp, "adaptive-performance", "reason")) as f:
                assert f.read().strip() == "normal"


def main():
    test_reducer_profiles()
    test_reducer_battery_trigger()
    test_reducer_gpu_hysteresis()
    test_reducer_fullscreen_app()
    test_reducer_multiple_reasons()
    test_reducer_missing_data()
    test_config_persistence()
    test_sample_lifecycle()
    print("adaptive-worker check passed — profiles, triggers, hysteresis, reasons and lifecycle all verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
