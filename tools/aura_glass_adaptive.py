#!/usr/bin/env python3
"""Apply Aura Glass's transient performance blur only while a trigger holds."""
import glob
import os
import re
import subprocess
import sys
import time


BUS_NAME = "io.github.DevWebeloper.AuraGlass"
OBJECT_PATH = "/io/github/DevWebeloper/AuraGlass"
INTERFACE = "io.github.DevWebeloper.AuraGlass"
PROFILES = ("auto", "full", "performance")
GPU_ENTER = 80
GPU_CLEAR = 65


def config_dir():
    return os.environ.get(
        "AURA_GLASS_DIR",
        os.environ.get("TAHOE_GLASS_DIR",
                       os.path.join(os.path.expanduser("~"), ".config", "aura-glass")))


def read_text(path):
    try:
        with open(path, encoding="utf-8") as stream:
            return stream.read().strip()
    except OSError:
        return None


def selected_profile(directory):
    profile = read_text(os.path.join(directory, "adaptive-profile"))
    return profile if profile in PROFILES else "auto"


def set_profile(directory, profile):
    os.makedirs(directory, exist_ok=True)
    temporary = os.path.join(directory, ".adaptive-profile.tmp")
    with open(temporary, "w", encoding="utf-8") as stream:
        stream.write(profile + "\n")
    os.replace(temporary, os.path.join(directory, "adaptive-profile"))


def read_fullscreen_apps(directory):
    path = os.path.join(directory, "adaptive-fullscreen-apps")
    content = read_text(path)
    if not content:
        return set()
    return {line.strip() for line in content.splitlines() if line.strip() and not line.strip().startswith("#")}


def write_fullscreen_apps(directory, apps):
    os.makedirs(directory, exist_ok=True)
    temporary = os.path.join(directory, ".adaptive-fullscreen-apps.tmp")
    with open(temporary, "w", encoding="utf-8") as stream:
        for app in sorted(set(apps)):
            if app.strip():
                stream.write(app.strip() + "\n")
    os.replace(temporary, os.path.join(directory, "adaptive-fullscreen-apps"))


def on_battery():
    """Return true only for a readable system Battery status that says Discharging."""
    for supply in glob.glob("/sys/class/power_supply/*"):
        if read_text(os.path.join(supply, "type")) != "Battery":
            continue
        scope = read_text(os.path.join(supply, "scope"))
        if scope == "Device" or os.path.basename(supply).startswith("hidpp_"):
            continue
        if read_text(os.path.join(supply, "status")) == "Discharging":
            return True
    return False


def gpu_busy_percent():
    """Return the highest supported DRM busy reading, or None when unavailable."""
    readings = []
    for path in glob.glob("/sys/class/drm/card*/device/gpu_busy_percent"):
        value = read_text(path)
        try:
            readings.append(float(value))
        except (TypeError, ValueError):
            continue
    return max(readings) if readings else None


def focus_state():
    """Ask the Shell extension; an absent service is never a trigger."""
    try:
        result = subprocess.run(
            ["gdbus", "call", "--session", "--dest", BUS_NAME,
             "--object-path", OBJECT_PATH, "--method", INTERFACE + ".GetFocusState"],
            capture_output=True, text=True, timeout=2, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return False, ""
    if result.returncode != 0:
        # Fallback to GetFullscreen if an older extension interface is active
        try:
            res = subprocess.run(
                ["gdbus", "call", "--session", "--dest", BUS_NAME,
                 "--object-path", OBJECT_PATH, "--method", INTERFACE + ".GetFullscreen"],
                capture_output=True, text=True, timeout=2, check=False)
            if res.returncode == 0:
                return bool(re.search(r"\btrue\b", res.stdout, re.IGNORECASE)), ""
        except (OSError, subprocess.TimeoutExpired):
            pass
        return False, ""
    stdout = result.stdout.strip()
    match = re.search(r"\(\s*(true|false)\s*,\s*['\"]([^'\"]*)['\"]\s*\)", stdout, re.IGNORECASE)
    if match:
        return match.group(1).lower() == "true", match.group(2)
    return bool(re.search(r"\btrue\b", stdout, re.IGNORECASE)), ""


def recorded_active(directory):
    return read_text(os.path.join(directory, "adaptive-performance", "active")) == "1"


def write_state(directory, active, reason):
    """Commit runtime state only after the corresponding installer transition."""
    state_dir = os.path.join(directory, "adaptive-performance")
    os.makedirs(state_dir, exist_ok=True)
    for name, value in (("active", "1" if active else "0"), ("reason", reason)):
        temporary = os.path.join(state_dir, ".%s.tmp" % name)
        with open(temporary, "w", encoding="utf-8") as stream:
            stream.write(value + "\n")
        os.replace(temporary, os.path.join(state_dir, name))


def write_reason(directory, reason):
    """Refresh the displayed trigger without claiming a new blur transition."""
    state_dir = os.path.join(directory, "adaptive-performance")
    os.makedirs(state_dir, exist_ok=True)
    temporary = os.path.join(state_dir, ".reason.tmp")
    with open(temporary, "w", encoding="utf-8") as stream:
        stream.write(reason + "\n")
    os.replace(temporary, os.path.join(state_dir, "reason"))


def styling_enabled(directory):
    return not os.path.exists(os.path.join(directory, "styling-off"))


def installer(directory, action):
    script = read_text(os.path.join(directory, "adaptive-install"))
    if not script:
        checkout = read_text(os.path.join(directory, "repo-path"))
        script = os.path.join(checkout, "install.sh") if checkout else ""
    if not script or not os.path.isfile(script):
        raise RuntimeError("no Aura Glass checkout is recorded for the adaptive transition")
    operation = os.environ.get(
        "AURA_GLASS_OPERATION",
        os.path.join(os.path.expanduser("~"), ".local", "bin", "aura-glass-operation"))
    cmd = [operation, "run", "--", script, "--settings-only", "--incremental",
           "--adaptive-blur", action, "--yes"]
    result = subprocess.run(cmd, text=True, timeout=90, check=False)
    if result.returncode:
        raise RuntimeError("adaptive %s transition did not complete (code %d)" % (action, result.returncode))


def restore_glass_from_solid(directory):
    """Reopen the themed mode when the panel profile is chosen from solid."""
    script = read_text(os.path.join(directory, "adaptive-install"))
    if not script:
        checkout = read_text(os.path.join(directory, "repo-path"))
        script = os.path.join(checkout, "install.sh") if checkout else ""
    if not script or not os.path.isfile(script):
        raise RuntimeError("no Aura Glass checkout is recorded for the glass restore")
    operation = os.environ.get(
        "AURA_GLASS_OPERATION",
        os.path.join(os.path.expanduser("~"), ".local", "bin", "aura-glass-operation"))
    result = subprocess.run(
        [operation, "run", "--", script, "--settings-only", "--glass-mode",
         "frosted", "--yes"], text=True, timeout=90, check=False)
    if result.returncode:
        raise RuntimeError("solid-mode glass restore did not complete")


class AdaptiveReducer:
    """Keep hysteresis and a short stable window out of the installer path."""

    def __init__(self, sustained=3):
        self.sustained = sustained
        self.gpu_active = False
        self.gpu_high_samples = 0
        self.pending = None
        self.samples = 0

    def desired(self, profile, fullscreen_now, focused_wm_class, battery_now, gpu_load, fullscreen_apps):
        if profile == "full":
            self.gpu_active = False
            self.gpu_high_samples = 0
            return False, "full-glass"
        if profile == "performance":
            self.gpu_active = False
            self.gpu_high_samples = 0
            return True, "performance"

        # GPU hysteresis with 3-sample sustained gate (at 2s intervals)
        if gpu_load is None:
            self.gpu_active = False
            self.gpu_high_samples = 0
        elif self.gpu_active:
            if gpu_load < GPU_CLEAR:
                self.gpu_active = False
                self.gpu_high_samples = 0
        else:
            if gpu_load >= GPU_ENTER:
                self.gpu_high_samples += 1
                if self.gpu_high_samples >= self.sustained:
                    self.gpu_active = True
            else:
                self.gpu_high_samples = 0

        game_active = bool(fullscreen_now and focused_wm_class and focused_wm_class in fullscreen_apps)
        battery_active = bool(battery_now)

        reasons = []
        if battery_active:
            reasons.append("battery")
        if self.gpu_active:
            reasons.append("gpu")
        if game_active:
            reasons.append("game")

        if reasons:
            return True, ", ".join(reasons)
        return False, "normal"

    def transition(self, current, desired, reason, force=False):
        if current == desired:
            self.pending = None
            self.samples = 0
            return None
        if force:
            self.pending = None
            self.samples = 0
            return desired, reason

        candidate = (desired, reason)
        if candidate != self.pending:
            self.pending = candidate
            self.samples = 1
        else:
            self.samples += 1

        # Battery and game triggers activate immediately; GPU load or clearing to normal debounces
        immediate = desired and any(trigger in reason for trigger in ("battery", "game"))
        if immediate or self.samples >= self.sustained:
            self.pending = None
            self.samples = 0
            return desired, reason
        return None


def sample(reducer, directory, force=False):
    # The profile menu stays available in solid mode, but when styling has stood down,
    # the worker does not make transient changes.
    if not styling_enabled(directory):
        return False
    profile = selected_profile(directory)
    fullscreen_now, focused_wm_class = focus_state()
    battery_now = on_battery()
    gpu_load = gpu_busy_percent()
    fullscreen_apps = read_fullscreen_apps(directory)

    desired, reason = reducer.desired(
        profile, fullscreen_now, focused_wm_class, battery_now, gpu_load, fullscreen_apps)
    current = recorded_active(directory)
    transition = reducer.transition(current, desired, reason, force)
    if transition is None:
        if current and desired:
            prior_reason = read_text(os.path.join(directory, "adaptive-performance", "reason"))
            if prior_reason != reason:
                write_reason(directory, reason)
        return False
    active, reason = transition
    installer(directory, "active" if active else "restore")
    write_state(directory, active, reason)
    return True


def interval_from_env():
    try:
        return max(1.0, float(os.environ.get("AURA_GLASS_ADAPTIVE_INTERVAL", "2")))
    except ValueError:
        return 2.0


def sustained_from_env():
    try:
        return max(1, int(os.environ.get("AURA_GLASS_ADAPTIVE_SUSTAINED", "3")))
    except ValueError:
        return 3


def usage():
    print("usage: aura-glass-adaptive profile auto|full|performance | refresh", file=sys.stderr)


def main(argv):
    directory = config_dir()
    reducer = AdaptiveReducer(sustained_from_env())
    if not argv:
        while True:
            sample(reducer, directory)
            time.sleep(interval_from_env())
    if len(argv) == 2 and argv[0] == "profile" and argv[1] in PROFILES:
        set_profile(directory, argv[1])
        if os.path.exists(os.path.join(directory, "styling-off")):
            restore_glass_from_solid(directory)
        sample(reducer, directory, force=True)
        return 0
    if argv == ["refresh"]:
        sample(reducer, directory, force=True)
        return 0
    usage()
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except Exception as error:
        print("aura-glass-adaptive:", error, file=sys.stderr)
        raise SystemExit(1)
