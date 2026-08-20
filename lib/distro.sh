# shellcheck shell=bash
# aura-glass — distro detection and dependency installation.
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
# is appended through it, and bin/aura-glass-apply does its whole block-replace
# in it. Without it the install used to pass this check, report "all"
# dependencies present", and then die part-way through with a bare "command not
# found" — which is the one failure mode this step exists to prevent. Arch
# spells the package `python`; Fedora and Debian spell it `python3`.
declare -A PKG_ARCH=(
    [git]=git [curl]=curl [unzip]=unzip [sassc]=sassc
    [gsettings]=glib2 [dconf]=dconf [gnome-extensions]=gnome-shell
    [msgfmt]=gettext [python3]=python [glib-compile-resources]=glib2
    [xmllint]=libxml2
)
declare -A PKG_FEDORA=(
    [git]=git [curl]=curl [unzip]=unzip [sassc]=sassc
    [gsettings]=glib2 [dconf]=dconf [gnome-extensions]=gnome-shell
    [msgfmt]=gettext [python3]=python3 [glib-compile-resources]=glib2-devel
    [xmllint]=libxml2
)
declare -A PKG_DEBIAN=(
    [git]=git [curl]=curl [unzip]=unzip [sassc]=sassc
    [gsettings]=libglib2.0-bin [dconf]=dconf-cli [gnome-extensions]=gnome-shell
    [msgfmt]=gettext [python3]=python3 [glib-compile-resources]=libglib2.0-dev-bin
    [xmllint]=libxml2-utils
)

REQUIRED_CMDS=(git curl unzip sassc gsettings dconf gnome-extensions python3 glib-compile-resources)

# PyGObject and libadwaita's typelib, for the settings window and the graphical
# setup wizard. These are imported rather than executed, so `command -v` cannot
# see them and they cannot join REQUIRED_CMDS or the PKG_* maps above — hence a
# probe of their own.
#
# Non-fatal, the same tier as msgfmt below: what a missing GUI toolkit costs is
# one optional window and a wizard that has a text twin, and every setting either
# exposes is a flag that still works from the command line. Failing an install of
# a *theme* over it would be absurd.
gui_toolkit_present() {
    python3 - >/dev/null 2>&1 <<'PY'
import gi
gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")
from gi.repository import Adw, Gtk
PY
}

# What it takes to get it, per family. One copy, read by both the hint that only
# prints and the step that offers to run it.
GUI_TOOLKIT_PKGS_ARCH="python-gobject libadwaita"
GUI_TOOLKIT_PKGS_FEDORA="python3-gobject libadwaita"
GUI_TOOLKIT_PKGS_DEBIAN="python3-gi gir1.2-adw-1"

# Printed as a suggestion — never run. install_gui uses this, because by the time
# it runs the install is already under way and the window it wants is optional.
gui_toolkit_hint() {
    case "$DISTRO_FAMILY" in
        arch)   printf 'sudo pacman -S --needed %s' "$GUI_TOOLKIT_PKGS_ARCH" ;;
        fedora) printf 'sudo dnf install %s' "$GUI_TOOLKIT_PKGS_FEDORA" ;;
        debian) printf 'sudo apt install %s' "$GUI_TOOLKIT_PKGS_DEBIAN" ;;
        *)      printf 'install PyGObject and libadwaita 1 for your distro' ;;
    esac
}

# The same packages, offered rather than printed — for the graphical setup
# wizard, which is asked for before anything has been installed and is worth one
# question at that point.
#
# Deliberately unlike install_deps in the one way that matters: it never dies.
# Every path out of here that is not "the toolkit is now present" means the text
# wizard runs instead, which asks the same questions and reaches the same flags.
# A declined package install is a preference, not a failure, and the install
# carries on either way.
ensure_gui_toolkit() {
    gui_toolkit_present && return 0

    local pkgs
    case "$DISTRO_FAMILY" in
        arch)   pkgs="$GUI_TOOLKIT_PKGS_ARCH" ;;
        fedora) pkgs="$GUI_TOOLKIT_PKGS_FEDORA" ;;
        debian) pkgs="$GUI_TOOLKIT_PKGS_DEBIAN" ;;
        *)      return 1 ;;
    esac

    info "the graphical setup wizard needs: $pkgs"
    info "without it the same questions are asked here in the terminal"
    info "would run: $(gui_toolkit_hint)"
    confirm "Install them and use the graphical wizard?" 1 || return 1

    case "$DISTRO_FAMILY" in
        arch)   run sudo pacman -S --needed --noconfirm $pkgs ;;
        fedora) run sudo dnf install -y $pkgs ;;
        debian) run sudo apt-get install -y $pkgs ;;
    esac

    gui_toolkit_present
}

# Nice to have, never fatal. msgfmt compiles Blur My Shell's translations when
# it is built from git; without it the extension works and its preferences are
# simply untranslated. Kept out of REQUIRED_CMDS so a missing gettext cannot
# block the whole install over a cosmetic loss.
OPTIONAL_CMDS=(msgfmt xmllint)

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

# ---------- Who owns a file, and how to remove them ----------
#
# The settings window's Packages page lists the icon and pointer themes on the
# machine, and the ones under /usr belong to the distribution rather than to
# this project. It used to say so and stop there. These two answer the obvious
# next question — which package is that, and what would remove it — without
# either side of the window having to know one distro's syntax.
#
# They are here rather than in the Python for the reason every other
# distro-shaped thing is: DISTRO_FAMILY is resolved in exactly one place, and a
# second copy of that case statement is a second thing to update when a family
# is added.
#
# Neither of them removes anything. pkg_remove_cmd prints a command for a
# terminal the user is looking at, because this is root's work and a password
# prompt needs a keyboard — the same rule the window follows for the rounded
# blur library and for uninstall.sh.

# The package that owns a path, or nothing if no package does.
pkg_owner() {
    local path="${1:-}"
    [ -n "$path" ] || return 1
    case "$DISTRO_FAMILY" in
        arch)
            have pacman || return 1
            # -Qoq prints the name alone. A path no package owns is an error
            # with a message on stderr, which is the "not from a package" case
            # rather than a failure worth reporting.
            pacman -Qoq "$path" 2>/dev/null | head -n1
            ;;
        fedora)
            have rpm || return 1
            rpm -qf --queryformat '%{NAME}\n' "$path" 2>/dev/null | head -n1
            ;;
        debian)
            have dpkg || return 1
            # `dpkg -S` answers "package: path" and takes no leading ./, so the
            # name is everything before the first colon.
            dpkg -S "$path" 2>/dev/null | head -n1 | cut -d: -f1
            ;;
        *)  return 1 ;;
    esac
}

# The command that would remove a package, for a terminal to run.
#
# On Arch an AUR helper is preferred when one is installed, because a theme
# under /usr on an Arch machine is as likely to have come from the AUR as from
# the repositories, and paru or yay removing it keeps that machine's own record
# of what it built straight. Both take pacman's own -Rns for a removal, so this
# is the same command with a different front end rather than a special case.
pkg_remove_cmd() {
    local pkg="${1:-}"
    [ -n "$pkg" ] || return 1
    case "$DISTRO_FAMILY" in
        arch)
            local helper
            for helper in paru yay; do
                have "$helper" && { printf '%s -Rns %s' "$helper" "$pkg"; return 0; }
            done
            printf 'sudo pacman -Rns %s' "$pkg"
            ;;
        fedora) printf 'sudo dnf remove %s' "$pkg" ;;
        debian) printf 'sudo apt remove %s' "$pkg" ;;
        *)      return 1 ;;
    esac
}
