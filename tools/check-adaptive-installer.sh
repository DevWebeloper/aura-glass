#!/usr/bin/env bash
# Assert install.sh --adaptive-blur active switches off blur surfaces without
# touching normal memos, and restore recovers the exact normal blur state.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=()

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

export HOME="$scratch"
conf="$scratch/.config/aura-glass"
mkdir -p "$conf/modes/frosted" "$scratch/.config/gtk-4.0" "$scratch/.config/gtk-3.0" \
         "$scratch/.themes/Aura-Glass/gnome-shell" "$scratch/.local/bin"

# Stubs for desktop tools
mkdir -p "$scratch/fakebin"
FAKE_DCONF_LOG="$scratch/fake-dconf.log"
: > "$FAKE_DCONF_LOG"

cat > "$scratch/fakebin/dconf" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    read)
        # Default responses for queries
        echo ""
        ;;
    write)
        echo "write:$2:$3" >> "$FAKE_DCONF_LOG"
        ;;
    *)
        exit 0
        ;;
esac
STUB
chmod +x "$scratch/fakebin/dconf"

cat > "$scratch/fakebin/gsettings" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$scratch/fakebin/gsettings"

cat > "$scratch/fakebin/gnome-extensions" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$scratch/fakebin/gnome-extensions"

export PATH="$scratch/fakebin:$PATH" FAKE_DCONF_LOG

# Populate baseline normal configuration and memos
printf 'frosted\n' > "$conf/glass-mode"
printf '1\n' > "$conf/modes/frosted/blur"
printf 'yes\n' > "$conf/bms-window-blur"
printf 'yes\n' > "$conf/bms-popup-blur"
printf 'yes\n' > "$conf/bms-notification-blur"
printf '25\n' > "$conf/transparency"
printf 'teal\n' > "$conf/accent"

# Shipped baseline CSS files
printf '/* popup blur */\n' > "$conf/shell-popup-blur.css"
printf '/* notification blur */\n' > "$conf/shell-notification-blur.css"
printf '/* transparency */\n' > "$conf/gtk4-transparency.css"

# Snapshot initial memos
memos_snapshot() {
    (cd "$conf" && sha256sum glass-mode modes/frosted/blur bms-window-blur bms-popup-blur bms-notification-blur transparency accent 2>/dev/null | sort)
}
before_memos="$(memos_snapshot)"

# --- 1. Transition to active (no-blur) ---
: > "$FAKE_DCONF_LOG"
out="$(bash "$ROOT/install.sh" --settings-only --incremental --adaptive-blur active -y 2>&1)" || failures+=(
    "install.sh --adaptive-blur active failed: $out")

# Check dconf writes
grep -q "write:/org/gnome/shell/extensions/blur-my-shell/applications/blur:false" "$FAKE_DCONF_LOG" \
    || failures+=("active: applications/blur was not set to false")
grep -q "write:/org/gnome/shell/extensions/blur-my-shell/applications/opacity:255" "$FAKE_DCONF_LOG" \
    || failures+=("active: applications/opacity was not set to 255")
grep -q "write:/org/gnome/shell/extensions/blur-my-shell/popup/blur:false" "$FAKE_DCONF_LOG" \
    || failures+=("active: popup/blur was not set to false")
grep -q "write:/org/gnome/shell/extensions/blur-my-shell/popup/notification:false" "$FAKE_DCONF_LOG" \
    || failures+=("active: popup/notification was not set to false")

# Check file states
[ -f "$conf/shell-80-solid.css" ] \
    || failures+=("active: shell-80-solid.css was not installed")
[ ! -f "$conf/shell-popup-blur.css" ] \
    || failures+=("active: shell-popup-blur.css was not removed")
[ ! -f "$conf/shell-notification-blur.css" ] \
    || failures+=("active: shell-notification-blur.css was not removed")
[ ! -f "$conf/gtk4-transparency.css" ] \
    || failures+=("active: gtk4-transparency.css was not removed")

# Check memos are unchanged
after_active_memos="$(memos_snapshot)"
[ "$before_memos" = "$after_active_memos" ] \
    || failures+=("active: configuration memos were modified during transient transition")

# --- 2. Transition back to restore ---
: > "$FAKE_DCONF_LOG"
out="$(bash "$ROOT/install.sh" --settings-only --incremental --adaptive-blur restore -y 2>&1)" || failures+=(
    "install.sh --adaptive-blur restore failed: $out")

# Check dconf writes
grep -q "write:/org/gnome/shell/extensions/blur-my-shell/applications/blur:true" "$FAKE_DCONF_LOG" \
    || failures+=("restore: applications/blur was not restored to true")
grep -q "write:/org/gnome/shell/extensions/blur-my-shell/popup/blur:true" "$FAKE_DCONF_LOG" \
    || failures+=("restore: popup/blur was not restored to true")
grep -q "write:/org/gnome/shell/extensions/blur-my-shell/popup/notification:true" "$FAKE_DCONF_LOG" \
    || failures+=("restore: popup/notification was not restored to true")

# Check file states
[ ! -f "$conf/shell-80-solid.css" ] \
    || failures+=("restore: shell-80-solid.css was not removed")
[ -f "$conf/shell-popup-blur.css" ] \
    || failures+=("restore: shell-popup-blur.css was not restored")
[ -f "$conf/shell-notification-blur.css" ] \
    || failures+=("restore: shell-notification-blur.css was not restored")
[ -f "$conf/gtk4-transparency.css" ] \
    || failures+=("restore: gtk4-transparency.css was not restored")

# Check memos are unchanged
after_restore_memos="$(memos_snapshot)"
[ "$before_memos" = "$after_restore_memos" ] \
    || failures+=("restore: configuration memos were modified during restore transition")

# --- 3. Baseline already no-blur skips redundant writes ---
printf '0\n' > "$conf/modes/frosted/blur"
: > "$FAKE_DCONF_LOG"
out="$(bash "$ROOT/install.sh" --settings-only --incremental --adaptive-blur active -y 2>&1)" || failures+=(
    "baseline no-blur test failed: $out")
case "$out" in
    *"baseline is already no-blur"*) ;;
    *) failures+=("baseline no-blur should report skip message, got: $out") ;;
esac
[ ! -s "$FAKE_DCONF_LOG" ] \
    || failures+=("baseline no-blur should perform no dconf writes, wrote: $(cat "$FAKE_DCONF_LOG")")

if [ "${#failures[@]}" -gt 0 ]; then
    printf 'adaptive-installer check FAILED\n\n'
    printf '  %s\n' "${failures[@]}"
    exit 1
fi

printf 'adaptive-installer check passed — active no-blur, restore normal, memo immutability, and baseline skip verified\n'
