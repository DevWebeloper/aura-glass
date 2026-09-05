#!/usr/bin/env python3
"""Exercise the incremental selector through the real installer parser."""
import json
import os
import subprocess
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def plan(home, *args):
    result = subprocess.run([os.path.join(ROOT, "install.sh"), "--settings-only",
                             "--incremental", "--dry-run", "--plan-json", *args],
                            env=os.environ | {"HOME": home}, text=True,
                            capture_output=True, timeout=15)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def main():
    with tempfile.TemporaryDirectory() as temp:
        os.makedirs(os.path.join(temp, ".config", "aura-glass"))
        os.makedirs(os.path.join(temp, ".themes", "Aura-Glass"))
        fallback = plan(temp, "--accent", "teal")
        assert fallback["actions"] == ["full"]
        fingerprint = subprocess.run(
            ["bash", "-c", "REPO_ROOT=$PWD; . lib/steps-apply-plan.sh; apply_source_fingerprint"],
            cwd=ROOT, text=True, capture_output=True, check=True).stdout
        with open(os.path.join(temp, ".config", "aura-glass", "apply-source-fingerprint"), "w", encoding="utf-8") as stream:
            stream.write(fingerprint)
        assert plan(temp, "--accent", "teal")["actions"] == ["accent"]
        assert plan(temp, "--cursor-size", "32")["actions"] == ["cursor-size"]
        assert plan(temp, "--app-tint-color", "#101820")["actions"] == ["css"]
        assert plan(temp, "--radius-preset", "soft")["actions"] == ["full"]
    print("check-incremental-apply: OK")


if __name__ == "__main__":
    main()
