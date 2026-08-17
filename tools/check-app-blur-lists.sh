#!/usr/bin/env bash
# Assert the per-app blur lists survive the trip from a flag, through a memo, to
# a dconf array literal — and back out again as the same patterns.
#
# The lists are the one place in this project where arbitrary user text reaches
# dconf. A pattern is whatever someone typed into the settings window, and it is
# spliced into a GVariant literal to get there, so the failure mode is not a
# wrong look but a `dconf write` that will not parse — or worse, one that parses
# as something else. install.sh has `set -e`, so that ends the run part-way
# through with a message about GVariant that says nothing about which app name
# caused it.
#
# Nothing here touches live dconf. The literal is built and then parsed back with
# GLib's own parser, which is the same code dconf would use.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# app_blur_lines and app_blur_literal are the pieces under test. They need
# nothing from the rest of the installer, so they are sourced alone rather than
# by running an install.
CONF_DIR="$(mktemp -d)"
trap 'rm -rf "$CONF_DIR"' EXIT
DRY_RUN=0
# shellcheck source=../lib/steps-dconf.sh
. "$REPO_ROOT/lib/steps-dconf.sh"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# --- the literal parses, and means what went in --------------------------
check_round_trip() {
    local label="$1"; shift
    local literal
    literal="$(printf '%s\n' "$@" | app_blur_literal)"
    REPO_ROOT="$REPO_ROOT" LITERAL="$literal" LABEL="$label" \
    python3 - "$@" <<'PY' || fail=1
import os, sys
import gi
gi.require_version("GLib", "2.0")
from gi.repository import GLib

want = [a for a in sys.argv[1:] if a.strip()]
literal, label = os.environ["LITERAL"], os.environ["LABEL"]
try:
    got = GLib.Variant.parse(GLib.VariantType("as"), literal, None, None).unpack()
except GLib.Error as exc:
    print("  %s: dconf could not parse %s\n      %s" % (label, literal, exc.message))
    sys.exit(1)
if got != want:
    print("  %s: parsed back as %s, want %s" % (label, got, want))
    sys.exit(1)
PY
}

check_round_trip "plain names" org.gnome.Nautilus org.gnome.Console
check_round_trip "wildcards" '*chrome*' '*electron*'
# The three that break naive quoting. An apostrophe closes a GVariant string, a
# backslash escapes the next character, and a double quote is fine but only if
# the escaping did not switch quote styles to cope with the apostrophe.
check_round_trip "apostrophe" "Bob's App"
check_round_trip "backslash" 'weird\name'
check_round_trip "double quote" 'say "hi"'
check_round_trip "spaces" 'Some App Name'
check_round_trip "blank lines dropped" org.gnome.Nautilus '' '  ' org.gnome.Console

# --- precedence: flag beats memo beats default ---------------------------
printf 'from.the.memo\n' > "$CONF_DIR/app-blur-allow"

got="$(app_blur_lines "" "" "$CONF_DIR/app-blur-allow" shipped.default | tr '\n' ' ')"
[ "$got" = "from.the.memo " ] || note "memo should win over the default, got: $got"

got="$(app_blur_lines 1 "from.the.flag" "$CONF_DIR/app-blur-allow" shipped.default | tr '\n' ' ')"
[ "$got" = "from.the.flag " ] || note "flag should win over the memo, got: $got"

got="$(app_blur_lines "" "" "$CONF_DIR/missing" shipped.default | tr '\n' ' ')"
[ "$got" = "shipped.default " ] || note "default should apply with no memo, got: $got"

# Clearing a list is a thing a user does — the settings window removing the last
# row sends an empty flag. Testing the value alone read that as "no flag given"
# and quietly reinstated the previous list, which looked like the remove button
# not working.
got="$(app_blur_lines 1 "" "$CONF_DIR/app-blur-allow" shipped.default | tr -d '\n')"
[ -z "$got" ] || note "an explicitly empty flag should empty the list, got: '$got'"

got="$(app_blur_lines 1 "a,b,c" "$CONF_DIR/app-blur-allow" shipped.default | tr '\n' ' ')"
[ "$got" = "a b c " ] || note "commas should split into entries, got: $got"

if [ "$fail" = 1 ]; then
    printf '\napp blur list check FAILED\n\n'
    exit 1
fi
printf 'app blur list check passed — literals parse, and flag/memo/default precedence holds\n'
