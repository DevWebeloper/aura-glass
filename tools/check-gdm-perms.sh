#!/usr/bin/env bash
# Guards the GDM login files against going back to world-writable. They are
# owned by the desktop user (who syncs them without sudo) and mode 644, and the
# boot-time layout unit runs as that user, not nobody.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
bad() { echo "FAIL: $*"; fail=1; }

if grep -nE 'chmod[[:space:]]+(0?666|a\+w|o\+w)|0666' "$REPO/lib/steps-gdm.sh" "$REPO"/bin/* >&2; then
    bad "world-writable mode in lib/steps-gdm.sh or bin/"
fi
unit="$REPO/systemd/aura-glass-gdm-layout.service"
grep -q '^User=@AURA_USER@$' "$unit" || bad "unit lacks User=@AURA_USER@ placeholder"
! grep -q '^User=nobody' "$unit" || bad "unit still runs as nobody"

# Run the real unit-install step with sudo recorded instead of executed.
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
out="$(
    REPO_ROOT="$REPO" DRY_RUN=0
    info() { :; }; ok() { :; }; warn() { :; }
    # shellcheck source=/dev/null
    source "$REPO/lib/steps-gdm.sh"
    sudo() {
        if [ "$1" = install ]; then
            local a src="" dst=""
            for a in "$@"; do case "$a" in -*) ;; install) ;; *) src="$dst"; dst="$a" ;; esac; done
            [ "$dst" = "$GDM_LAYOUT_UNIT" ] && cp "$src" "$work/unit"
        fi
        return 0
    }
    install_gdm_layout_unit
)" || bad "install_gdm_layout_unit failed: $out"
if [ -f "$work/unit" ]; then
    grep -qx "User=$(id -un)" "$work/unit" || bad "installed unit lacks User=$(id -un)"
    ! grep -q '@AURA_USER@' "$work/unit" || bad "placeholder left in installed unit"
else
    bad "unit-install step did not install the unit"
fi

[ "$fail" = 0 ] && echo "check-gdm-perms: ok"
exit "$fail"
