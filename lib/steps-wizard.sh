# shellcheck shell=bash
# aura-glass — handing the opening questions to a window.
#
# The questions themselves are install.sh's, and so are the answers: everything
# downstream of the wizard reads flags, and this only decides which of two things
# collects them. gui/aura_glass_setup_wizard.py asks them in a window and prints
# the flags it settled on; install.sh's own text wizard asks the same ones here
# in the terminal. Both end at the same parse_flags call.
#
# That is the whole design. The window is a front end for the flag surface rather
# than a second configuration path, so there is nothing it can express that a
# command line cannot, and nothing to keep in sync but the questions.
#
# Anything that is not "the user answered" falls back to the text wizard rather
# than stopping: no display, no toolkit, a declined package install, a Python
# traceback on an unusual desktop. The one exception is Cancel, which is an
# answer — see run_setup_wizard's return codes.

# run_setup_wizard — fills WIZARD_ARGS with the flags the window settled on.
#
#   0  answered; WIZARD_ARGS holds the flags
#   1  cancelled; the caller stops the install
#   2  no window was available; the caller asks in the terminal instead
run_setup_wizard() {
    WIZARD_ARGS=()

    # An SSH session or a bare TTY is not asked whether it would like to install
    # a GUI toolkit it has nowhere to draw with.
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        return 2
    fi

    local wizard="$REPO_ROOT/gui/aura_glass_setup_wizard.py"
    [ -r "$wizard" ] || return 2

    ensure_gui_toolkit || return 2

    # Computed here rather than in Python, so the check for a login manager has
    # one copy. It is the same one the text wizard's GDM step makes.
    local gdm_flag=""
    if have gdm || have gdm3 || [ -e /usr/sbin/gdm3 ]; then
        gdm_flag="--gdm-present"
    fi

    local out rc=0
    out="$(mktemp)" || return 2

    step "Setup"
    info "opening the setup wizard — this terminal continues once it closes"

    # Plain redirection rather than a pipe or process substitution, because the
    # exit code is the whole protocol here and only a simple command reports its
    # own. stderr stays attached: a traceback belongs on the screen, and stdout
    # is reserved for the flags.
    python3 "$wizard" --repo "$REPO_ROOT" ${gdm_flag:+"$gdm_flag"} >"$out" || rc=$?

    if [ "$rc" = 2 ]; then
        rm -f "$out"
        return 1
    fi
    if [ "$rc" != 0 ]; then
        rm -f "$out"
        warn "the setup wizard exited unexpectedly — asking here instead"
        return 2
    fi

    mapfile -t WIZARD_ARGS < "$out"
    rm -f "$out"

    # A run that answered everything and produced nothing is the wizard being
    # broken rather than a user choosing an empty install. The terminal asks.
    if [ "${#WIZARD_ARGS[@]}" -eq 0 ]; then
        warn "the setup wizard returned no settings — asking here instead"
        return 2
    fi

    return 0
}
