#!/usr/bin/env python3
"""Keep GUI recovery feedback on the backend protocol, not parsed log text."""
import os
import subprocess
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    preview = os.path.join(ROOT, "bin", "aura-glass-preview")
    with tempfile.TemporaryDirectory() as temp:
        config = os.path.join(temp, ".config", "aura-glass")
        os.makedirs(config)
        with open(os.path.join(config, "repo-path"), "w", encoding="utf-8") as stream:
            stream.write(ROOT + "\n")
        env = os.environ | {"HOME": temp}
        result = subprocess.run([preview, "status", "--json"], env=env,
                                text=True, capture_output=True, timeout=10)
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == ('{"schema_version":1,"state":"idle",'
                                         '"session_id":null,"revision":0,'
                                         '"recovery_available":false,"conflicts":[]}')
    source = open(os.path.join(ROOT, "gui", "aura_glass_settings.py"), encoding="utf-8").read()
    assert '"--force-reload"' in source
    assert "Preview queued" not in source or "_preview_queue" in source
    assert "_preview_generation != generation" in source
    print("check-apply-feedback: OK")


if __name__ == "__main__":
    main()
