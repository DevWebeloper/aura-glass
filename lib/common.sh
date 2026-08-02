# shellcheck shell=bash
# tahoe-glass — output, prompting and small shared helpers.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_DIM=$'\033[2m'; C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'
    C_YEL=$'\033[0;33m'; C_BLU=$'\033[0;34m'; C_BLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_DIM=''; C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_BLD=''; C_OFF=''
fi

step()  { printf '\n%s==>%s %s%s%s\n' "$C_BLU" "$C_OFF" "$C_BLD" "$*" "$C_OFF"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s✓%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn()  { printf '    %s!%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
skip()  { printf '    %s·%s %s%s%s\n' "$C_DIM" "$C_OFF" "$C_DIM" "$*" "$C_OFF"; }
die()   { printf '\n%serror:%s %s\n\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

# run CMD... — echoes in --dry-run instead of executing.
run() {
    if [ "${DRY_RUN:-0}" = 1 ]; then
        printf '    %sdry-run:%s %s\n' "$C_DIM" "$C_OFF" "$*"
        return 0
    fi
    "$@"
}

# confirm "question" [default_yes]
# --yes answers yes; a non-interactive stdin answers with the default.
confirm() {
    local q="$1" def="${2:-1}" ans hint
    [ "${ASSUME_YES:-0}" = 1 ] && return 0
    if [ "$def" = 1 ]; then hint="[Y/n]"; else hint="[y/N]"; fi
    if [ ! -t 0 ]; then
        [ "$def" = 1 ] && return 0 || return 1
    fi
    printf '    %s %s ' "$q" "$hint" >&2
    read -r ans || ans=''
    case "${ans,,}" in
        y|yes) return 0 ;;
        n|no)  return 1 ;;
        '')    [ "$def" = 1 ] && return 0 || return 1 ;;
        *)     [ "$def" = 1 ] && return 0 || return 1 ;;
    esac
}

# confirm_always "question" — like confirm, but --yes does not answer it and a
# non-interactive run declines instead of defaulting. For the one step that
# installs a package outside $HOME: saying yes to a theme installer is not the
# same as saying yes to that, and neither is piping this script into bash.
confirm_always() {
    local q="$1" ans
    if [ ! -t 0 ]; then
        warn "not an interactive terminal — declining. Re-run in a terminal to accept."
        return 1
    fi
    printf '    %s [y/N] ' "$q" >&2
    read -r ans || ans=''
    case "${ans,,}" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

have() { command -v "$1" >/dev/null 2>&1; }

# Clone at a pinned ref, or fetch that ref into an existing clone. Pinning
# matters here: both upstreams are moving targets, and a theme that changes
# under the tweaks is how you end up with half-applied CSS.
clone_pinned() {
    local url="$1" ref="$2" dest="$3"
    if [ -d "$dest/.git" ]; then
        run git -C "$dest" fetch --quiet --depth 50 origin "$ref" 2>/dev/null \
            || run git -C "$dest" fetch --quiet origin
    else
        run rm -rf "$dest"
        run git clone --quiet "$url" "$dest"
    fi
    run git -C "$dest" checkout --quiet --detach "$ref"
}

# Back up a file once, keeping the first (pre-tahoe-glass) copy forever.
# The third argument names the backup, because several of the files we touch
# are called gtk.css and would otherwise overwrite each other.
backup_once() {
    local f="$1" dir="$2" name="${3:-}"
    [ -f "$f" ] || return 0
    [ -n "$name" ] || name="$(basename "$f")"
    local dst="$dir/$name.orig"
    [ -e "$dst" ] && return 0
    run mkdir -p "$dir"
    run cp -a "$f" "$dst"
}

gnome_major() {
    local v
    v="$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1)" || return 1
    printf '%s' "$v"
}
