#!/usr/bin/env bash
# Exercise the Liquid Glass lifecycle against a scratch extension directory and
# dconf/gsettings stubs.  The installer itself cannot be run non-dry here:
# those commands would address the caller's session bus even when HOME points
# at a temporary directory.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=()
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
export HOME="$scratch"
mkdir -p "$HOME/.local/share/gnome-shell/extensions" "$scratch/fakebin"
export EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
export CONF_DIR="$HOME/.config/aura-glass"
export SRC_CACHE="$HOME/.cache/aura-glass/src"
export FAKE_DCONF="$scratch/dconf" FAKE_ENABLED="$scratch/enabled" FAKE_LOG="$scratch/log"
: > "$FAKE_DCONF"; : > "$FAKE_ENABLED"; : > "$FAKE_LOG"

cat > "$scratch/fakebin/dconf" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  read) awk -F '\t' -v k="$2" '$1 == k { print $2; found=1 } END { exit(found ? 0 : 1) }' "$FAKE_DCONF" ;;
  write) grep -v -F "$2"$'\t' "$FAKE_DCONF" > "$FAKE_DCONF.tmp" || true; printf '%s\t%s\n' "$2" "$3" >> "$FAKE_DCONF.tmp"; mv "$FAKE_DCONF.tmp" "$FAKE_DCONF" ;;
  *) exit 1 ;;
esac
STUB
cat > "$scratch/fakebin/gsettings" <<'STUB'
#!/usr/bin/env bash
case "$1:$2:$3" in
  list-schemas::) printf '%s\n' org.gnome.shell.extensions.liquid-glass@thinkingcoding1231.gmail.com ;;
  get:org.gnome.shell:enabled-extensions) printf '[%s]\n' "$(sed "s/^/'/;s/$/'/" "$FAKE_ENABLED" | paste -sd, -)" ;;
  set:org.gnome.shell:enabled-extensions) printf '%s\n' "$4" | tr -d "[]' " | tr , '\n' | sed '/^$/d' > "$FAKE_ENABLED" ;;
  *) exit 1 ;;
esac
STUB
cat > "$scratch/fakebin/gnome-extensions" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  list) cat "$FAKE_ENABLED" ;;
  enable) printf 'enable:%s\n' "$2" >> "$FAKE_LOG" ;;
  disable) printf 'disable:%s\n' "$2" >> "$FAKE_LOG" ;;
  info) grep -qxF "$2" "$FAKE_ENABLED" && printf 'State: ACTIVE\n' || printf 'State: INACTIVE\n' ;;
  *) exit 1 ;;
esac
STUB
cat > "$scratch/fakebin/glib-compile-schemas" <<'STUB'
#!/usr/bin/env bash
touch "$1/gschemas.compiled"
STUB
chmod +x "$scratch/fakebin"/*
export PATH="$scratch/fakebin:$PATH"

# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=lib/steps.sh
source "$ROOT/lib/steps.sh"
# shellcheck source=lib/steps-extensions.sh
source "$ROOT/lib/steps-extensions.sh"
# shellcheck source=lib/steps-dconf.sh
source "$ROOT/lib/steps-dconf.sh"

DRY_RUN=0
WANT_LIQUID_GLASS=1
LIQUID_GLASS_EFFECTIVE=1
WANT_BLUR=1
WANT_STYLING=1

if ! declare -F install_liquid_glass >/dev/null \
   || ! declare -F apply_liquid_glass_profile >/dev/null \
   || ! declare -F restore_liquid_glass_profile >/dev/null; then
  printf 'liquid-glass check FAILED\n\n  Liquid Glass lifecycle functions are not implemented\n'
  exit 1
fi

# The runtime source comes from clone_pinned in production.  Its fixture has
# every file the filtered payload promises and a schema which glib can compile.
clone_pinned() {
  local _repo="$1" _ref="$2" dst="$3"
  dst="$dst/liquid-glass@thinkingcoding1231.gmail.com"
  mkdir -p "$dst/dist" "$dst/shaders" "$dst/schemas"
  for f in extension.js metadata.json stylesheet.css prefs.js resources.gresource resources.gresource.xml LICENSE; do : > "$dst/$f"; done
  printf '{"uuid":"liquid-glass@thinkingcoding1231.gmail.com","shell-version":["49","50"]}\n' > "$dst/metadata.json"
  printf '<schemalist><schema id="org.gnome.shell.extensions.liquid-glass@thinkingcoding1231.gmail.com" path="/org/gnome/shell/extensions/liquid-glass/"></schema></schemalist>\n' > "$dst/schemas/org.gnome.shell.extensions.liquid-glass@thinkingcoding1231.gmail.com.gschema.xml"
}
ext_supports_shell() { return 0; }

install_liquid_glass
[ -f "$EXT_DIR/$LIQUID_GLASS_UUID/.aura-glass-liquid-glass" ] || failures+=("owned payload was not marked")
[ "$(cat "$CONF_DIR/liquid-glass/ref")" = "$LIQUID_GLASS_REF" ] || failures+=("owned payload ref was not recorded")

# A valid unmarked copy belongs to its existing owner.  Validation may compile
# its schema, but its files and the absence of Aura's ownership marker survive.
mv "$EXT_DIR/$LIQUID_GLASS_UUID" "$scratch/aura-owned"
cp -a "$SRC_CACHE/liquid-glass/$LIQUID_GLASS_UUID" "$EXT_DIR/$LIQUID_GLASS_UUID"
touch "$EXT_DIR/$LIQUID_GLASS_UUID/external-owner-sentinel"
install_liquid_glass
[ -f "$EXT_DIR/$LIQUID_GLASS_UUID/external-owner-sentinel" ] || failures+=("external Liquid Glass was replaced")
[ ! -f "$EXT_DIR/$LIQUID_GLASS_UUID/.aura-glass-liquid-glass" ] || failures+=("external Liquid Glass was claimed by Aura")

# Stage live conflicts once, leave Aura's own memos alone, and queue only for
# the next session.  A second apply must reuse the first snapshot.
printf '%s\t%s\n' \
  /org/gnome/shell/extensions/blur-my-shell/popup/blur true \
  /org/gnome/shell/extensions/blur-my-shell/popup/notification false \
  /org/gnome/shell/extensions/dash-to-dock/blur true \
  /org/gnome/shell/extensions/openbar/apply-menu-notif true > "$FAKE_DCONF"
printf '%s\n' custom-osd@neuromorph > "$FAKE_ENABLED"
mkdir -p "$CONF_DIR"; printf '0\n' > "$CONF_DIR/popup-blur"; printf '1\n' > "$CONF_DIR/notification-blur"
apply_liquid_glass_profile
[ "$(dconf read /org/gnome/shell/extensions/blur-my-shell/popup/blur)" = false ] || failures+=("popup blur was not suspended")
[ "$(dconf read /org/gnome/shell/extensions/blur-my-shell/popup/notification)" = false ] || failures+=("notification blur was not suspended")
[ "$(dconf read /org/gnome/shell/extensions/dash-to-dock/blur)" = false ] || failures+=("dock blur was not suspended")
[ "$(dconf read /org/gnome/shell/extensions/openbar/apply-menu-notif)" = false ] || failures+=("Open Bar notification override was not cleared")
[ "$(cat "$CONF_DIR/popup-blur")" = 0 ] || failures+=("Liquid Glass overwrote Aura popup memo")
[ "$(cat "$CONF_DIR/notification-blur")" = 1 ] || failures+=("Liquid Glass overwrote Aura notification memo")
grep -qxF "$LIQUID_GLASS_UUID" "$FAKE_ENABLED" || failures+=("Liquid Glass was not queued for next login")
grep -qxF 'disable:custom-osd@neuromorph' "$FAKE_LOG" || failures+=("enabled Custom OSD was not suspended")

WANT_LIQUID_GLASS=0
restore_liquid_glass_profile
[ "$(dconf read /org/gnome/shell/extensions/blur-my-shell/popup/blur)" = true ] || failures+=("popup blur snapshot was not restored")
[ "$(dconf read /org/gnome/shell/extensions/dash-to-dock/blur)" = true ] || failures+=("dock blur snapshot was not restored")
[ -e "$CONF_DIR/liquid-glass/profile-snapshot" ] && failures+=("profile snapshot was not removed after restoration")
grep -qxF "disable:$LIQUID_GLASS_UUID" "$FAKE_LOG" || failures+=("Liquid Glass was not disabled during restore")

# --extensions is allowed to remove only Aura's marked runtime.  The real
# uninstaller is dry-run here, so its complete scope is exercised without
# touching this checker or the caller's desktop.
uninstall_home="$scratch/uninstall-home"
uninstall_target="$uninstall_home/.local/share/gnome-shell/extensions/$LIQUID_GLASS_UUID"
mkdir -p "$uninstall_target" "$uninstall_home/.config/aura-glass"
touch "$uninstall_target/external-owner-sentinel"
uninstall_out="$(HOME="$uninstall_home" bash "$ROOT/uninstall.sh" --extensions --dry-run --yes 2>&1)"
case "$uninstall_out" in
  *"externally managed — left installed"*) ;;
  *) failures+=("uninstall did not preserve an unmarked external Liquid Glass") ;;
esac
touch "$uninstall_target/.aura-glass-liquid-glass"
uninstall_out="$(HOME="$uninstall_home" bash "$ROOT/uninstall.sh" --extensions --dry-run --yes 2>&1)"
case "$uninstall_out" in
  *"rm -rf $uninstall_target"*) ;;
  *) failures+=("uninstall did not select Aura-marked Liquid Glass for removal") ;;
esac

if [ "${#failures[@]}" -gt 0 ]; then
  printf 'liquid-glass check FAILED\n\n  %s\n' "${failures[@]}"
  exit 1
fi
printf 'liquid-glass check passed — pinned payload, conflict snapshot, queued activation and restore covered\n'
