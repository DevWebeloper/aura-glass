#!/usr/bin/env python3
"""Check that installed helper artifacts are not recopied when unchanged."""
import os
import subprocess
import tempfile


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    with tempfile.TemporaryDirectory() as temp:
        source = os.path.join(temp, "source")
        destination = os.path.join(temp, "nested", "destination")
        with open(source, "w", encoding="utf-8") as stream:
            stream.write("one\n")
        os.chmod(source, 0o755)
        script = f'''set -euo pipefail
DRY_RUN=0
BACKUP_DIR="{temp}/backups"
source "{ROOT}/lib/common.sh"
install_if_changed "{source}" "{destination}" 755
test "$INSTALL_CHANGED" = 1
first=$(stat -c %Y:%a "{destination}")
install_if_changed "{source}" "{destination}" 755
test "$INSTALL_CHANGED" = 0
second=$(stat -c %Y:%a "{destination}")
test "$first" = "$second"
chmod 644 "{destination}"
install_if_changed "{source}" "{destination}" 755
test "$INSTALL_CHANGED" = 1
test "$(stat -c %a "{destination}")" = 755
printf 'two\\n' > "{source}"
install_if_changed "{source}" "{destination}" 755
test "$INSTALL_CHANGED" = 1
cmp "{source}" "{destination}"
'''
        result = subprocess.run(["bash", "-c", script], text=True,
                                capture_output=True, timeout=15)
        assert result.returncode == 0, result.stderr
    print("check-integration-reconcile: OK")


if __name__ == "__main__":
    main()
