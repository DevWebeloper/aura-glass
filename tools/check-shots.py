#!/usr/bin/env python3
"""Compare a preview run against the last accepted one.

    tools/check-shots.py --mode glass          compare, and say what moved
    tools/check-shots.py --mode glass --accept adopt this run as the baseline
    tools/check-shots.py --mode solid --list   what is in the baseline

Glass and solid mode were compared by eye, and that is a real gap rather than a
pedantic one: the two modes are meant to look different, so a regression in one
of them looks exactly like the difference between them. Nothing catches a sheet
that stopped applying in solid mode as long as glass still looks right.

This turns "looks the same to me" into a number, the same shift in kind that
tools/check-tokens.sh made for the values.

The baseline lives in ~/.cache, not in the repository. Each shot is a 1080p PNG
and there are ten of them per mode, so tracking baselines would put ~25MB of
binaries into a repository whose entire history is currently a couple of
thousand objects — and they would have to be regenerated on every deliberate
visual change, which is most commits here. A local baseline catches what it is
actually useful for: "I changed one sheet, what else moved?"

Needs Pillow. Without it this says so and exits 0 rather than failing a preview
over a missing optional dependency — an exact byte comparison is no use, since
two renders of the same tree differ in the clock and in dithering.
"""
import argparse
import os
import shutil
import sys

# A pixel counts as changed only past this, so font dithering and the odd
# rounding difference between two renders do not read as a regression.
CHANNEL_TOLERANCE = 8
# And a shot counts as changed only past this share of its pixels. The clock in
# the top bar moves on its own between runs and is worth a few hundredths of a
# percent by itself.
DEFAULT_THRESHOLD = 0.40


def baseline_dir(mode):
    root = os.environ.get("TAHOE_SHOT_BASELINE") or os.path.join(
        os.path.expanduser("~"), ".cache", "tahoe-glass", "baseline")
    return os.path.join(root, mode)


def shots_in(path):
    if not os.path.isdir(path):
        return {}
    return {f: os.path.join(path, f)
            for f in sorted(os.listdir(path)) if f.endswith(".png")}


def compare(a_path, b_path):
    """Return (percent_changed, note). percent is None when incomparable."""
    from PIL import Image, ImageChops

    with Image.open(a_path) as a_img, Image.open(b_path) as b_img:
        a = a_img.convert("RGB")
        b = b_img.convert("RGB")
        if a.size != b.size:
            return None, "size changed: %dx%d -> %dx%d" % (
                b.size[0], b.size[1], a.size[0], a.size[1])
        r, g, bl = ImageChops.difference(a, b).split()
        # The worst channel per pixel, rather than the sum of the three. A
        # summed difference lets a shift too small to see in each of red, green
        # and blue add up to something this would call a change.
        mono = ImageChops.lighter(ImageChops.lighter(r, g), bl)
        changed = sum(count for value, count in enumerate(mono.histogram())
                      if value > CHANNEL_TOLERANCE)
        total = a.size[0] * a.size[1]
        return 100.0 * changed / total, None


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--mode", default="glass",
                    help="which baseline to use (glass, solid, ...)")
    ap.add_argument("--shots", default=None,
                    help="directory of the run to check")
    ap.add_argument("--accept", action="store_true",
                    help="adopt this run as the new baseline")
    ap.add_argument("--list", action="store_true",
                    help="list what the baseline holds")
    ap.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD,
                    help="percent of pixels that may differ (default %.2f)"
                         % DEFAULT_THRESHOLD)
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    shots = args.shots or os.path.join(root, "screenshots", "preview")
    base = baseline_dir(args.mode)

    if args.list:
        have = shots_in(base)
        if not have:
            print("no baseline for '%s' yet — %s" % (args.mode, base))
            return 0
        print("baseline for '%s' (%s):" % (args.mode, base))
        for name in have:
            print("   %s" % name)
        return 0

    current = shots_in(shots)
    if not current:
        print("   no screenshots in %s — nothing to check" % shots)
        return 0

    if args.accept:
        os.makedirs(base, exist_ok=True)
        for name, path in current.items():
            shutil.copy2(path, os.path.join(base, name))
        print("   baseline for '%s' updated — %d shot%s"
              % (args.mode, len(current), "" if len(current) == 1 else "s"))
        return 0

    have = shots_in(base)
    if not have:
        print("   no baseline for '%s' yet. To adopt this run as one:" % args.mode)
        print("      tools/check-shots.py --mode %s --accept" % args.mode)
        return 0

    try:
        import PIL  # noqa: F401
    except ImportError:
        print("   Pillow is not installed, so this run was not compared.")
        print("   pacman -S python-pillow   (or pip install --user pillow)")
        return 0

    moved, gone, added, failed = [], [], [], []

    for name in sorted(set(current) | set(have)):
        if name not in have:
            added.append(name)
            continue
        if name not in current:
            gone.append(name)
            continue
        pct, note = compare(current[name], have[name])
        if pct is None:
            failed.append((name, note))
        elif pct > args.threshold:
            moved.append((name, pct))

    print("   compared %d shot%s against the '%s' baseline"
          % (len(set(current) & set(have)),
             "" if len(set(current) & set(have)) == 1 else "s", args.mode))

    for name in added:
        print("      new     %s  (not in the baseline)" % name)
    for name in gone:
        print("      MISSING %s  (in the baseline, not in this run)" % name)
    for name, note in failed:
        print("      CHANGED %s  %s" % (name, note))
    for name, pct in moved:
        print("      CHANGED %s  %.2f%% of pixels" % (name, pct))

    if moved or failed or gone:
        print()
        print("   If that is the change you meant to make, adopt it:")
        print("      tools/check-shots.py --mode %s --accept" % args.mode)
        return 1

    print("   nothing moved beyond %.2f%%" % args.threshold)
    return 0


if __name__ == "__main__":
    sys.exit(main())
