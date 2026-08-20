# shellcheck shell=bash
# aura-glass — output, prompting and small shared helpers.

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

# prompt_logout — asks whether to log out now (default No).
# If confirmed, logs out of the current desktop session.
prompt_logout() {
    if ! confirm_always "Log out now?"; then
        return 0
    fi
    info "Logging out..."
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: gnome-session-quit --logout --no-prompt"
        return 0
    fi
    if have gnome-session-quit; then
        gnome-session-quit --logout --no-prompt
    elif have loginctl; then
        loginctl terminate-session "${XDG_SESSION_ID:-self}" 2>/dev/null \
            || loginctl terminate-user "$USER"
    fi
}

# patch_stamp NAME PATCHFILE — true when the installed build already came from
# this exact patch. A patched extension is built once and then skipped forever
# on the strength of the directory existing, so editing a patch used to change
# nothing on a machine that had already installed: the old build stayed, and
# the only symptom was code on disk that no longer matched the repo.
patch_stamp_current() {
    local name="$1" patch="$2"
    [ -r "$CONF_DIR/$name" ] || return 1
    [ "$(cat "$CONF_DIR/$name" 2>/dev/null)" = "$(sha256sum "$patch" | cut -d' ' -f1)" ]
}
patch_stamp_write() {
    local name="$1" patch="$2"
    [ "${DRY_RUN:-0}" = 1 ] && return 0
    mkdir -p "$CONF_DIR"
    sha256sum "$patch" | cut -d' ' -f1 > "$CONF_DIR/$name"
}

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
    # Steps that patch this checkout (Open Bar, Custom OSD) leave modified
    # tracked files behind. checkout is a no-op when already sitting on
    # $ref, so a second run applies the same patch to the first run's
    # already-patched files and every hunk fails. Force pristine every time.
    run git -C "$dest" reset --quiet --hard "$ref"
    run git -C "$dest" clean --quiet -fdx
}

# clone_pinned's shape for a repository too big to clone whole, taking the
# directories wanted as trailing arguments. Hatter is the reason it exists: its
# history is over a gigabyte and a full checkout is 328M, of which GNOME reads
# about a third — the KDE flavours and the artwork are dead weight on a GNOME
# machine.
#
# Shallow and sparse rather than one or the other: --depth 1 on the pinned SHA
# leaves the history behind, blob:none leaves the objects outside the cone
# behind, and the cone itself leaves the files behind. GitHub serves a bare SHA
# to fetch, which is what makes pinning still possible without tags.
clone_pinned_sparse() {
    local url="$1" ref="$2" dest="$3"; shift 3
    if [ ! -d "$dest/.git" ]; then
        run rm -rf "$dest"
        run mkdir -p "$dest"
        run git -C "$dest" init --quiet
        run git -C "$dest" remote add origin "$url"
    fi
    run git -C "$dest" sparse-checkout init --cone
    run git -C "$dest" sparse-checkout set "$@"
    run git -C "$dest" fetch --quiet --depth 1 --filter=blob:none origin "$ref" \
        || die "could not fetch $ref from $url"
    run git -C "$dest" checkout --quiet --detach FETCH_HEAD
    run git -C "$dest" reset --quiet --hard FETCH_HEAD
    # The cone is narrowed as well as widened between runs — a different icon
    # colour asks for a different directory — and the files outside the new cone
    # stay checked out until something removes them.
    run git -C "$dest" clean --quiet -fdx
}

# A pinned release tarball, verified before it is unpacked. The counterpart of
# clone_pinned for an upstream that publishes builds rather than a buildable
# tree: there is no commit to pin, so the hash is the pin, and a mismatch is
# fatal rather than a warning.
#
# Unpacks into $dest, which is emptied first so a changed pin cannot leave the
# previous release's files sitting alongside the new one.
fetch_tarball_pinned() {
    local url="$1" sha="$2" dest="$3"
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: download $url and unpack it into $dest"
        return 0
    fi
    local tmp; tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/archive" "$url" \
        || { rm -rf "$tmp"; die "could not download $url"; }
    local got; got="$(sha256sum "$tmp/archive" | cut -d' ' -f1)"
    if [ "$got" != "$sha" ]; then
        rm -rf "$tmp"
        die "$url does not match its pinned checksum (expected $sha, got $got)"
    fi
    rm -rf "$dest"
    mkdir -p "$dest"
    tar -xf "$tmp/archive" -C "$dest" \
        || { rm -rf "$tmp"; die "could not unpack $url"; }
    rm -rf "$tmp"
}

# The same thing for an upstream that ships a zip, which is what the two font
# vendors do. Two differences from the tarball above, both forced by what is
# on the other end.
#
# unzip rather than tar: the archives are built on macOS and carry __MACOSX
# resource forks, which -x drops so they never reach a font directory.
#
# And the mismatch is answerable. Xiaomi serves MiSans from a bare filename
# with no version in it, so the URL moves under the pin every time they cut a
# release; dying there would break every install the day that happens, for an
# archive whose contents are fonts. Pass "warn" for those and the checksum
# becomes a notice rather than a wall. Anything served from a versioned URL —
# a GitHub release asset — keeps the default, which is die.
fetch_zip_pinned() {
    local url="$1" sha="$2" dest="$3" on_mismatch="${4:-die}"
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: download $url and unpack it into $dest"
        return 0
    fi
    local tmp; tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/archive.zip" "$url" \
        || { rm -rf "$tmp"; die "could not download $url"; }
    local got; got="$(sha256sum "$tmp/archive.zip" | cut -d' ' -f1)"
    if [ "$got" != "$sha" ]; then
        if [ "$on_mismatch" = warn ]; then
            warn "$url no longer matches its pinned checksum — upstream has published a new build (expected $sha, got $got)"
        else
            rm -rf "$tmp"
            die "$url does not match its pinned checksum (expected $sha, got $got)"
        fi
    fi
    rm -rf "$dest"
    mkdir -p "$dest"
    unzip -qo "$tmp/archive.zip" -d "$dest" -x '__MACOSX/*' '*/.DS_Store' \
        || { rm -rf "$tmp"; die "could not unpack $url"; }
    rm -rf "$tmp"
}

# Back up a file once, keeping the first (pre-aura-glass) copy forever.
# The third argument names the backup, because several of the files we touch
# are called gtk.css and would otherwise overwrite each other.
backup_once() {
    local f="$1" dir="$2" name="${3:-}"
    [ -n "$name" ] || name="$(basename "$f")"
    local dst="$dir/$name.orig"
    # Never overwrite the first-run record, whichever kind it is.
    if [ -e "$dst" ] || [ -e "$dir/$name.absent" ]; then
        return 0
    fi
    run mkdir -p "$dir"
    if [ -f "$f" ]; then
        run cp -a "$f" "$dst"
    elif [ "${DRY_RUN:-0}" = 1 ]; then
        printf '    %sdry-run:%s note that %s did not exist\n' "$C_DIM" "$C_OFF" "$f"
    else
        # Nothing was here before us. Recorded, because a file we create
        # has no .orig to restore from — and the uninstaller only strips
        # its own marked block, so without this note the theme's own 41K
        # libadwaita override stays in ~/.config/gtk-4.0 forever and every
        # GTK4 app keeps the theme after a full uninstall.
        : > "$dir/$name.absent"
    fi
}

# The same idea as backup_once, for a gsettings key rather than a file: record
# what was there the first time and never touch the record again.
#
# It exists so that --icons original and --cursors original have something to
# mean. "Keep current" is a choice not to touch whatever is set right now, which
# after one install is this theme's own pack — there was no way back to what the
# machine looked like before, because nothing had written it down.
#
# The honest limit, and the row in the window says it: this can only capture the
# first time *this code* runs. On a machine that already has aura-glass on it,
# the first run after upgrading records the pack aura-glass installed, and
# "original" means that rather than something older. Nothing can recover a state
# nobody recorded.
gsettings_backup_once() {
    local schema="$1" key="$2" name="$3"
    local dst="$BACKUP_DIR/$name.gsettings-orig"
    [ -e "$dst" ] && return 0

    local current
    current="$(gsettings get "$schema" "$key" 2>/dev/null || true)"
    [ -n "$current" ] || return 0

    if [ "${DRY_RUN:-0}" = 1 ]; then
        printf '    %sdry-run:%s remember %s %s = %s\n' \
            "$C_DIM" "$C_OFF" "$schema" "$key" "$current"
        return 0
    fi
    mkdir -p "$BACKUP_DIR"
    # Unquoted: gsettings prints strings as 'Adwaita', and every reader of this
    # wants the name rather than the GVariant spelling of it.
    current="${current#\'}"; current="${current%\'}"
    printf '%s\n' "$current" > "$dst"
}

# What gsettings_backup_once recorded, or nothing if it never ran.
gsettings_original() {
    cat "$BACKUP_DIR/$1.gsettings-orig" 2>/dev/null || true
}

gnome_major() {
    local v
    v="$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1)" || return 1
    printf '%s' "$v"
}

# How many screens this machine has, for the defaults that only earn their keep
# on more than one. Mutter is asked first because it knows which outputs the
# session is actually driving; DRM's connector list covers the case where there
# is no session to ask, and the larger of the two wins so a laptop with its lid
# shut around an external screen still counts as the two monitors it has.
monitor_count() {
    local mutter=0 drm=0

    if have gdbus; then
        # One match per logical monitor: each opens with its position, scale,
        # transform and primary flag before the outputs it is made of.
        mutter="$(gdbus call --session \
                    --dest org.gnome.Mutter.DisplayConfig \
                    --object-path /org/gnome/Mutter/DisplayConfig \
                    --method org.gnome.Mutter.DisplayConfig.GetCurrentState \
                    2>/dev/null \
                  | grep -oE '\(-?[0-9]+, -?[0-9]+, [0-9.]+, uint32 [0-9]+, (true|false), \[\(' \
                  | wc -l)"
    fi
    drm="$(grep -lx connected /sys/class/drm/card*-*/status 2>/dev/null | wc -l)"

    [ "$mutter" -gt "$drm" ] 2>/dev/null && drm="$mutter"
    [ "$drm" -gt 0 ] 2>/dev/null || drm=1
    printf '%s' "$drm"
}
