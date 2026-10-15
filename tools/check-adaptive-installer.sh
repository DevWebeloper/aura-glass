#!/usr/bin/env bash
# Assert that install.sh --adaptive-blur is the app's Glass mode switch, minus
# the memos: "active" leaves the same files and keys behind as a switch to
# Performance, "restore" puts back exactly what Frosted left, and neither
# touches a memo or a drawer.
#
# Two fixture HOMEs start from the same real Frosted install. One takes the
# transient overlay, the other the ordinary mode switch, and what each leaves
# in dconf and in the generated sheets is compared. That is the KI-25 shape:
# the tray profile used to be a hand-kept subset of the switch and differed in
# the shell sheet, the app sheet, hacks-level and the OSD alpha, none of which
# a check against a fabricated memo could see.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=()

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
export XDG_CURRENT_DESKTOP=GNOME

# A throwaway HOME with persistent stubs for the desktop tools, so a run's
# dconf and gsettings writes can be read back and compared. Nothing reaches
# the real session: systemctl, gdbus and friends are recorded and ignored.
build_fixture() {   # build_fixture NAME
    local h="$scratch/$1" f
    mkdir -p "$h/.config/aura-glass" "$h/.themes/Aura-Glass/gnome-shell" \
             "$h/.config/gtk-4.0" "$h/.config/gtk-3.0" "$h/.local/bin" "$h/fakebin" \
             "$h/.local/share/gnome-shell/extensions/blur-my-shell@aunetx"
    for f in "$h/.themes/Aura-Glass/gnome-shell/gnome-shell.css" \
             "$h/.config/gtk-4.0/gtk.css" "$h/.config/gtk-4.0/gtk-dark.css" \
             "$h/.config/gtk-3.0/gtk.css"; do
        printf '/* base */\n' > "$f"
    done

    cat > "$h/fakebin/dconf" <<'STUB'
#!/usr/bin/env bash
DB="$HOME/dconf.db"; touch "$DB"
case "$1" in
    read)  grep -m1 -F "$2"$'\t' "$DB" | cut -f2- ;;
    write) grep -vF "$2"$'\t' "$DB" > "$DB.t"; printf '%s\t%s\n' "$2" "$3" >> "$DB.t"
           mv "$DB.t" "$DB" ;;
    load)  python3 -c '
import sys
base, db = sys.argv[1].strip("/"), sys.argv[2]
rows = {}
for line in open(db):
    k, _, v = line.rstrip("\n").partition("\t"); rows[k] = v
sec = ""
for line in sys.stdin:
    line = line.strip()
    if not line or line[0] in "#;": continue
    if line[0] == "[": sec = line[1:-1]; continue
    k, _, v = line.partition("=")
    rows["/%s/%s/%s" % (base, sec, k)] = v
open(db, "w").write("".join("%s\t%s\n" % kv for kv in rows.items()))
' "$2" "$DB" ;;
    *) exit 0 ;;
esac
STUB
    cat > "$h/fakebin/gsettings" <<'STUB'
#!/usr/bin/env bash
DB="$HOME/gsettings.db"; touch "$DB"
case "$1" in
    get) r="$(grep -m1 -F "$2 $3"$'\t' "$DB" | cut -f2-)"; echo "${r:-''}" ;;
    set) grep -vF "$2 $3"$'\t' "$DB" > "$DB.t"; printf '%s\t%s\n' "$2 $3" "$4" >> "$DB.t"
         mv "$DB.t" "$DB" ;;
    *) exit 0 ;;
esac
STUB
    cat > "$h/fakebin/gnome-extensions" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    list) echo blur-my-shell@aunetx ;;
    enable|disable) echo "$*" >> "$HOME/ext.log" ;;
esac
exit 0
STUB
    printf '#!/bin/sh\necho "GNOME Shell 50.1"\n' > "$h/fakebin/gnome-shell"
    for f in systemctl gdbus busctl notify-send loginctl; do
        printf '#!/bin/sh\nexit 0\n' > "$h/fakebin/$f"
    done
    chmod +x "$h/fakebin/"*
}

in_fixture() {   # in_fixture NAME ARGS... — install.sh under that HOME
    local h="$scratch/$1"; shift
    env -u DBUS_SESSION_BUS_ADDRESS HOME="$h" XDG_CONFIG_HOME="$h/.config" \
        XDG_DATA_HOME="$h/.local/share" XDG_RUNTIME_DIR="$h/run" \
        PATH="$h/fakebin:$PATH" bash "$ROOT/install.sh" "$@" 2>&1
}

# What a run leaves: the generated and installed sheets, every dconf and
# gsettings row, and the memos the transient path must not move. Files are
# listed by name and hash so a differing sheet names itself.
state() {   # state NAME
    local h="$scratch/$1"
    (
        cd "$h" || exit 1
        for f in .themes/Aura-Glass/gnome-shell/gnome-shell.css \
                 .config/gtk-4.0/gtk.css .config/gtk-4.0/gtk-dark.css \
                 .config/gtk-3.0/gtk.css \
                 .config/aura-glass/shell-*.css .config/aura-glass/gtk4-*.css; do
            [ -f "$f" ] && printf 'file %s %s\n' "$f" "$(sha256sum < "$f" | cut -d' ' -f1)"
        done
        sort dconf.db 2>/dev/null | sed 's/^/dconf /'
        sort gsettings.db 2>/dev/null | sed 's/^/gsettings /'
    )
}
memos() {       # memos NAME — the persistent answers
    (cd "$scratch/$1/.config/aura-glass" && \
        sha256sum glass-mode app-transparency app-opacity app-tint-color shell-tint-color \
                  blur-strength popup-blur notification-blur app-blur-scope \
                  notification-opacity popup-brightness window-brightness 2>/dev/null
     find modes -type f -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum) | sort
}

for name in tray mode; do
    build_fixture "$name"
    out="$(in_fixture "$name" --settings-only -y --glass-mode frosted)" \
        || failures+=("$name: the Frosted baseline install failed: $(printf '%s\n' "$out" | tail -n 5)")
done
frosted_state="$(state tray)"
frosted_memos="$(memos tray)"

# --- 1. active == a switch to Performance, without the memos ---------------
# The baseline install enables extensions; only the transitions are under test.
: > "$scratch/tray/ext.log"
out="$(in_fixture tray --settings-only --incremental --adaptive-blur active -y)" \
    || failures+=("--adaptive-blur active failed: $(printf '%s\n' "$out" | tail -n 5)")
out="$(in_fixture mode --settings-only -y --glass-mode performance)" \
    || failures+=("the Performance switch failed: $(printf '%s\n' "$out" | tail -n 5)")

diffs="$(diff <(state mode) <(state tray))" \
    || failures+=("active: the tray overlay and the Performance switch differ:
$(printf '%s\n' "$diffs" | head -n 12)")
[ "$frosted_memos" = "$(memos tray)" ] \
    || failures+=("active: a memo or a drawer changed during the transient transition")
[ ! -s "$scratch/tray/ext.log" ] \
    || failures+=("active: gnome-extensions was invoked (dynamic disable causes Mutter 51 crash)")
[ -f "$scratch/tray/.config/aura-glass/shell-80-solid.css" ] \
    || failures+=("active: shell-80-solid.css was not installed")
[ ! -f "$scratch/tray/.config/aura-glass/shell-popup-blur.css" ] \
    || failures+=("active: shell-popup-blur.css was not removed")
[ ! -f "$scratch/tray/.config/aura-glass/shell-notification-blur.css" ] \
    || failures+=("active: shell-notification-blur.css was not removed")
for key in panel overview appfolder lockscreen window-list screenshot popup applications; do
    [ "$(HOME="$scratch/tray" "$scratch/tray/fakebin/dconf" read \
         "/org/gnome/shell/extensions/blur-my-shell/$key/blur")" = false ] \
        || failures+=("active: blur-my-shell/$key/blur is not false")
done
[ "$(HOME="$scratch/tray" "$scratch/tray/fakebin/dconf" read \
     /org/gnome/shell/extensions/blur-my-shell/hacks-level)" = 0 ] \
    || failures+=("active: hacks-level was left at Frosted's value")

# --- 2. restore == the Frosted install it came from -------------------------
: > "$scratch/tray/ext.log"
out="$(in_fixture tray --settings-only --incremental --adaptive-blur restore -y)" \
    || failures+=("--adaptive-blur restore failed: $(printf '%s\n' "$out" | tail -n 5)")
diffs="$(diff <(printf '%s\n' "$frosted_state") <(state tray))" \
    || failures+=("restore: the desktop did not return to what Frosted left:
$(printf '%s\n' "$diffs" | head -n 12)")
[ "$frosted_memos" = "$(memos tray)" ] \
    || failures+=("restore: a memo or a drawer changed during the restore transition")
[ ! -s "$scratch/tray/ext.log" ] \
    || failures+=("restore: gnome-extensions was invoked (dynamic enable causes Mutter 51 crash)")
[ ! -e "$scratch/tray/.config/aura-glass/adaptive-performance/saved-mode-keys" ] \
    || failures+=("restore: the saved overlay keys were left behind")

# A per-component choice made inside Frosted survives the overlay.
h="$scratch/tray"
HOME="$h" "$h/fakebin/dconf" write /org/gnome/shell/extensions/blur-my-shell/lockscreen/blur false
in_fixture tray --settings-only --incremental --adaptive-blur active -y >/dev/null || true
in_fixture tray --settings-only --incremental --adaptive-blur restore -y >/dev/null || true
[ "$(HOME="$h" "$h/fakebin/dconf" read /org/gnome/shell/extensions/blur-my-shell/lockscreen/blur)" = false ] \
    || failures+=("restore: a per-component choice (no lock screen blur) was overwritten")
[ "$(HOME="$h" "$h/fakebin/dconf" read /org/gnome/shell/extensions/blur-my-shell/panel/blur)" = true ] \
    || failures+=("restore: panel/blur was not put back to true")

# --- 3. a Performance baseline has nothing to adapt --------------------------
# The guard reads the mode itself, the same glass-mode memo a real performance
# install leaves behind. The fixture that switched to Performance is that.
before="$(state mode)"
out="$(in_fixture mode --settings-only --incremental --adaptive-blur active -y)" \
    || failures+=("baseline no-blur test failed: $out")
case "$out" in
    *"baseline is already no-blur"*) ;;
    *) failures+=("baseline no-blur should report skip message, got: $out") ;;
esac
[ "$before" = "$(state mode)" ] \
    || failures+=("baseline no-blur should leave every file and key alone")

if [ "${#failures[@]}" -gt 0 ]; then
    printf 'adaptive-installer check FAILED\n\n'
    printf '  %s\n' "${failures[@]}"
    exit 1
fi

printf 'adaptive-installer check passed — active equals the Performance switch, restore equals Frosted, memos untouched, baseline skip verified\n'
