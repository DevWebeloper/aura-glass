# shellcheck shell=bash
# aura-glass — telling a window how a full install is going.
#
# The terminal stays where the install happens. sudo and the
# retired-extension questions are asked there, and every line the run
# prints is still printed there. What a window adds is what a long terminal
# scroll does not give: how far along the run is, which part is running,
# whether the terminal is waiting for an answer, and at the end a checklist of
# what landed, with the reason next to anything that did not and a way to log
# out. That window is gui/aura_glass_install_progress.py.
#
# It is on for a run the setup wizard started (FROM_GUI_WIZARD), for
# --progress-window, which is what the settings window adds to the full runs it
# opens in a terminal, and for an update: the settings window opens the window
# itself in update mode and bin/aura-glass-update passes its run directory down
# in AURA_GLASS_PROGRESS_DIR, so this install adds its steps to that window
# instead of opening a second one. Everything else — a scripted install, --settings-only,
# --deps-only — never calls progress_begin, and every function here is then a
# no-op.
#
# $PROGRESS_DIR holds two files, both only appended to:
#
#   events  one JSON object per line, the window's only input:
#             begin   pid, log, repo, dry   (aura-glass-update's, in an update)
#             plan    id, title          one per step, in order, before any start
#             start   id, offset         offset = log size when the step began
#             note    id, level, text    a warn or error line, as printed
#             end     id, status, offset ok | warn | skip | fail
#             wait    text               the terminal is asking something
#             resume
#             verify-begin
#             check   group, title, status, why, fix
#             finish  status, rc         ok | warn | fail
#   log     a copy of everything the terminal shows, so "why did this fail" can
#           show the part of the run that failed
#
# The window only reads, and is launched detached. If it cannot start, or is
# closed, the install carries on exactly as it would without it.

PROGRESS_DIR=""
PROGRESS_STEP=""
PROGRESS_FINISHED=0
PROGRESS_OKS=0
PROGRESS_WARNS=0
PROGRESS_SKIPS=0
VERIFY_FAILS=0

# _progress_json VAR STRING — STRING as a JSON string literal, into VAR.
_progress_json() {
    local s="$2"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/}"
    s="${s//$'\033'/}"
    printf -v "$1" '"%s"' "$s"
}

# progress_event TYPE [KEY VALUE]... — one line of events. Values are strings.
progress_event() {
    [ -n "$PROGRESS_DIR" ] || return 0
    local line field
    _progress_json field "$1"; line="{\"t\":$field"; shift
    while [ "$#" -ge 2 ]; do
        _progress_json field "$1"; line+=",$field:"
        _progress_json field "$2"; line+="$field"
        shift 2
    done
    printf '%s}\n' "$line" >> "$PROGRESS_DIR/events" 2>/dev/null || true
}

_progress_offset() {
    stat -c %s "$PROGRESS_DIR/log" 2>/dev/null || echo 0
}

# Replaces lib/common.sh's no-op. ok/warn/skip/die call it with what they print,
# which is how a step learns whether it went cleanly.
progress_note() {
    [ -n "$PROGRESS_DIR" ] || return 0
    case "$1" in
        ok)    PROGRESS_OKS=$((PROGRESS_OKS + 1)) ;;
        skip)  PROGRESS_SKIPS=$((PROGRESS_SKIPS + 1)) ;;
        warn)  PROGRESS_WARNS=$((PROGRESS_WARNS + 1))
               progress_event note id "$PROGRESS_STEP" level warn text "$2" ;;
        error) progress_event note id "$PROGRESS_STEP" level error text "$2" ;;
    esac
}

progress_wait()   { progress_event wait text "$1"; }
progress_resume() { progress_event resume; }

# The window's first sign of life is a file holding its pid; prompt_logout
# leaves the logout to it while it is open.
progress_window_open() {
    [ -n "$PROGRESS_DIR" ] && [ -r "$PROGRESS_DIR/window" ] || return 1
    local pid
    pid="$(cat "$PROGRESS_DIR/window" 2>/dev/null || true)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# progress_begin — start recording this run and open the window on it.
#
# The record goes to $CONF_DIR/last-install, replaced each run, so the log of
# the last install is still there to read after the window is closed. A dry
# run or a preview writes nothing under $CONF_DIR, so it gets a temp dir.
progress_begin() {
    # An update's window is already open and already reading this directory,
    # and aura-glass-update already sends this script's output to its log and
    # owns the begin event (its pid is the one the window watches). So: no tee,
    # no window, no begin; only this run's steps and its finish.
    if [ -n "${AURA_GLASS_PROGRESS_DIR:-}" ] && [ -d "$AURA_GLASS_PROGRESS_DIR" ]; then
        PROGRESS_DIR="$AURA_GLASS_PROGRESS_DIR"
        add_exit_trap 'progress_exit "$?"'
        return 0
    fi
    [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || return 0
    gui_toolkit_present || return 0
    local window="$REPO_ROOT/gui/aura_glass_install_progress.py"
    [ -r "$window" ] || return 0

    local dir
    if remembering; then
        dir="$CONF_DIR/last-install"
        rm -rf "$dir"
        mkdir -p "$dir"
    else
        dir="$(mktemp -d)"
    fi
    : > "$dir/events"
    : > "$dir/log"
    PROGRESS_DIR="$dir"

    # Both streams through tee, so the log has warnings and errors in the
    # order the terminal showed them. stdin is left alone: every question is
    # still read from the terminal, and sudo asks on /dev/tty either way.
    exec > >(tee -a "$PROGRESS_DIR/log") 2>&1

    progress_event begin pid "$$" log "$PROGRESS_DIR/log" repo "$REPO_ROOT" dry "${DRY_RUN:-0}"
    add_exit_trap 'progress_exit "$?"'

    setsid -f python3 "$window" --dir "$PROGRESS_DIR" </dev/null >/dev/null 2>&1 \
        || warn "the progress window did not open — everything is still shown here"
}

# progress_plan ID TITLE [ID TITLE]... — the checklist, before anything runs.
progress_plan() {
    while [ "$#" -ge 2 ]; do
        progress_event plan id "$1" title "$2"
        shift 2
    done
}

# progress_start ID — the steps after this belong to ID, until progress_end.
# A step that fails stops the run through die or set -e, so there is no
# progress_end for it; progress_exit closes it as failed.
progress_start() {
    [ -n "$PROGRESS_DIR" ] || return 0
    [ -z "$PROGRESS_STEP" ] || progress_end
    PROGRESS_STEP="$1"
    PROGRESS_OKS=0; PROGRESS_WARNS=0; PROGRESS_SKIPS=0
    progress_event start id "$1" offset "$(_progress_offset)"
}

progress_end() {
    [ -n "$PROGRESS_DIR" ] && [ -n "$PROGRESS_STEP" ] || return 0
    local status=ok
    if [ "$PROGRESS_WARNS" -gt 0 ]; then
        status=warn
    elif [ "$PROGRESS_OKS" = 0 ] && [ "$PROGRESS_SKIPS" -gt 0 ]; then
        status=skip
    fi
    progress_event end id "$PROGRESS_STEP" status "$status" offset "$(_progress_offset)"
    PROGRESS_STEP=""
}

# progress_skip ID WHY — a planned step this run does not do at all.
progress_skip() {
    [ -n "$PROGRESS_DIR" ] || return 0
    progress_event start id "$1" offset "$(_progress_offset)"
    progress_event note id "$1" level info text "$2"
    progress_event end id "$1" status skip offset "$(_progress_offset)"
}

# progress_finish — the run is over and the window can show its checklist.
# Called by finish() before the logout question, and by the exit trap for a
# run that stopped early.
progress_finish() {
    [ -n "$PROGRESS_DIR" ] && [ "$PROGRESS_FINISHED" = 0 ] || return 0
    PROGRESS_FINISHED=1
    local rc="${1:-0}" status=ok
    if [ "$rc" != 0 ]; then
        status=fail
    elif grep -q '"t":"end".*"status":"warn"\|"t":"check".*"status":"\(warn\|fail\)"' "$PROGRESS_DIR/events" 2>/dev/null; then
        status=warn
    fi
    progress_event finish status "$status" rc "$rc"
}

progress_exit() {
    local rc="$1"
    [ -n "$PROGRESS_DIR" ] || return 0
    if [ -n "$PROGRESS_STEP" ]; then
        if [ "$rc" != 0 ]; then
            progress_event end id "$PROGRESS_STEP" status fail offset "$(_progress_offset)"
            PROGRESS_STEP=""
        else
            progress_end
        fi
    fi
    progress_finish "$rc"
}

# ---------------------------------------------------------------------------
# verify_install — the checklist's second half: what is actually on disk and in
# gsettings now, rather than what each step said it did. Reads the same
# resolved WANT_* variables the run used, so it checks for what this run (or,
# under --verify, a flagless run) would install, and nothing it was told to
# leave out. Each result is a line in the terminal and a check event; a failed
# one carries why it matters and what fixes it.
#
# Extensions are checked as installed and listed as enabled. Whether the shell
# has loaded one can only be known after the next login.
# ---------------------------------------------------------------------------

# verify_check STATUS GROUP TITLE [WHY] [FIX]
verify_check() {
    progress_event check status "$1" group "$2" title "$3" why "${4:-}" fix "${5:-}"
    case "$1" in
        ok)   printf '    %s✓%s %s: %s\n' "$C_GRN" "$C_OFF" "$2" "$3" ;;
        warn) printf '    %s!%s %s: %s — %s\n' "$C_YEL" "$C_OFF" "$2" "$3" "${4:-}" ;;
        *)    VERIFY_FAILS=$((VERIFY_FAILS + 1))
              printf '    %s✗%s %s: %s — %s\n' "$C_RED" "$C_OFF" "$2" "$3" "${4:-}" ;;
    esac
    [ -z "${5:-}" ] || [ "$1" = ok ] || printf '      fix: %s\n' "$5"
}

_verify_icon_dir() {   # NAME [SUBDIR] — whether an icon or cursor theme is installed
    local d
    for d in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons; do
        [ -d "$d/$1${2:+/$2}" ] && return 0
    done
    return 1
}

verify_install() {
    step "Checking the result"
    progress_event verify-begin
    VERIFY_FAILS=0
    if [ "${DRY_RUN:-0}" = 1 ]; then
        skip "dry run — nothing was installed to check"
        return 0
    fi

    local begin='/* >>> aura-glass BEGIN <<< */' f name
    local -a sheets=(
        "Shell stylesheet|$HOME/.themes/$THEME_NAME/gnome-shell/gnome-shell.css"
        "GTK 4 stylesheet|$HOME/.config/gtk-4.0/gtk.css"
        "GTK 3 stylesheet|$HOME/.config/gtk-3.0/gtk.css"
    )
    for f in "${sheets[@]}"; do
        name="${f%%|*}"; f="${f#*|}"
        if grep -qF "$begin" "$f" 2>/dev/null; then
            verify_check ok Theme "$name"
        else
            verify_check fail Theme "$name" \
                "$f has no Aura Glass block, so that part of the desktop keeps its old look" \
                "aura-glass-apply"
        fi
    done

    if [ "$(dconf read /org/gnome/shell/extensions/user-theme/name 2>/dev/null)" = "'$THEME_NAME'" ]; then
        verify_check ok Theme "Shell theme selected"
    else
        verify_check fail Theme "Shell theme selected" \
            "User Themes is not set to $THEME_NAME, so the top bar and menus keep GNOME's look" \
            "dconf write /org/gnome/shell/extensions/user-theme/name \"'$THEME_NAME'\""
    fi

    # The same list enable_extensions turns on.
    local -a want=("${EXT_CORE[@]}" "$AURA_EXT_UUID" "$BMS_UUID")
    [ "${WANT_OSD:-1}" = 1 ] && want+=(custom-osd@neuromorph)
    if [ "${WANT_EXTRAS:-0}" = 1 ] && [ "${#EXT_EXTRA[@]}" -gt 0 ]; then
        want+=("${EXT_EXTRA[@]}")
    fi
    local u title state
    for u in "${want[@]}"; do
        title="$(ext_description "$u" 2>/dev/null || true)"
        title="${title%% — *}"
        title="${title:-$u}"
        if [ ! -d "$EXT_DIR/$u" ] && [ ! -d "/usr/share/gnome-shell/extensions/$u" ]; then
            verify_check fail Extensions "$title" \
                "$u is not installed — its download or build failed (see the Shell extensions step)" \
                "./install.sh"
            continue
        fi
        state="$(gnome-extensions info "$u" 2>/dev/null | sed -n 's/^ *State: *//p' | head -1)"
        case "${state^^}" in
            ERROR|OUT\ OF\ DATE|OUT_OF_DATE)
                verify_check fail Extensions "$title" \
                    "the running shell reports $u as ${state,,}" \
                    "journalctl --user -b -g '$u'"
                continue ;;
        esac
        if is_extension_enabled "$u"; then
            verify_check ok Extensions "$title"
        elif ext_never_auto_enabled "$u"; then
            verify_check ok Extensions "$title (installed, off on purpose)"
        else
            verify_check warn Extensions "$title" \
                "$u is installed but switched off — on purpose if you turned it off yourself" \
                "gnome-extensions enable $u"
        fi
    done

    local theme
    if [ "${WANT_ICONS:-0}" = 1 ]; then
        theme="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")"
        if [ -n "$theme" ] && _verify_icon_dir "$theme"; then
            verify_check ok Look "Icons ($theme)"
        else
            verify_check fail Look "Icons" \
                "the icon theme '$theme' is selected but not installed" \
                "./install.sh --icons ${ICONS:-colloid}"
        fi
    fi
    if [ "${WANT_CURSORS:-0}" = 1 ]; then
        theme="$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")"
        if [ -n "$theme" ] && _verify_icon_dir "$theme" cursors; then
            verify_check ok Look "Pointer ($theme)"
        else
            verify_check fail Look "Pointer" \
                "the pointer theme '$theme' is selected but not installed" \
                "./install.sh --cursors ${CURSORS:-adwaita}"
        fi
    fi

    if [ "${WANT_GUI:-1}" = 1 ]; then
        if [ -x "$HOME/.local/bin/aura-glass-settings" ]; then
            verify_check ok Apps "Aura Glass settings app"
        else
            verify_check fail Apps "Aura Glass settings app" \
                "~/.local/bin/aura-glass-settings is missing" \
                "./install.sh --settings-only"
        fi
    fi

    if [ "${WANT_GDM:-0}" = 1 ] || [ -r "$CONF_DIR/gdm-installed" ]; then
        if [ -r "$CONF_DIR/gdm-installed" ]; then
            verify_check ok "Login screen" "Login screen themed"
        else
            verify_check fail "Login screen" "Login screen themed" \
                "the GDM theme was not installed (see the Login screen step)" \
                "./install.sh --gdm"
        fi
    fi

    if [ "$VERIFY_FAILS" = 0 ]; then
        ok "everything checked is in place"
    else
        warn "$VERIFY_FAILS check(s) failed — see above"
    fi
}
