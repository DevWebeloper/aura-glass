# shellcheck shell=bash
# tahoe-glass — distro detection and dependency installation.
#
# arch — CachyOS, Arch, EndeavourOS … — is the family this is built and tested
# on. fedora and debian are handled on the same terms but are not exercised.
#
# Every asset still installs under $HOME: ~/.themes, ~/.local/share/icons and
# ~/.local/share/gnome-shell/extensions are read by GNOME exactly as their
# /usr counterparts are, and staying out of /usr is what keeps the whole
# install root-free apart from fetching dependencies.

DISTRO_FAMILY=""   # arch | fedora | debian | unknown
DISTRO_NAME=""
DISTRO_PRETTY=""

detect_distro() {
    local id='' id_like=''
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="${ID:-}"; id_like="${ID_LIKE:-}"
        DISTRO_NAME="$id"
        DISTRO_PRETTY="${PRETTY_NAME:-$id}"
    fi

    case " $id $id_like " in
        *" arch "*|*" cachyos "*|*" archarm "*) DISTRO_FAMILY="arch" ;;
        *" fedora "*|*" rhel "*)                DISTRO_FAMILY="fedora" ;;
        *" debian "*|*" ubuntu "*)              DISTRO_FAMILY="debian" ;;
        *)                                      DISTRO_FAMILY="unknown" ;;
    esac
}

# Commands the installer genuinely needs, mapped to the package that ships
# them. sassc is the only one that is regularly missing — the Tahoe theme
# compiles its SCSS at install time.
#
# python3 is here because it is load-bearing rather than incidental: every
# extension's metadata is checked through it (ext_supports_shell), the display
# density is measured and the correction emitted through it, enabled-extensions
# is appended through it, and bin/tahoe-glass-apply does its whole block-replace
# in it. Without it the install used to pass this check, report "all
# dependencies present", and then die part-way through with a bare "command not
# found" — which is the one failure mode this step exists to prevent. Arch
# spells the package `python`; Fedora and Debian spell it `python3`.
declare -A PKG_ARCH=(
    [git]=git [curl]=curl [unzip]=unzip [sassc]=sassc
    [gsettings]=glib2 [dconf]=dconf [gnome-extensions]=gnome-shell
    [msgfmt]=gettext [python3]=python
)
declare -A PKG_FEDORA=(
    [git]=git [curl]=curl [unzip]=unzip [sassc]=sassc
    [gsettings]=glib2 [dconf]=dconf [gnome-extensions]=gnome-shell
    [msgfmt]=gettext [python3]=python3
)
declare -A PKG_DEBIAN=(
    [git]=git [curl]=curl [unzip]=unzip [sassc]=sassc
    [gsettings]=libglib2.0-bin [dconf]=dconf-cli [gnome-extensions]=gnome-shell
    [msgfmt]=gettext [python3]=python3
)

REQUIRED_CMDS=(git curl unzip sassc gsettings dconf gnome-extensions python3)

# Nice to have, never fatal. msgfmt compiles Blur My Shell's translations when
# it is built from git; without it the extension works and its preferences are
# simply untranslated. Kept out of REQUIRED_CMDS so a missing gettext cannot
# block the whole install over a cosmetic loss.
OPTIONAL_CMDS=(msgfmt)

missing_cmds() {
    local c
    for c in "${REQUIRED_CMDS[@]}"; do
        have "$c" || printf '%s\n' "$c"
    done
}

# Print the exact command a user would run, so nothing installs behind
# their back and the manual path is always one copy-paste away.
install_hint() {
    local -n _map=$1; shift
    local pkgs=() c
    for c in "$@"; do pkgs+=("${_map[$c]:-$c}"); done
    printf '%s' "${pkgs[*]}"
}

install_deps() {
    local missing=() c
    while IFS= read -r c; do [ -n "$c" ] && missing+=("$c"); done < <(missing_cmds)

    # Reported but never installed or waited on: an optional command going
    # missing should read as a note, not as something the user has to act on.
    local opt=() o
    for o in "${OPTIONAL_CMDS[@]}"; do have "$o" || opt+=("$o"); done
    [ ${#opt[@]} -gt 0 ] && info "optional, not installed: ${opt[*]}"

    if [ ${#missing[@]} -eq 0 ]; then
        ok "all dependencies present"
        return 0
    fi

    info "missing: ${missing[*]}"

    case "$DISTRO_FAMILY" in
        arch)
            local pkgs; pkgs="$(install_hint PKG_ARCH "${missing[@]}")"
            info "would run: sudo pacman -S --needed $pkgs"
            confirm "Install these with pacman?" 1 || { warn "skipping — install them yourself, then re-run"; return 1; }
            run sudo pacman -S --needed --noconfirm $pkgs
            ;;
        fedora)
            local pkgs; pkgs="$(install_hint PKG_FEDORA "${missing[@]}")"
            info "would run: sudo dnf install $pkgs"
            confirm "Install these with dnf?" 1 || { warn "skipping — install them yourself, then re-run"; return 1; }
            run sudo dnf install -y $pkgs
            ;;
        debian)
            local pkgs; pkgs="$(install_hint PKG_DEBIAN "${missing[@]}")"
            info "would run: sudo apt install $pkgs"
            confirm "Install these with apt?" 1 || { warn "skipping — install them yourself, then re-run"; return 1; }
            run sudo apt-get install -y $pkgs
            ;;
        *)
            warn "unknown distro — install these yourself: ${missing[*]}"
            return 1
            ;;
    esac

    local still=() c2
    while IFS= read -r c2; do [ -n "$c2" ] && still+=("$c2"); done < <(missing_cmds)
    if [ ${#still[@]} -gt 0 ] && [ "${DRY_RUN:-0}" != 1 ]; then
        die "still missing after install: ${still[*]}"
    fi
    ok "dependencies satisfied"
}
