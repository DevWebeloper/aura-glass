#!/usr/bin/env bash
# Regression fixture for the overview blur lifecycle.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/extensions/blur-my-shell@aunetx"
cat > "$TMP/bin/gnome-extensions" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    info) printf 'State: ACTIVE\n' ;;
    disable|enable) printf '%s %s\n' "$1" "$2" >> "$AURA_TEST_LOG" ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$TMP/bin/gnome-extensions"

cat > "$TMP/harness.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$1"
export PATH="$2:$PATH"
export AURA_TEST_LOG="$3"
EXT_DIR="$4"
BMS_UUID=blur-my-shell@aunetx
WANT_BLUR=1
DRY_RUN=0

run() { "$@"; }
info() { :; }
ok() { :; }
warn() { :; }

. "$ROOT/lib/steps-extensions.sh"
refresh_bms_after_dconf
EOF
chmod +x "$TMP/harness.sh"

if "$TMP/harness.sh" "$ROOT" "$TMP/bin" "$TMP/commands.log" "$TMP/extensions"; then
    grep -qx 'disable blur-my-shell@aunetx' "$TMP/commands.log"
    grep -qx 'enable blur-my-shell@aunetx' "$TMP/commands.log"
else
    printf '%s\n' 'check-overview-blur: refresh hook missing or failed' >&2
    exit 1
fi

printf '%s\n' 'check-overview-blur: OK'
