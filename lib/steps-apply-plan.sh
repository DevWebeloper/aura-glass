# shellcheck shell=bash
# Conservative selector for settings-only incremental Apply. Resolution stays in
# install.sh; this file only classifies the flags a caller actually typed.

APPLY_ACTIONS=()
APPLY_FALLBACK_REASON=""

_apply_add() { local value; for value in "${APPLY_ACTIONS[@]}"; do [ "$value" = "$1" ] && return; done; APPLY_ACTIONS+=("$1"); }

select_apply_actions() {
    APPLY_ACTIONS=()
    APPLY_FALLBACK_REASON=""
    local flag
    for flag in "${TYPED_FLAGS[@]}"; do
        case "$flag" in
            --settings-only|--incremental|--plan-json|--yes|-y|--dry-run|-n) ;;
            --adaptive-blur|--adaptive-blur=*) _apply_add adaptive-blur ;;
            --accent|--accent=*) _apply_add accent ;;
            --update-check|--no-update-check|--update-channel|--update-channel=*) _apply_add update-check ;;
            --window-menu|--no-window-menu) _apply_add window-menu ;;
            --font|--font=*) _apply_add font ;;
            --icons|--icons=*|--no-icons) _apply_add icons ;;
            --glass-style|--glass-style=*|--liquid-windows|--no-liquid-windows) _apply_add glass-style ;;
            # A corner is painted by the sheet and clipped by the blur behind
            # it, and the two must stay equal (CLAUDE.md rule 3).
            --radius-preset|--radius-preset=*|--radius-custom|--radius-custom=*) _apply_add css; _apply_add radius ;;
            --popup-blur|--no-popup-blur) _apply_add css; _apply_add popup-blur ;;
            --gtk-apps-blur|--all-apps-blur|--no-window-blur) _apply_add css; _apply_add app-blur; _apply_add app-opacity ;;
            --cursor-size|--cursor-size=*) _apply_add cursor-size ;;
            --cursors|--cursors=*|--no-cursors) _apply_add cursor-theme ;;
            --window-buttons|--window-buttons=*) _apply_add window-buttons ;;
            # Every blur amount and brightness is one rewrite of the pipelines
            # blob from dconf/core.ini's values (apply_blur_pipelines), so any
            # of them, alone or together, is that one step.
            --blur-strength|--blur-strength=*|--blur-brightness|--blur-brightness=*|--*-blur-strength|--*-blur-strength=*|--window-brightness|--window-brightness=*|--app-brightness|--app-brightness=*|--window-blur-brightness|--window-blur-brightness=*|--popup-brightness|--popup-brightness=*|--panel-brightness|--panel-brightness=*|--lockscreen-brightness|--lockscreen-brightness=*|--maximized-brightness|--maximized-brightness=*) _apply_add blur-pipelines ;;
            --fullscreen-blur|--no-fullscreen-blur) _apply_add fullscreen-blur ;;
            --maximized-blur|--maximized-blur=*|--maximized-opacity|--maximized-opacity=*) _apply_add maximized-blur ;;
            --osd-device-name|--no-osd-device-name) _apply_add osd-device-name ;;
            --osd-style|--osd-style=*) _apply_add osd-style ;;
            --osd-opacity|--osd-opacity=*|--osd-tint|--osd-tint=*) _apply_add osd-background ;;
            --system-icons|--system-icons=*) _apply_add system-icons ;;
            --smooth-animations|--no-smooth-animations) _apply_add smooth-animations ;;
            --window-animation-speed|--window-animation-speed=*|--notification-animation-speed|--notification-animation-speed=*|--menu-animation-speed|--menu-animation-speed=*) _apply_add animation-speed ;;
            --top-bar-icon|--no-top-bar-icon) _apply_add top-bar-icon ;;
            --app-blur-allow|--app-blur-allow=*|--app-blur-block|--app-blur-block=*) _apply_add app-blur ;;
            # The level is written twice: the GTK stylesheet's alpha (css) and
            # Blur My Shell's window actor opacity, which is all a browser or
            # Electron window has. Classed as css alone, a slider move rewrote
            # the sheet and left the actor at its old value, so Chrome stopped
            # showing the blur while GTK apps still did.
            --app-transparency|--app-transparency=*|--no-app-transparency) _apply_add css; _apply_add app-opacity ;;
            --app-tint-color|--app-tint-color=*|--shell-tint-color|--shell-tint-color=*|--dock-tint-color|--dock-tint-color=*|--panel-tint-color|--panel-tint-color=*|--maximized-panel-tint-color|--maximized-panel-tint-color=*|--popup-opacity|--popup-opacity=*|--maximized-panel-brightness|--maximized-panel-brightness=*|--panel-height|--panel-height=*|--titlebar-button-style|--titlebar-button-style=*) _apply_add css ;;
            *) APPLY_FALLBACK_REASON="unclassified flag: $flag"; APPLY_ACTIONS=(full); return ;;
        esac
    done
    if [ "${#APPLY_ACTIONS[@]}" = 0 ]; then
        APPLY_FALLBACK_REASON="no narrow setting was typed"
        APPLY_ACTIONS=(full)
        return
    fi
    # The settings window sends only --accent for an accent edit. Moga is the
    # one pointer pack whose selected theme name depends on that value, so the
    # incremental path must update the cursor key beside the accent key.
    if [ "${CURSORS:-}" = moga ] && [ -n "${ACCENT_EXPLICIT:-}" ]; then
        _apply_add cursor-theme
    fi
    # A bare pack name follows the accent (icon_base), so the key has to move
    # with it. Only ever to a colour already on disk, as on the full retune; the
    # icons action fetches nothing unless a pack was asked for.
    if [ -n "${ACCENT_EXPLICIT:-}" ] && [ "${WANT_ICONS:-1}" = 1 ]; then
        case "${ICONS:-colloid}" in
            colloid|reversal|hatter) _apply_add icons ;;
        esac
    fi
    # The tinted glass style is coloured with the accent (accent_hex in
    # steps-dconf.sh), so an accent edit has to re-tint the shell too.
    if [ -n "${ACCENT_EXPLICIT:-}" ] && [ "$(cat "$CONF_DIR/glass-style" 2>/dev/null || true)" = tinted ]; then
        _apply_add glass-style
    fi
}

# ---------------------------------------------------------- what is out of date

# Everything a full install does, as parts in the order it does them. A part is
# out of date when what it would install has changed since it last ran, or when
# what it installed is no longer there. An update and an Apply run only those,
# so this table is what stands between "only what changed" and "something new
# never got installed":
#
#   - A part's hash covers its entry functions and every function they reach,
#     read from `declare -f`, so a helper three calls down counts and a comment
#     does not. The library-level variables those functions name (pins, patch
#     names, extension lists) are hashed too.
#   - A repository file that no part claims and UPDATE_IGNORED does not name
#     lands in `other`, and a change there runs everything. A new file can make
#     an update slower, never incomplete.
#   - A part that failed has no new stamp, so the next run tries it again, and
#     verify_install runs after every update: a failed check runs everything.
#   - tools/check-incremental-apply.py asserts that every step in install.sh's
#     full sequence and every tracked file is accounted for here.
#
# Bump UPDATE_PLAN_SCHEMA to make every part out of date on the next update, for
# a release that needs one whatever this table thinks.
UPDATE_PLAN_SCHEMA=1
UPDATE_PARTS=(theme extensions icons cursors fonts look icon-sync gui update-check wallpapers flatpak retired adaptive enable gdm)
# What an Apply may run itself: local, unprivileged and quick. The same steps a
# retune has always run, which is what lets the window press it without warning
# anyone. The rest can fetch or want root, so an Apply only reports them.
UPDATE_LOCAL_PARTS=(look icon-sync gui update-check wallpapers retired adaptive)
declare -A UPDATE_PART_FUNCS=(
    [theme]="install_theme"
    [extensions]="install_extensions snapshot_preinstalled_exts"
    [icons]="install_icons apply_icon_theme"
    [cursors]="install_cursors"
    [fonts]="install_fonts"
    [look]="load_dconf install_css apply_gsettings remember_glass_mode"
    [icon-sync]="install_icon_sync"
    [gui]="install_gui"
    [update-check]="install_update_check"
    [wallpapers]="install_wallpapers"
    [flatpak]="flatpak_override"
    [retired]="remove_panel_blur_unit"
    [adaptive]="install_adaptive_performance"
    [enable]="enable_extensions"
    # The login screen is a copy of the theme and its sheets, so what changes
    # those changes it.
    [gdm]="install_gdm sync_gdm_monitors install_gdm_sync_unit install_theme install_css"
)
# fnmatch patterns, relative to the repository; * crosses directories. install.sh
# is the look's because its body is the flag resolver, whose answers every part
# of the look reads; the steps it calls are checked against this table.
declare -A UPDATE_PART_FILES=(
    [extensions]="patches/* extensions/*"
    [cursors]="tools/moga_cursor.py"
    [look]="install.sh css/* dconf/* tokens/* symbols/* bin/aura-glass-apply bin/aura-glass-operation bin/aura-glass-display-sync tools/aura_glass_operation.py tools/apply-*.py tools/rescale-transparency.py tools/token_manifest.py tools/moga_cursor.py"
    [icon-sync]="bin/aura-glass-icon-sync systemd/aura-glass-icon-sync.service"
    [gui]="gui/* bin/aura-glass-settings bin/aura-glass-preview bin/aura-glass-ext bin/aura-glass-open-once"
    [update-check]="bin/aura-glass-update bin/aura-glass-update-check systemd/aura-glass-update-check.*"
    [wallpapers]="wallpapers/*"
    # extensions/ too: a retune installs the helper from this step.
    [adaptive]="bin/aura-glass-adaptive tools/aura_glass_adaptive.py systemd/aura-glass-adaptive.service extensions/*"
    [gdm]="bin/aura-glass-gdm-sync systemd/aura-glass-gdm-sync.service css/* tokens/*"
)
# Installed by nothing, or read only through a part's functions: lib/ is hashed
# by function and variable, the deps by asking whether a command is missing.
UPDATE_IGNORED=".* docs/* tests/* screenshots/* packaging/* lib/* *.md llms.txt LICENSE *.code-workspace uninstall.sh tools/check-* tools/preview* tools/gpu-* tools/hooks/* tools/install-hooks.sh */__pycache__/*"
# Printing and prompting. Reached from every step, and a change to them changes
# no installed file.
UPDATE_PLUMBING="step info ok warn skip die run have confirm confirm_always remembering progress_note progress_wait progress_resume progress_event"

declare -A UPDATE_HASHES=()
UPDATE_STALE=()
UPDATE_FULL_REASON=""

# One sha256 per part, plus `other` for the files no part claims. Read from a
# clean bash that has only sourced the libraries, so a variable is hashed at its
# shipped value rather than what this run's flags made it. Printed as PART HASH.
update_part_hashes() {
    [ "${#UPDATE_HASHES[@]}" = 0 ] || return 0
    local part hash table=""
    for part in "${UPDATE_PARTS[@]}"; do
        table+="$part"$'\t'"${UPDATE_PART_FUNCS[$part]:-}"$'\t'"${UPDATE_PART_FILES[$part]:-}"$'\n'
    done
    while read -r part hash; do
        [ -n "$part" ] && UPDATE_HASHES["$part"]="$hash"
    done < <(
        env -i HOME="$HOME" PATH="$PATH" REPO_ROOT="$REPO_ROOT" bash -c '
            compgen -v | sed "s/^/base /"
            for f in lib/common.sh lib/distro.sh lib/steps.sh lib/steps-*.sh lib/progress.sh tokens/tokens.sh; do
                . "$REPO_ROOT/$f"
            done >/dev/null 2>&1
            echo "== vars"; declare -p
            echo "== funcs"; declare -f
        ' 2>/dev/null | REPO_ROOT="$REPO_ROOT" UPDATE_TABLE="$table" UPDATE_IGNORED="$UPDATE_IGNORED" \
            UPDATE_PLUMBING="$UPDATE_PLUMBING" UPDATE_SALT="$UPDATE_PLAN_SCHEMA" \
            UPDATE_GNOME="$(gnome_major 2>/dev/null || true)" \
            python3 -c '
import fnmatch, hashlib, os, re, sys
dump = sys.stdin.read()
head, _, rest = dump.partition("== vars\n")
var_text, _, func_text = rest.partition("== funcs\n")
base = {line[5:] for line in head.splitlines()}
variables = {}
for chunk in re.split(r"(?m)^(?=declare -\S+ )", var_text):
    found = re.match(r"declare -\S+ (\w+)", chunk)
    if found and found.group(1) not in base:
        # Paths under the home folder are the same paths wherever it is.
        variables[found.group(1)] = chunk.replace(os.environ["HOME"], "~")
functions = {m.group(1): m.group(0) for m in
             re.finditer(r"(?ms)^([\w-]+) \(\) *\n\{.*?^\}", func_text)}
plumbing = set(os.environ["UPDATE_PLUMBING"].split())
word = re.compile(r"[A-Za-z_][\w]*")
root = os.environ["REPO_ROOT"]
ignored = os.environ["UPDATE_IGNORED"].split()
paths = []
for folder, dirs, names in os.walk(root):
    dirs[:] = [d for d in dirs if d != ".git"]
    paths += [os.path.relpath(os.path.join(folder, n), root) for n in names]
paths.sort()
def content(path):
    with open(os.path.join(root, path), "rb") as stream:
        return hashlib.sha256(stream.read()).hexdigest()
claimed = set()
for line in os.environ["UPDATE_TABLE"].splitlines():
    part, entries, patterns = line.split("\t")
    digest = hashlib.sha256(os.environ["UPDATE_SALT"].encode())
    seen, todo = set(), entries.split()
    while todo:
        name = todo.pop()
        if name in seen or name not in functions:
            continue
        seen.add(name)
        todo += [t for t in word.findall(functions[name])
                 if t in functions and t not in plumbing]
    names = set()
    for name in sorted(seen):
        digest.update(functions[name].encode())
        names.update(word.findall(functions[name]))
    for name in sorted(names & set(variables)):
        digest.update(variables[name].encode())
    if part in ("theme", "extensions"):
        digest.update(os.environ["UPDATE_GNOME"].encode())
    for path in paths:
        if any(fnmatch.fnmatch(path, p) for p in patterns.split()):
            claimed.add(path)
            digest.update((path + content(path)).encode())
    print(part, digest.hexdigest())
other = hashlib.sha256(os.environ["UPDATE_SALT"].encode())
unclaimed = []
for path in paths:
    if path not in claimed and not any(fnmatch.fnmatch(path, p) for p in ignored):
        unclaimed.append(path)
        other.update((path + content(path)).encode())
print("other", other.hexdigest())
if os.environ.get("UPDATE_LIST_UNCLAIMED"):
    print("\n".join(unclaimed), file=sys.stderr)
'
    )
    [ -n "${UPDATE_HASHES[other]:-}" ] || die "could not work out which parts are out of date"
}

update_stamp_read() {   # PART
    sed -n "s/^$1 //p" "$CONF_DIR/installed-parts" 2>/dev/null | head -n 1
}

# Written only once the part has run, so a run that died leaves it out of date.
update_stamp() {   # PART [HASH-OF: another name in UPDATE_HASHES]
    remembering || return 0
    update_part_hashes
    local tmp="$CONF_DIR/installed-parts.tmp"
    mkdir -p "$CONF_DIR"
    { grep -v "^$1 " "$CONF_DIR/installed-parts" 2>/dev/null || true
      printf '%s %s\n' "$1" "${UPDATE_HASHES[${2:-$1}]}"; } > "$tmp"
    mv -f "$tmp" "$CONF_DIR/installed-parts"
    # What the Apply path compared before there were parts.
    rm -f "$CONF_DIR/apply-source-fingerprint"
}

# The same list enable_extensions turns on and verify_install checks.
update_wanted_extensions() {
    printf '%s\n' "${EXT_CORE[@]}" "$AURA_EXT_UUID" "$BMS_UUID"
    [ "${WANT_OSD:-1}" != 1 ] || echo custom-osd@neuromorph
    if [ "${WANT_EXTRAS:-0}" = 1 ] && [ "${#EXT_EXTRA[@]}" -gt 0 ]; then
        printf '%s\n' "${EXT_EXTRA[@]}"
    fi
}

# Whether what the part installs is still on the machine: a deleted extension,
# an uninstall --extensions or a pack the resolver now wants all land here, with
# no source having changed.
update_part_present() {   # PART
    local u theme
    # theme holds the icon, cursor or font name the part is asked to provide.
    case "$1" in
        theme) [ -f "$HOME/.themes/$THEME_NAME/gnome-shell/gnome-shell.css" ] ;;
        extensions)
            while IFS= read -r u; do
                [ -d "$EXT_DIR/$u" ] || [ -d "/usr/share/gnome-shell/extensions/$u" ] || return 1
            done < <(update_wanted_extensions)
            ;;
        icons)
            [ "${WANT_ICONS:-1}" = 1 ] || return 0
            [ -n "$(icon_variant "$(icon_base)" Dark 2>/dev/null || true)" ]
            ;;
        cursors)
            [ "${WANT_CURSORS:-1}" = 1 ] || return 0
            theme="$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")"
            [ -n "$theme" ] && _verify_icon_dir "$theme" cursors
            ;;
        fonts)
            theme="$(font_family)"
            [ -z "$theme" ] || font_present "$theme"
            ;;
        look)
            grep -qF '/* >>> aura-glass BEGIN <<< */' "$HOME/.themes/$THEME_NAME/gnome-shell/gnome-shell.css" 2>/dev/null \
                && grep -qF '/* >>> aura-glass BEGIN <<< */' "$HOME/.config/gtk-4.0/gtk.css" 2>/dev/null \
                && grep -qF '/* >>> aura-glass BEGIN <<< */' "$HOME/.config/gtk-3.0/gtk.css" 2>/dev/null
            ;;
        gui)
            [ "${WANT_GUI:-1}" = 1 ] || return 0
            gui_toolkit_present || return 0
            [ -x "$HOME/.local/bin/aura-glass-settings" ]
            ;;
        update-check)
            [ -d "$REPO_ROOT/.git" ] || return 0
            [ -x "$HOME/.local/bin/aura-glass-update" ]
            ;;
        adaptive) [ -x "$HOME/.local/bin/aura-glass-adaptive" ] ;;
    esac
}

update_part_wanted() {   # PART
    case "$1" in
        gdm) [ "${WANT_GDM:-0}" = 1 ] || [ "${WANT_GDM_MONITORS:-0}" = 1 ] ;;
    esac
}

update_part_stale() {   # PART
    update_part_wanted "$1" || return 1
    [ "$(update_stamp_read "$1")" != "${UPDATE_HASHES[$1]}" ] && return 0
    ! update_part_present "$1"
}

_update_stale_add() {
    local value
    for value in "${UPDATE_STALE[@]}"; do [ "$value" = "$1" ] && return 0; done
    update_part_wanted "$1" && UPDATE_STALE+=("$1")
    return 0
}

# Fills UPDATE_STALE, or says in UPDATE_FULL_REASON why only everything will do.
# Apply passes "apply": it never installs the theme or the extensions, so what
# following them would need is not its to run.
select_update_parts() {
    UPDATE_STALE=()
    UPDATE_FULL_REASON=""
    update_part_hashes
    if [ ! -s "$CONF_DIR/installed-parts" ]; then
        UPDATE_FULL_REASON="nothing is recorded about what is installed"
    elif [ "$(update_stamp_read other)" != "${UPDATE_HASHES[other]}" ]; then
        UPDATE_FULL_REASON="a file changed that no part claims"
    fi
    local part
    for part in "${UPDATE_PARTS[@]}"; do
        update_part_stale "$part" && _update_stale_add "$part"
    done
    [ "${1:-}" != apply ] || return 0
    # Installing the theme puts upstream's stylesheets back, without the block
    # the look splices in, and the login screen is a copy of them. Extensions
    # that have just arrived have to be switched on.
    if update_is_stale theme; then _update_stale_add look; _update_stale_add gdm; fi
    if update_is_stale extensions; then _update_stale_add enable; fi
    return 0
}

update_is_stale() {   # PART
    local value
    for value in "${UPDATE_STALE[@]}"; do [ "$value" = "$1" ] && return 0; done
    return 1
}

# The flags that do not stop an update being only what changed.
update_flags_are_plain() {
    local flag
    for flag in "${TYPED_FLAGS[@]}"; do
        case "$flag" in
            --update|--gui|--yes|-y|--dry-run|-n|--plan-json|--progress-window) ;;
            *) UPDATE_FULL_REASON="$flag was given"; return 1 ;;
        esac
    done
}

update_needs_root() {
    [ -n "$(missing_cmds)" ] || update_is_stale gdm
}

# Fills APPLY_ACTIONS and its reason as select_apply_actions does, with the
# parts that are out of date beside them: APPLY_PARTS for the ones this Apply
# runs and APPLY_PENDING for the ones only an update can.
resolve_apply_plan() {
    APPLY_PARTS=()
    APPLY_PENDING=()
    select_apply_actions
    [ "${APPLY_ACTIONS[0]}" != adaptive-blur ] || return 0
    select_update_parts apply
    if [ "${APPLY_ACTIONS[0]}" != full ] \
       && { [ ! -s "$CONF_DIR/installed-parts" ] \
            || [ "$(update_stamp_read other-local)" != "${UPDATE_HASHES[other]}" ]; }; then
        APPLY_ACTIONS=(full)
        APPLY_FALLBACK_REASON="installed source fingerprint is absent or changed"
    fi
    local part local_part is_local
    for part in "${UPDATE_STALE[@]}"; do
        is_local=0
        for local_part in "${UPDATE_LOCAL_PARTS[@]}"; do
            [ "$part" = "$local_part" ] && is_local=1
        done
        if [ "$is_local" = 1 ]; then
            APPLY_PARTS+=("$part")
        elif [ -n "$(update_stamp_read "$part")" ]; then
            # No stamp is an install from before there were parts rather than a
            # change, and nothing to warn about.
            APPLY_PENDING+=("$part")
        fi
    done
    return 0
}

# Stated once, because the full sequence, an update and an Apply all run these.
run_update_part() {   # PART
    case "$1" in
        theme) install_theme ;;
        extensions) install_extensions ;;
        icons) if [ "${WANT_ICONS:-1}" = 1 ]; then install_icons; fi ;;
        cursors) if [ "${WANT_CURSORS:-1}" = 1 ]; then install_cursors; fi ;;
        fonts) install_fonts ;;
        look)
            load_dconf
            install_css
            apply_gsettings
            remember_glass_mode
            ;;
        icon-sync) install_icon_sync ;;
        gui) install_gui ;;
        update-check) install_update_check ;;
        wallpapers) install_wallpapers ;;
        flatpak) flatpak_override ;;
        retired) remove_panel_blur_unit ;;
        adaptive) install_adaptive_performance ;;
        enable) enable_extensions ;;
        gdm)
            if [ "${WANT_GDM_MONITORS:-0}" = 1 ]; then
                sync_gdm_monitors
                [ "${WANT_GDM:-0}" = 1 ] || install_gdm_sync_unit
            fi
            if [ "${WANT_GDM:-0}" = 1 ]; then
                install_gdm
            fi
            ;;
        *) die "no such part: $1" ;;
    esac
    update_stamp "$1"
}

# run_update_group PROGRESS-ID PART... — one line of the window's checklist.
_update_group() {
    local id="$1" part any=0
    shift
    for part in "$@"; do update_is_stale "$part" && any=1; done
    if [ "$any" = 0 ]; then
        progress_end
        progress_skip "$id" "already up to date"
        return 0
    fi
    progress_start "$id"
    for part in "$@"; do
        if update_is_stale "$part"; then run_update_part "$part"; fi
    done
}

# Extensions load only into a new session, so the logout is owed only if one of
# their files actually moved: the part can run and find everything current.
_extension_tree_state() {
    find "$EXT_DIR" -type f -printf '%s %T@ %p\n' 2>/dev/null | sort | sha256sum
}

# Only what is out of date, in the full sequence's order. Exits on success. A
# failed check returns instead, with UPDATE_SELECTIVE cleared, and the full
# sequence install.sh has next puts in whatever this missed.
run_selective_update() {
    info "running only what changed: ${UPDATE_STALE[*]:-nothing}"
    snapshot_preinstalled_exts
    local before
    before="$(_extension_tree_state)"
    if [ -n "$(missing_cmds)" ]; then
        progress_start deps
        step "Checking dependencies"
        install_deps || die "dependencies are missing — re-run once they are installed, or pass --no-deps to try anyway"
    else
        progress_end
        progress_skip deps "already up to date"
    fi
    _update_group theme theme
    _update_group extensions extensions
    _update_group icons icons
    _update_group cursors cursors
    _update_group fonts fonts
    _update_group look look
    _update_group services icon-sync gui update-check wallpapers flatpak retired adaptive
    _update_group enable enable
    _update_group gdm gdm
    progress_start verify
    verify_install
    progress_end
    if [ "${VERIFY_FAILS:-0}" != 0 ]; then
        warn "a check failed after the partial update — running the complete install"
        UPDATE_SELECTIVE=0
        return 0
    fi
    update_stamp other
    update_stamp other-local other
    if [ "$before" != "$(_extension_tree_state)" ]; then
        finish
    else
        step "Done"
        info "Everything is already live, so there is no need to log out."
        progress_finish 0 0
    fi
    exit 0
}
