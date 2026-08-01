#!/usr/bin/env bash
#
# tahoe-glass — put the desktop back.
#
# Everything here is reversible because the installer only ever appended to
# generated files (inside a marked block) and kept a first-run copy of anything
# it overwrote. Extensions are left installed unless you ask for them to go —
# removing an extension also throws away its settings.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$REPO_ROOT/lib/common.sh"

CONF_DIR="$HOME/.config/tahoe-glass"
BACKUP_DIR="$CONF_DIR/backups"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"

ASSUME_YES=0
DRY_RUN=0
REMOVE_EXTENSIONS=0
REMOVE_ASSETS=0

usage() {
    cat <<EOF
${C_BLD}tahoe-glass uninstall${C_OFF}

  ./uninstall.sh [options]

    --extensions   also remove the extensions this installed (and their settings)
    --assets       also remove the Tahoe theme, Colloid icons and MacTahoe cursors
    --all          both of the above
    -y, --yes      answer yes to every prompt
    -n, --dry-run  print what would happen, change nothing
    -h, --help     this

  With no options this removes the CSS tweaks, the dconf preset, the systemd
  unit and the theme settings, and leaves everything it downloaded in place.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --extensions) REMOVE_EXTENSIONS=1; shift ;;
        --assets)     REMOVE_ASSETS=1; shift ;;
        --all)        REMOVE_EXTENSIONS=1; REMOVE_ASSETS=1; shift ;;
        -y|--yes)     ASSUME_YES=1; shift ;;
        -n|--dry-run) DRY_RUN=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            usage; die "unknown option: $1" ;;
    esac
done

printf '\n%s  tahoe-glass uninstall%s\n' "$C_BLD" "$C_OFF"
[ "$DRY_RUN" = 1 ] && printf '%s  dry run — nothing will be changed%s\n' "$C_DIM" "$C_OFF"

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
# "tahoe-tweaks" is the marker this project used before it was named.
for name in ("tahoe-glass", "tahoe-tweaks"):
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
    [ -f "$orig" ] || { skip "no backup of $1"; return 0; }
    run cp -a "$orig" "$dst"
    ok "restored $dst"
}
restore "gtk4-gtk.css"      "$HOME/.config/gtk-4.0/gtk.css"
restore "gtk4-gtk-dark.css" "$HOME/.config/gtk-4.0/gtk-dark.css"
restore "gtk3-gtk.css"      "$HOME/.config/gtk-3.0/gtk.css"

# ----------------------------------------------------------------- settings --

step "Resetting theme settings"
run gsettings reset org.gnome.desktop.interface gtk-theme
run gsettings reset org.gnome.desktop.interface icon-theme
run gsettings reset org.gnome.desktop.interface cursor-theme
run gsettings reset org.gnome.desktop.interface accent-color
run gsettings reset org.gnome.desktop.wm.preferences button-layout
run dconf reset /org/gnome/shell/extensions/user-theme/name
ok "back to the GNOME defaults"

step "Resetting the extension preset"
if confirm "Reset Open Bar, Blur My Shell and Custom OSD to their defaults?" 1; then
    run dconf reset -f /org/gnome/shell/extensions/openbar/
    run dconf reset -f /org/gnome/shell/extensions/blur-my-shell/
    run dconf reset -f /org/gnome/shell/extensions/custom-osd/
    ok "reset"
else
    skip "kept"
fi

# ------------------------------------------------------------------- units --

step "Removing the panel blur unit"
# bms-panel-blur-rebuild is the name this unit had before the project was named.
found=0
for u in tahoe-glass-panel-blur.service bms-panel-blur-rebuild.service \
         tahoe-glass-icon-sync.service; do
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
    # Only the ones installed under $HOME are touched: on Bazzite several of
    # these live in /usr/share and belong to the image, not to us.
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
    for d in "$HOME"/.local/share/icons/Colloid* "$HOME"/.local/share/icons/MacTahoe*; do
        [ -e "$d" ] && { run rm -rf "$d"; ok "removed $(basename "$d")"; }
    done
    run rm -rf "$HOME/.cache/tahoe-glass"
fi

# ------------------------------------------------------------------ our own --

step "Removing tahoe-glass itself"
run rm -f "$HOME/.local/bin/tahoe-glass-apply" "$HOME/.local/bin/tahoe-glass-icon-sync" \
          "$HOME/.local/bin/tahoe-glass-panel-blur"
if confirm "Delete $CONF_DIR (this also deletes the backups above)?" 0; then
    run rm -rf "$CONF_DIR"
    ok "removed"
else
    skip "kept — backups are still in $BACKUP_DIR"
fi

step "Done"
printf '\n    Log out and back in to finish.\n\n'
