#!/usr/bin/env bash
# Measure GPU cost on the session you are actually using.
#
# The preview harness cannot see this class of cost: it renders headless to a
# virtual monitor, which never pays the repaint a real display does. Panel sigma
# was tuned against it for an afternoon and moved nothing, because there was
# nothing there to move. This samples the real session instead.
#
# Blur My Shell applies dconf changes live, so a setting can be changed and
# re-measured in seconds without logging out. That is what makes A/B possible.
#
#   tools/gpu-live.sh                  run every scenario once
#   tools/gpu-live.sh --label before   tag the run, to compare with --label after
#   tools/gpu-live.sh --quick          skip the scenarios that need your hands
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL=""
QUICK=0
while [ $# -gt 0 ]; do
    case "$1" in
        --label) LABEL="$2"; shift 2 ;;
        --quick) QUICK=1; shift ;;
        -h|--help) sed -n '2,16p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

python3 "$REPO_ROOT/tools/gpu-sample.py" --probe >/dev/null || {
    echo "no GPU counter on this machine — see tools/gpu-sample.py"; exit 1; }

CARD="$(ls /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1)"

say() { printf '\033[1;36m::\033[0m %s\n' "$*"; }

# sample SECONDS -> prints the samples, one per line, on fd 3
sample_into() {
    local secs="$1" out="$2"
    : > "$out"
    local end=$((SECONDS + secs))
    while [ $SECONDS -lt $end ]; do
        cat "$CARD" 2>/dev/null >> "$out"
        sleep 0.1
    done
}

report() {
    local name="$1" file="$2"
    python3 - "$name" "$file" "$LABEL" <<'PY' | tee -a "$LOG"
import sys
name, path, label = sys.argv[1], sys.argv[2], sys.argv[3]
v = sorted(int(x) for x in open(path) if x.strip().isdigit())
if not v:
    print("   %-22s no samples" % name)
else:
    n = len(v)
    print("   %-22s median %3d%%   p90 %3d%%   max %3d%%   (n=%d)%s"
          % (name, v[n // 2], v[min(n - 1, int(n * 0.9))], v[-1], n,
             ("  [%s]" % label) if label else ""))
PY
}

countdown() {
    local n="$1"
    while [ "$n" -gt 0 ]; do
        printf '\r   starting in %d... ' "$n"
        sleep 1
        n=$((n - 1))
    done
    printf '\r   GO — %-30s\n' "sampling for 10s"
}

overview() {
    gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell \
        --method org.freedesktop.DBus.Properties.Set \
        org.gnome.Shell OverviewActive "<$1>" >/dev/null 2>&1
}

TMP="$(mktemp -d)"
# Results are also appended to a log, so a run can be read back afterwards
# rather than depending on the terminal it was run in still being on screen.
LOG="${AURA_GPU_LOG:-${TAHOE_GPU_LOG:-$HOME/.cache/aura-glass/gpu-live.log}}"
mkdir -p "$(dirname "$LOG")"
{
    echo
    echo "=== $(date '+%Y-%m-%d %H:%M:%S')${LABEL:+  label: $LABEL} ==="
} >> "$LOG"
trap 'rm -rf "$TMP"; overview false' EXIT

say "sampling $CARD${LABEL:+  (label: $LABEL)}"

# --- idle -----------------------------------------------------------------
say "idle — don't touch anything for 8s"
sample_into 8 "$TMP/idle"
report "idle" "$TMP/idle"

# --- overview, scripted ---------------------------------------------------
# The one interaction that can be driven from a script: OverviewActive is a
# writable property on org.gnome.Shell and works on the live bus.
say "overview — toggling 6 times"
( for _ in 1 2 3 4 5 6; do overview true; sleep 1; overview false; sleep 1; done ) &
DRIVER=$!
sample_into 13 "$TMP/overview"
wait $DRIVER 2>/dev/null
overview false
report "overview toggle" "$TMP/overview"

if [ "$QUICK" = 1 ]; then
    say "done (--quick: skipped the hands-on scenarios)"
    exit 0
fi

# --- window drag, prompted ------------------------------------------------
# Wayland has no scriptable pointer for this, and injecting one at the uinput
# level would hit whatever is focused rather than a window we chose. So this
# asks, which is less elegant and measures the real thing.
say "window drag — drag a window around the screen when the count starts"
countdown 3
sample_into 10 "$TMP/drag"
report "window drag" "$TMP/drag"

# --- menus, prompted ------------------------------------------------------
say "menus — open and close Quick Settings and the date menu when it starts"
countdown 3
sample_into 10 "$TMP/menus"
report "menus" "$TMP/menus"

say "done — results also in $LOG"
