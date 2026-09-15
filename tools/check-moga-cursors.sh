#!/usr/bin/env bash
# Fixture checks for official Moga variant selection and the installer boundary.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=()
fail() { failures+=("$*"); }

metadata="$TMP/loadFiles.json"
python3 - "$metadata" <<'PY'
import json
import sys

records = {
    "Blue": ("Moga-Neon-Blue.zip", "d193a5cf9a38478165c4a9f41fdacd18"),
    "Cyan": ("Moga-Neon-Cyan.zip", "e0a1ff78c6b6b9f7248873b70002a2ba"),
    "Green": ("Moga-Neon-Green.zip", "25e9a0f4df1f2bd4b749d687c2810c63"),
    "Yellow": ("Moga-Neon-Yellow.zip", "acef804aa6e3e61e04bd931030753c2b"),
    "Orange": ("Moga-Neon-Orange.zip", "0ccc899ec383367afee017d30b67e203"),
    "Red": ("Moga-Neon-Red.zip", "b3745d8268a8e790bba2996438dd4f53"),
    "Rose": ("Moga-Neon-Rose.zip", "834fe75fa3c513cc418aad96cd4fafb8"),
    "Purple": ("Moga-Neon-Purple.zip", "6ec7f0cc041c2aca32561493dd002763"),
    "Sky": ("Moga-Neon-Sky.zip", "41d45aed9191f4f252fdc8c71878c3a0"),
}
json.dump({
    "files": [
        {"active": "1", "name": name, "md5sum": md5,
         "url": "https%3A%2F%2Ffiles.example%2F" + name}
        for name, md5 in records.values()
    ]
}, open(sys.argv[1], "w"))
PY

declare -A expected=(
  [blue]='Blue|Moga-Neon-Blue.zip|d193a5cf9a38478165c4a9f41fdacd18'
  [teal]='Cyan|Moga-Neon-Cyan.zip|e0a1ff78c6b6b9f7248873b70002a2ba'
  [green]='Green|Moga-Neon-Green.zip|25e9a0f4df1f2bd4b749d687c2810c63'
  [yellow]='Yellow|Moga-Neon-Yellow.zip|acef804aa6e3e61e04bd931030753c2b'
  [orange]='Orange|Moga-Neon-Orange.zip|0ccc899ec383367afee017d30b67e203'
  [red]='Red|Moga-Neon-Red.zip|b3745d8268a8e790bba2996438dd4f53'
  [pink]='Rose|Moga-Neon-Rose.zip|834fe75fa3c513cc418aad96cd4fafb8'
  [purple]='Purple|Moga-Neon-Purple.zip|6ec7f0cc041c2aca32561493dd002763'
  [slate]='Sky|Moga-Neon-Sky.zip|41d45aed9191f4f252fdc8c71878c3a0'
)

expect_variant() {
    local accent="$1" want="$2" got
    if ! got="$(python3 "$ROOT/tools/moga_cursor.py" variant "$accent" 2>/dev/null)"; then
        fail "$accent variant command failed"
    elif [ "$got" != "$want" ]; then
        fail "$accent mapped to '$got', want '$want'"
    fi
}

for accent in "${!expected[@]}"; do
    IFS='|' read -r variant archive md5 <<<"${expected[$accent]}"
    expect_variant "$accent" "$variant"
    if ! line="$(python3 "$ROOT/tools/moga_cursor.py" resolve "$accent" "$metadata" 2>/dev/null)"; then
        fail "$accent resolve command failed"
    else
        IFS=$'\t' read -r got_variant got_archive got_md5 got_url <<<"$line"
        [ "$got_variant" = "$variant" ] || fail "$accent resolve variant '$got_variant'"
        [ "$got_archive" = "$archive" ] || fail "$accent resolve archive '$got_archive'"
        [ "$got_md5" = "$md5" ] || fail "$accent resolve md5 '$got_md5'"
        [ "$got_url" = "https://files.example/$archive" ] || fail "$accent URL was not decoded"
    fi
done

python3 - "$metadata" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1]))
for item in data["files"]:
    if item["name"] == "Moga-Neon-Purple.zip":
        item["active"] = "0"
        break
json.dump(data, open(sys.argv[1], "w"))
PY
python3 "$ROOT/tools/moga_cursor.py" resolve purple "$metadata" >/dev/null 2>&1 \
    && fail "inactive Purple release was accepted"

python3 - "$metadata" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1]))
for item in data["files"]:
    if item["name"] == "Moga-Neon-Purple.zip":
        item["active"] = "1"
        item["md5sum"] = "wrong"
        break
json.dump(data, open(sys.argv[1], "w"))
PY
python3 "$ROOT/tools/moga_cursor.py" resolve purple "$metadata" >/dev/null 2>&1 \
    && fail "checksum-mismatched Purple release was accepted"

if bash "$ROOT/install.sh" --settings-only --dry-run --cursors moga --accent teal -y \
       >/dev/null 2>&1; then
    fail "installer accepted --cursors moga before integration"
fi

if [ "${#failures[@]}" -gt 0 ]; then
    printf 'Moga cursor checks FAILED\n' >&2
    printf '  %s\n' "${failures[@]}" >&2
    exit 1
fi
printf 'Moga cursor checks passed\n'
