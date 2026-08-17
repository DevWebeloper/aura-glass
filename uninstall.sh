#!/usr/bin/env bash
#
# aura-glass — put the desktop back.
#
# Everything here is reversible because the installer only ever appended to
# generated files (inside a marked block) and kept a first-run copy of anything
# it overwrote. Extensions are left installed unless you ask for them to go —
# removing an extension also throws away its settings.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$REPO_ROOT/lib/common.sh"
# shellcheck source=lib/steps-gdm.sh
. "$REPO_ROOT/lib/steps-gdm.sh"

CONF_DIR="$HOME/.config/aura-glass"
[ -d "$CONF_DIR" ] || [ ! -d "$HOME/.config/tahoe-glass" ] || CONF_DIR="$HOME/.config/tahoe-glass"
BACKUP_DIR="$CONF_DIR/backups"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
SRC_CACHE="$HOME/.cache/aura-glass/src"
[ -d "$SRC_CACHE" ] || [ ! -d "$HOME/.cache/tahoe-glass/src" ] || SRC_CACHE="$HOME/.cache/tahoe-glass/src"

ASSUME_YES=0
DRY_RUN=0
REMOVE_EXTENSIONS=0
REMOVE_ASSETS=0
REMOVE_GDM=0
REMOVE_GDM_MONITORS=0
EXPLICIT_FLAGS=0
FORCE_INTERACTIVE=0

usage() {
    cat <<EOF
${C_BLD}aura-glass uninstall${C_OFF}

  ./uninstall.sh [options]

    --interactive   launch the interactive uninstall wizard explicitly
    --extensions    also remove the extensions this installed (and their settings)
    --assets        also remove the Tahoe theme, the icon pack (Colloid or
                    Reversal) and MacTahoe cursors
    --gdm           restore the stock GDM login screen (requires sudo)
    --gdm-monitors  revert synced GDM monitor layout back to default (requires sudo)
    --all           all of the above (--full is accepted as the same thing)
    -y, --yes       answer yes to every prompt
    -n, --dry-run   print what would happen, change nothing
    -h, --help      this

  With no options or in interactive mode, you can select which components to remove.
  By default, it removes the CSS tweaks, the dconf preset, the systemd
  unit and the theme settings, and leaves everything it downloaded in place.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --interactive)  FORCE_INTERACTIVE=1; shift ;;
        --extensions)   REMOVE_EXTENSIONS=1; EXPLICIT_FLAGS=1; shift ;;
        --assets)       REMOVE_ASSETS=1; EXPLICIT_FLAGS=1; shift ;;
        --gdm)          REMOVE_GDM=1; EXPLICIT_FLAGS=1; shift ;;
        --gdm-monitors) REMOVE_GDM_MONITORS=1; EXPLICIT_FLAGS=1; shift ;;
        --all|--full)   REMOVE_EXTENSIONS=1; REMOVE_ASSETS=1; REMOVE_GDM=1; REMOVE_GDM_MONITORS=1; EXPLICIT_FLAGS=1; shift ;;
        -y|--yes)       ASSUME_YES=1; EXPLICIT_FLAGS=1; shift ;;
        -n|--dry-run)   DRY_RUN=1; EXPLICIT_FLAGS=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              usage; die "unknown option: $1" ;;
    esac
done

printf '\n%s  aura-glass uninstall%s\n' "$C_BLD" "$C_OFF"
[ "$DRY_RUN" = 1 ] && printf '%s  dry run — nothing will be changed%s\n' "$C_DIM" "$C_OFF"

# Interactive wizard when no explicit mode flag is given in an interactive terminal
if { [ "$EXPLICIT_FLAGS" = 0 ] || [ "$FORCE_INTERACTIVE" = 1 ]; } && [ "$ASSUME_YES" = 0 ] && [ -t 0 ]; then
    cat <<EOF

${C_BLD}Choose uninstall scope:${C_OFF}
  ${C_BLD}[1]${C_OFF} Revert styling only (keep downloaded extensions & icon assets) ${C_DIM}[Default]${C_OFF}
  ${C_BLD}[2]${C_OFF} Revert styling + Remove Aura Glass extensions
  ${C_BLD}[3]${C_OFF} Full wipe (Revert styling, delete extensions, downloaded themes, icons & backups)
  ${C_BLD}[4]${C_OFF} Cancel

EOF
    printf '  Choice [1-4, default 1]: '
    read -r scope_choice || scope_choice=1
    case "${scope_choice:-1}" in
        1)
            REMOVE_EXTENSIONS=0
            REMOVE_ASSETS=0
            ;;
        2)
            REMOVE_EXTENSIONS=1
            REMOVE_ASSETS=0
            ;;
        3)
            REMOVE_EXTENSIONS=1
            REMOVE_ASSETS=1
            REMOVE_GDM=1
            REMOVE_GDM_MONITORS=1
            ;;
        4|q|quit)
            printf '\n  Uninstall cancelled.\n\n'
            exit 0
            ;;
        *)
            warn "unrecognised choice '$scope_choice' — defaulting to revert styling only"
            REMOVE_EXTENSIONS=0
            REMOVE_ASSETS=0
            ;;
    esac

    # If GDM theme is currently installed and not marked for removal by scope choice
    if [ "$REMOVE_GDM" = 0 ] && [ -f "$CONF_DIR/gdm-installed" ]; then
        if confirm "Restore stock GDM login screen & remove wallpaper sync (requires sudo)?" 0; then
            REMOVE_GDM=1
        fi
    fi

    # If GDM monitors were synced and not marked for removal by scope choice
    if [ "$REMOVE_GDM_MONITORS" = 0 ] && { [ -f "$CONF_DIR/gdm-monitors-synced" ] || [ -f "/var/lib/gdm/.config/monitors.xml" ] || [ -f "/etc/xdg/monitors.xml" ]; }; then
        if confirm "Revert GDM primary monitor sync back to system default (requires sudo)?" 0; then
            REMOVE_GDM_MONITORS=1
        fi
    fi
fi

# ---------------------------------------------------------------------- css --

step "Removing the CSS block"
strip_block() {
    local target="$1"
    [ -f "$target" ] || { skip "not present: $target"; return 0; }
    if [ "$DRY_RUN" = 1 ]; then info "dry-run: strip block from $target"; return 0; fi
    python3 - "$target" <<'PY'
import sys, re
target = sys.argv[1]
css = open(target, encoding="utf-8").read()
new = css
# "tahoe-tweaks" and "tahoe-glass" are prior markers.
for name in ("aura-glass", "tahoe-glass", "tahoe-tweaks"):
    new = re.sub(
        r"/\* >>> %s BEGIN <<< \*/.*?/\* >>> %s END <<< \*/\n?" % (name, name),
        "", new, flags=re.S,
    )
if new != css:
    open(target, "w", encoding="utf-8").write(new)
    print("cleaned", target)
else:
    print("no block in", target)
PY
}
for f in "$HOME/.themes/Tahoe-Dark/gnome-shell/gnome-shell.css" \
         "$HOME/.config/gtk-4.0/gtk.css" \
         "$HOME/.config/gtk-4.0/gtk-dark.css" \
         "$HOME/.config/gtk-3.0/gtk.css"; do
    strip_block "$f" | sed 's/^/    /'
done

# ------------------------------------------------------------------ backups --

step "Restoring the files that were overwritten"
restore() {
    local orig="$BACKUP_DIR/$1.orig" dst="$2"
    if [ -f "$orig" ]; then
        run cp -a "$orig" "$dst"
        ok "restored $dst"
        return 0
    fi
    # No .orig because there was no file here before — the theme's own
    # installer created it. Stripping our marked block out of it leaves the
    # whole libadwaita override in place, which keeps every GTK4 app themed
    # after an uninstall, so the file goes rather than stays.
    if [ -e "$BACKUP_DIR/$1.absent" ]; then
        [ -e "$dst" ] || { skip "$dst already gone"; return 0; }
        run rm -f "$dst"
        ok "removed $dst (nothing was there before install)"
        return 0
    fi
    skip "no backup of $1"
}
restore "gtk4-gtk.css"      "$HOME/.config/gtk-4.0/gtk.css"
restore "gtk4-gtk-dark.css" "$HOME/.config/gtk-4.0/gtk-dark.css"
restore "gtk3-gtk.css"      "$HOME/.config/gtk-3.0/gtk.css"
# The shell sheet needs restoring rather than just un-blocking: apply flattens
# the theme's own shadow and gradient values in place, so stripping the appended
# block leaves a theme that is still flat. Unlike the GTK files this one has no
# .absent marker — the theme's installer always creates it — so a missing backup
# falls through to "no backup of", which is correct.
restore "gnome-shell.css"   "$HOME/.themes/Tahoe-Dark/gnome-shell/gnome-shell.css"

# ----------------------------------------------------------------- settings --

step "Resetting theme settings"
run gsettings reset org.gnome.desktop.interface gtk-theme
run gsettings reset org.gnome.desktop.interface icon-theme
run gsettings reset org.gnome.desktop.interface cursor-theme
run gsettings reset org.gnome.desktop.interface accent-color
ok "back to the GNOME defaults (window buttons left intact)"

step "Resetting extension settings to GNOME defaults"
# Core extensions (dconf/core.ini)
run dconf reset -f /org/gnome/shell/extensions/openbar/
run dconf reset -f /org/gnome/shell/extensions/blur-my-shell/
run dconf reset -f /org/gnome/shell/extensions/custom-osd/
run dconf reset -f /org/gnome/shell/extensions/user-theme/
# Optional extensions (dconf/extras.ini)
run dconf reset -f /org/gnome/shell/extensions/just-perfection/
run dconf reset -f /org/gnome/shell/extensions/gnome-ui-tune/
run dconf reset -f /org/gnome/shell/extensions/space-bar/
run dconf reset -f /org/gnome/shell/extensions/vitals/
run dconf reset -f /org/gnome/shell/extensions/clipboard-indicator/
run dconf reset -f /org/gnome/shell/extensions/hotedge/
run dconf reset -f /org/gnome/shell/extensions/appindicator/
ok "all extension configs reset to their defaults"

# ------------------------------------------------------------------- units --

step "Removing systemd units"
found=0
for u in aura-glass-panel-blur.service tahoe-glass-panel-blur.service bms-panel-blur-rebuild.service \
         aura-glass-icon-sync.service tahoe-glass-icon-sync.service \
         aura-glass-gdm-sync.service tahoe-glass-gdm-sync.service; do
    [ -f "$HOME/.config/systemd/user/$u" ] || continue
    found=1
    run systemctl --user disable --now "$u" >/dev/null 2>&1 || true
    run rm -f "$HOME/.config/systemd/user/$u"
    ok "removed $u"
done
if [ "$found" = 1 ]; then
    run systemctl --user daemon-reload
else
    skip "not installed"
fi

# -------------------------------------------------------------- extensions --

if [ "$REMOVE_EXTENSIONS" = 1 ]; then
    step "Removing extensions"
    # Only the ones installed under $HOME are touched: a distro-packaged copy
    # in /usr/share belongs to the system, not to us.
    for u in openbar@neuromorph custom-osd@neuromorph blur-my-shell@aunetx \
             just-perfection-desktop@just-perfection gnome-ui-tune@itstime.tech \
             space-bar@luchrioh auto-accent-colour@Wartybix \
             Vitals@CoreCoding.com clipboard-indicator@tudmotu.com \
             ddterm@amezin.github.com kiwimenu@kemma \
             hotedge@jonathan.jdoda.ca restartto@tiagoporsch.github.io \
             xwayland-indicator@swsnr.de appindicatorsupport@rgcjonas.gmail.com \
             compiz-alike-magic-lamp-effect@hermes83.github.com \
             add-to-steam@pupper.space; do
        if [ -d "$EXT_DIR/$u" ]; then
            run gnome-extensions disable "$u" 2>/dev/null || true
            run rm -rf "$EXT_DIR/$u"
            ok "removed $u"
        else
            skip "$u not installed here"
        fi
    done
    # user-theme is deliberately left alone: it is a stock GNOME extension that
    # plenty of other setups depend on.
    info "user-theme left installed — it is a stock GNOME extension"
fi

# ------------------------------------------------------------------ assets --

if [ "$REMOVE_ASSETS" = 1 ]; then
    step "Removing downloaded themes, icons and cursors"
    run rm -rf "$HOME/.themes/Tahoe-Dark" "$HOME/.themes/Tahoe-Light"
    # Reversal is matched as well as Colloid: --icons reversal installs it, and
    # install rewrites its pan-*.svg in place with no backup, so leaving the
    # theme on disk leaves patched files behind with nothing to restore them.
    for d in "$HOME"/.local/share/icons/Colloid* "$HOME"/.local/share/icons/Reversal* \
             "$HOME"/.local/share/icons/MacTahoe*; do
        [ -e "$d" ] && { run rm -rf "$d"; ok "removed $(basename "$d")"; }
    done
fi

# GDM revert runs before the cache wipe so it can still reach WhiteSur's
# tweaks.sh inside $SRC_CACHE.
if [ "$REMOVE_GDM" = 1 ] || { [ "$REMOVE_ASSETS" = 1 ] && [ -f "$CONF_DIR/gdm-installed" ]; }; then
    uninstall_gdm
fi

if [ "$REMOVE_GDM_MONITORS" = 1 ] || [ "$REMOVE_GDM" = 1 ]; then
    unsync_gdm_monitors
fi

if [ "$REMOVE_ASSETS" = 1 ]; then
    run rm -rf "$HOME/.cache/aura-glass" "$HOME/.cache/tahoe-glass"
fi

# ------------------------------------------------------------------ our own --

if [ -f "$CONF_DIR/rounded-blur" ]; then
    step "gnome-rounded-blur"
    # Not removed from here: it is the one thing this project installs outside
    # $HOME, and an uninstaller that runs sudo on your behalf is worse than one
    # that tells you what to run.
    info "installed into /usr by this project. To remove it:"
    info "    sudo pacman -Rs gnome-rounded-blur       # if it came from the AUR"
    info "    sudo ninja -C ~/.cache/aura-glass/src/gnome-rounded-blur/build uninstall"
fi

step "Removing aura-glass itself"
run rm -f "$HOME/.local/bin/aura-glass-apply" "$HOME/.local/bin/aura-glass-icon-sync" \
          "$HOME/.local/bin/aura-glass-panel-blur" "$HOME/.local/bin/aura-glass-gdm-sync" \
          "$HOME/.local/bin/tahoe-glass-apply" "$HOME/.local/bin/tahoe-glass-icon-sync" \
          "$HOME/.local/bin/tahoe-glass-panel-blur" "$HOME/.local/bin/tahoe-glass-gdm-sync"
# Stamps describing artifacts that have just been removed, rather than choices
# the user made — so they go now instead of waiting on the $CONF_DIR prompt.
#
# The sheets go by glob rather than by name. They used to be listed one by one,
# which was already leaving some behind when there were three of them, and the
# split into per-concern sheets turned that into fourteen names to keep in step
# with css/. A glob cannot fall behind. The remembered choices that describe a
# theme still on disk — icons, icon-pack, grain — are deliberately not matched:
# those are answers the user gave rather than artifacts, and they wait for the
# prompt below.
run rm -f "$CONF_DIR"/shell-*.css "$CONF_DIR"/gtk3-*.css "$CONF_DIR"/gtk4-*.css
run rm -f "$CONF_DIR/bms-ref" "$CONF_DIR/bms-source" \
          "$CONF_DIR/popup-blur" \
          "$CONF_DIR/window-blur" \
          "$CONF_DIR/app-blur-scope" \
          "$CONF_DIR/rounded-blur" \
          "$CONF_DIR/app-transparency" \
          "$CONF_DIR/app-opacity" \
          "$CONF_DIR/gdm-installed" \
          "$CONF_DIR/gdm-monitors-synced" \
          "$CONF_DIR/openbar-patch" "$CONF_DIR/custom-osd-patch"
if confirm "Delete $CONF_DIR (this also deletes the backups above)?" 0; then
    run rm -rf "$CONF_DIR"
    ok "removed"
else
    skip "kept — backups are still in $BACKUP_DIR"
fi

step "Done"
printf '\n    Log out and back in to finish.\n\n'
prompt_logout
