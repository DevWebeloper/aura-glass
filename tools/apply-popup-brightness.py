#!/usr/bin/env python3
"""Set how bright the popup blur comes out.

    apply-popup-brightness.py PERCENT

Blur My Shell v76 keeps a blur's brightness only as a `brightness` param inside
the `pipelines` blob (the per-component key is read once, by its settings
migration). Writing it needs more than a dconf write, because the blob holds
every pipeline at once and only one of them is the popups'.

Which one that is comes from the popup component's own `pipeline` key rather
than from a hard-coded id, so repointing the component in dconf/core.ini moves
this with it instead of quietly turning it into a no-op.

Text rewriting rather than GVariant parsing, for the same reason
apply_blur_strength does it that way: the blob round-trips through `dconf
read`/`dconf write` as the text dconf itself prints, and a regex over one
pipeline's slice of it cannot invent keys that were not already there.
"""
import re
import subprocess
import sys

BASE = "/org/gnome/shell/extensions/blur-my-shell"


def read(key):
    return subprocess.run(["dconf", "read", BASE + key],
                          capture_output=True, text=True).stdout.strip()


def main():
    if len(sys.argv) != 2 or not sys.argv[1].strip().isdigit():
        print("usage: apply-popup-brightness.py PERCENT", file=sys.stderr)
        return 2
    want = int(sys.argv[1]) / 100.0

    name, blob = read("/popup/pipeline"), read("/pipelines")
    if not name or not blob or name not in blob:
        # No pipelines blob, or the component points at one that is not in it:
        # there is no popup brightness to set.
        return 0

    # The named pipeline's own slice of the blob, so what is rewritten below is
    # that pipeline's brightness and not the panel's or the windows'.
    start = blob.index(name)
    nxt = blob.find("'pipeline_", start + len(name))
    end = nxt if nxt != -1 else len(blob)

    sliced = re.sub(r"('brightness': <)([0-9.]+)(>)",
                    lambda m: "%s%s%s" % (m.group(1), repr(want), m.group(3)),
                    blob[start:end])
    new = blob[:start] + sliced + blob[end:]
    if new != blob:
        subprocess.run(["dconf", "write", BASE + "/pipelines", new], check=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
