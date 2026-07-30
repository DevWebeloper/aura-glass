# shellcheck shell=bash
# tahoe-glass — distro detection and dependency installation.
#
# Two families are supported first-class:
#
#   arch    CachyOS, Arch, EndeavourOS …  — pacman, writable /usr
#   atomic  Bazzite, Bluefin, Silverblue … — rpm-ostree, read-only /usr
#
# The atomic case is why every asset in this project installs under $HOME.
# On Bazzite /usr/share/themes and /usr/share/icons cannot be written without
# layering a package and rebooting, but ~/.themes, ~/.local/share/icons and
# ~/.local/share/gnome-shell/extensions are all ordinary writable directories
# and GNOME reads them exactly the same way.

DISTRO_FAMILY=""   # arch | atomic | fedora | debian | unknown
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

    # Atomic wins over the ID_LIKE=fedora it also reports: an ostree system
    # needs a completely different dependency strategy from a mutable one.
    # /run/ostree-booted is a plain file written by ostree-prepare-root, not a
    # directory — `-d` silently never matches it and detection falls through
    # to the fedora branch, which tries dnf. Bazzite's dnf refuses to run at
    # all in that case, so this one check decides the whole install path.
    if have rpm-ostree && [ -e /run/ostree-booted ]; then
        DISTRO_FAMILY="atomic"
        return
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
declare -A PKG_ARCH=(
    [git]=git [curl]=curl [unzip]=unzip [sassc]=sassc
    [gsettings]=glib2 [dconf]=dconf [gnome-extensions]=gnome-shell
)
declare -A PKG_FEDORA=(
    [git]=git [curl]=curl [unzip]=unzip [sassc]=sassc
    [gsettings]=glib2 [dconf]=dconf [gnome-extensions]=gnome-shell
)
declare -A PKG_DEBIAN=(
    [git]=git [curl]=curl [unzip]=unzip [sassc]=sassc
    [gsettings]=libglib2.0-bin [dconf]=dconf-cli [gnome-extensions]=gnome-shell
)

REQUIRED_CMDS=(git curl unzip sassc gsettings dconf gnome-extensions)

# Bazzite and Bluefin preinstall a rootless Homebrew prefix at
# /home/linuxbrew/.linuxbrew so images that ship it never need to run brew's
# installer. But that prefix is only added to PATH by shell profile snippets,
# which a non-interactive session — cron, or `ssh host command` — never
# sources. `command -v brew` alone misses a real, working brew in exactly the
# situation this installer is likely to be run from.
find_brew() {
    have brew && { command -v brew; return 0; }
    local p
    for p in /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew" /opt/homebrew/bin/brew; do
        [ -x "$p" ] && { printf '%s' "$p"; return 0; }
    done
    return 1
}

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
        atomic)
            # Homebrew ships with Bazzite and Bluefin and installs into
            # /home/linuxbrew, so it needs no layering and no reboot. Layering
            # is offered second because it costs a reboot before the install
            # can even continue.
            local brew_bin
            if brew_bin="$(find_brew)"; then
                # A brew found outside PATH means the shell that will run the
                # rest of this script — including the theme's own installer,
                # which shells out to sassc — can't see it either. Put its bin
                # dir on PATH now so both `brew install` and everything
                # downstream in this process can find what it just installed.
                case ":$PATH:" in
                    *":$(dirname "$brew_bin"):"*) ;;
                    *) export PATH="$(dirname "$brew_bin"):$PATH" ;;
                esac
                info "would run: $brew_bin install ${missing[*]}"
                confirm "Install these with Homebrew? (no reboot needed)" 1 \
                    || { warn "skipping — install them yourself, then re-run"; return 1; }
                run "$brew_bin" install "${missing[@]}"
            else
                local pkgs; pkgs="$(install_hint PKG_FEDORA "${missing[@]}")"
                warn "Homebrew not found on an atomic system."
                warn "Layering requires a reboot before this installer can continue:"
                warn "    rpm-ostree install $pkgs && systemctl reboot"
                warn "Homebrew is the lighter option:"
                warn "    /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/brew/HEAD/install.sh)\""
                return 1
            fi
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
