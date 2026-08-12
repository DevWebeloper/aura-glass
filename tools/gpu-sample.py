#!/usr/bin/env python3
"""Sample GPU busy percentage, on whatever GPU this machine actually has.

Blur is the expensive part of this desktop and the cost is not the same on
every card, so the numbers in the README have to be reproducible by someone
else. There is no portable interface for this — each driver exposes it
differently, and two of them do not expose it at all:

    amdgpu      /sys/class/drm/cardN/device/gpu_busy_percent
    xe          /sys/class/drm/cardN/device/tile0/gt0/gt_busy_percent (varies)
    i915        nothing in sysfs. Intel's busy figure comes from perf counters,
                which is what intel_gpu_top reads; without igt-gpu-tools there
                is no number to read.
    nvidia      nvidia-smi --query-gpu=utilization.gpu
    nouveau     nothing.

Where there is no source this says so and exits non-zero, rather than printing
a zero that reads like an idle GPU.

    tools/gpu-sample.py --probe          say what this machine can measure
    tools/gpu-sample.py --seconds 10     sample, then print a summary
"""
import glob
import os
import shutil
import subprocess
import sys
import time


def _read(path):
    try:
        with open(path) as fh:
            return fh.read().strip()
    except OSError:
        return None


def find_source():
    """Return (name, callable->int|None, note)."""
    for card in sorted(glob.glob("/sys/class/drm/card[0-9]*")):
        if "-" in os.path.basename(card):
            continue  # a connector, not the card
        driver = None
        link = os.path.join(card, "device", "driver")
        if os.path.islink(link):
            driver = os.path.basename(os.path.realpath(link))

        amd = os.path.join(card, "device", "gpu_busy_percent")
        if os.path.exists(amd):
            return ("%s (%s)" % (os.path.basename(card), driver or "?"),
                    lambda p=amd: _to_int(_read(p)), None)

        for pattern in ("device/tile*/gt*/gt_busy_percent", "gt_busy_percent"):
            hits = glob.glob(os.path.join(card, pattern))
            if hits:
                return ("%s (%s)" % (os.path.basename(card), driver or "?"),
                        lambda p=hits[0]: _to_int(_read(p)), None)

        if driver == "i915":
            return (None, None,
                    "i915 exposes no busy percentage in sysfs. Install "
                    "igt-gpu-tools and read it with `intel_gpu_top -J`, or "
                    "compare frame timings instead.")
        if driver == "nouveau":
            return (None, None,
                    "nouveau exposes no busy percentage. The proprietary "
                    "driver does, through nvidia-smi.")

    if shutil.which("nvidia-smi"):
        return ("nvidia-smi", _nvidia_sample, None)

    return (None, None, "no GPU busy counter found on this machine")


def _to_int(text):
    try:
        return int(text)
    except (TypeError, ValueError):
        return None


def _nvidia_sample():
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5)
        return _to_int(out.stdout.strip().splitlines()[0])
    except (OSError, subprocess.SubprocessError, IndexError):
        return None


def main():
    args = sys.argv[1:]
    name, sample, note = find_source()

    if "--probe" in args:
        if sample:
            print("gpu source: %s" % name)
            return 0
        print("gpu source: none — %s" % note)
        return 1

    if not sample:
        print("   GPU sampling unavailable: %s" % note)
        return 1

    seconds = 10.0
    if "--seconds" in args:
        seconds = float(args[args.index("--seconds") + 1])
    label = args[args.index("--label") + 1] if "--label" in args else ""

    values = []
    deadline = time.time() + seconds
    while time.time() < deadline:
        v = sample()
        if v is not None:
            values.append(v)
        time.sleep(0.1)

    if not values:
        print("   %s produced no readings" % name)
        return 1

    values.sort()
    n = len(values)
    print("   %-16s samples %3d   median %3d%%   p90 %3d%%   max %3d%%   (%s)"
          % (label or "gpu", n, values[n // 2],
             values[min(n - 1, int(n * 0.9))], values[-1], name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
