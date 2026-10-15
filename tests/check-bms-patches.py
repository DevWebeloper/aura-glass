#!/usr/bin/env python3
"""Exercise Aura's actual patched BMS sources. Pass an existing upstream clone.

No network, desktop, or installed extension access. Requires git and node.
"""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('upstream_clone', type=Path)
source = parser.parse_args().upstream_clone.resolve()
revision = re.search(r'^BMS_REF="([^"]+)"', (ROOT / 'lib/steps.sh').read_text(), re.M).group(1)
with tempfile.TemporaryDirectory(prefix="aura-bms-test-") as directory:
    target = Path(directory)
    archive = subprocess.run(["git", "-C", str(source), "archive", revision],
                             check=True, capture_output=True).stdout
    subprocess.run(["tar", "-x", "-C", directory], input=archive, check=True)
    for name in ("overview", "subwindows", "notifications"):
        subprocess.run(["git", "apply",
                        str(ROOT / "patches" / f"blur-my-shell-{name}.patch")],
                       cwd=target, check=True)
    subprocess.run(["node", str(ROOT / "tests" / "bms-patches.cjs"), directory], check=True)

    subprocess.run(["node", str(ROOT / "tests" / "application-lifecycle.cjs"), directory], check=True)
