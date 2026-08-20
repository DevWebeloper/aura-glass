# shellcheck shell=bash
# aura-glass — the interface font.
#
# GNOME ships Cantarell and nothing here argues with that being a reasonable
# default, which is why --font system is the default and resets rather than
# writes. The other three are the fonts this look was drawn against, and none
# of them is packaged widely enough to assume: picking one that is not on the
# machine would set a gsettings key to a family fontconfig cannot resolve, and
# the desktop would silently render in the fallback instead. So the step that
# offers them is also the step that installs them.
#
# Everything lands under one directory, $FONT_DIR, and nothing outside it is
# touched — the packaged copy of a font that is already installed system-wide
# keeps working, and uninstall.sh removes this directory whole.
#
# The families each value resolves to are not guessable from the value, which
# is why font_family exists rather than a title-cased FONT:
#
#   misans   MiSans Latin      (the Latin zip's family; the full MiSans is CJK)
#   inter    Inter             (Inter.ttc; InterVariable is a separate family)
#   sf-pro   SF Pro Display    (the Text faces install too, for anything that
#                               asks for them — dconf/core.ini's panel font does)
#
# Sourced by install.sh.

FONT_DIR="$HOME/.local/share/fonts/aura-glass"

# Where fontconfig reads per-user rules from. Only MiSans puts anything here,
# and only because its Arabic coverage is a separate family from its Latin one.
FONTCONFIG_DIR="$HOME/.config/fontconfig/conf.d"
MISANS_ARABIC_CONF="$FONTCONFIG_DIR/60-aura-glass-misans.conf"

# The family name apply_gsettings writes into the three font keys. Empty for
# "system", which is the signal to reset them instead — see apply_font.
font_family() {
    case "${FONT:-system}" in
        misans) printf 'MiSans Latin\n' ;;
        inter)  printf 'Inter\n' ;;
        sf-pro) printf 'SF Pro Display\n' ;;
        *)      printf '\n' ;;
    esac
}

# True when fontconfig can already resolve the family this run wants. Asked of
# fontconfig rather than of $FONT_DIR because a font installed by the distro
# package manager is just as good an answer — there is nothing to download if
# `pacman -S inter-font` got there first.
#
# fc-match always answers with something, so the answer has to be compared:
# asking for a family that is not installed returns DejaVu Sans and reports
# success, which is exactly the silent fallback this step exists to prevent.
font_present() {
    local family="$1" got
    have fc-match || return 1
    got="$(fc-match -f '%{family[0]}' "$family" 2>/dev/null || true)"
    [ "$got" = "$family" ]
}

# One vendor directory under $FONT_DIR, emptied first. A font that changed its
# file names between releases would otherwise leave the old faces beside the
# new ones, and fontconfig would carry on serving both.
font_dest() {
    local dir="$FONT_DIR/$1"
    rm -rf "$dir"
    mkdir -p "$dir"
    printf '%s\n' "$dir"
}

install_font_inter() {
    local src="$SRC_CACHE/Inter"
    fetch_zip_pinned "$INTER_URL" "$INTER_SHA256" "$src"
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: copy Inter.ttc into $FONT_DIR/inter"
        return 0
    fi
    [ -f "$src/Inter.ttc" ] || die "the Inter release did not contain Inter.ttc"
    local dest; dest="$(font_dest inter)"
    cp "$src/Inter.ttc" "$dest/" || die "could not install Inter.ttc"
    # The licence travels with the font. Inter is OFL and the OFL asks for it.
    if [ -f "$src/LICENSE.txt" ]; then
        cp "$src/LICENSE.txt" "$dest/"
    fi
    return 0
}

install_font_misans() {
    local latin="$SRC_CACHE/MiSans-Latin" arabic="$SRC_CACHE/MiSans-Arabic"
    fetch_zip_pinned "$MISANS_LATIN_URL"  "$MISANS_LATIN_SHA256"  "$latin"  warn
    fetch_zip_pinned "$MISANS_ARABIC_URL" "$MISANS_ARABIC_SHA256" "$arabic" warn
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: copy the MiSans Latin and Arabic UI faces into $FONT_DIR/misans"
        info "dry-run: write $MISANS_ARABIC_CONF"
        return 0
    fi

    # Two faces out of the ten each zip ships, and this is not a size decision.
    #
    # MiSans numbers its weights its own way: the face it calls Regular declares
    # usWeightClass 330 and the one it calls Medium declares 380. A desktop asks
    # for 400, fontconfig answers with whichever face is nearest, and with all
    # ten installed that is Medium — so the whole interface came out one step
    # heavy, and every Bold request (700) landed on Heavy rather than on Bold
    # (630). Installing only the two the desktop actually asks for leaves
    # nothing in between for it to land on wrongly.
    #
    # Both zips unpack to a directory named for the script, with spaces in it,
    # and Xiaomi have renamed those between releases. Finding the ttf by shape
    # rather than by path survives that; requiring the Latin pair is what turns
    # a changed layout into an error rather than an empty directory.
    local dest; dest="$(font_dest misans)"
    local found=0 f
    while IFS= read -r f; do
        cp "$f" "$dest/" || die "could not install $(basename "$f")"
        found=1
    done < <(find "$latin" -type f \
                  \( -name 'MiSansLatin-Regular.ttf' -o -name 'MiSansLatin-Bold.ttf' \) \
                  2>/dev/null)
    [ "$found" = 1 ] || die "the MiSans Latin zip contained no MiSansLatin-Regular.ttf"

    # The UI cut of MiSans Arabic rather than the text cut: shorter line height,
    # which is what a panel and a menu bar want. Same two weights, same reason.
    while IFS= read -r f; do
        cp "$f" "$dest/"
    done < <(find "$arabic" -type f \
                  \( -name 'MiSansArabicUI-Regular.ttf' -o -name 'MiSansArabicUI-Bold.ttf' \) \
                  2>/dev/null)

    # Without this, Arabic text under a MiSans Latin interface font falls back
    # by fontconfig's own ordering, which on most distributions means Noto —
    # the two faces are different enough that a mixed string reads as a mistake.
    # The rule only fires for the family this project sets, so it cannot affect
    # anything else on the machine, and uninstall.sh deletes it.
    #
    # The comment inside it does not name the flag: a double hyphen is illegal
    # inside an XML comment, fontconfig rejects the whole file over one, and a
    # rejected file is a line of noise on stderr in front of every fc- call on
    # the machine rather than a rule that quietly does not fire.
    mkdir -p "$FONTCONFIG_DIR"
    cat > "$MISANS_ARABIC_CONF" <<'CONF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!-- Written by aura-glass, for the misans interface font. Removed by
     uninstall.sh. MiSans Latin has no Arabic coverage; this hands those
     glyphs to the Arabic UI cut of the same family rather than to the
     system fallback. -->
<fontconfig>
  <match target="pattern">
    <test name="family"><string>MiSans Latin</string></test>
    <edit name="family" mode="append" binding="weak">
      <string>MiSans Arabic UI</string>
    </edit>
  </match>
</fontconfig>
CONF
    return 0
}

install_font_sfpro() {
    local src="$SRC_CACHE/San-Francisco-Pro-Fonts"
    clone_pinned "$SFPRO_REPO" "$SFPRO_REF" "$src"
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: copy the SF Pro Display and Text faces into $FONT_DIR/sf-pro"
        return 0
    fi
    local dest; dest="$(font_dest sf-pro)"
    # Four weights of the eighteen each family ships, for the same reason MiSans
    # gets two of ten, and here the mis-numbering is worse: this mirror's
    # SF-Pro-Display-Bold.otf declares the weight fontconfig reads as semibold,
    # which is the number Semibold declares too. A bold request then finds
    # Heavy nearer than Bold, and every window title on the desktop came out in
    # Heavy. With nothing installed between Regular and Bold there is nothing
    # nearer for it to find.
    #
    # Display and Text both, because they are two families and the panel font
    # in dconf/core.ini names Display while an app asking for Text should get
    # it. Rounded and the variable SF-Pro.ttf are left behind: neither is an
    # interface face, and each would add a family to every font list.
    local found=0 f cut weight
    for cut in Display Text; do
        for weight in Regular RegularItalic Bold BoldItalic; do
            f="$src/SF-Pro-$cut-$weight.otf"
            [ -f "$f" ] || continue
            cp "$f" "$dest/" || die "could not install $(basename "$f")"
            found=1
        done
    done
    [ "$found" = 1 ] || die "the San Francisco checkout contained no SF-Pro-Display-Regular.otf"
    return 0
}

install_fonts() {
    if [ "${FONT:-system}" = system ]; then
        step "Interface font"
        skip "keeping the system font (--font inter, misans or sf-pro to change)"
        return 0
    fi

    local family; family="$(font_family)"
    step "Installing the $family font"

    # Already resolvable and not being forced: there is nothing to fetch. The
    # gsettings keys are still written further down by apply_gsettings, which is
    # what makes --settings-only able to move the font with no network at all.
    if [ "${FORCE:-0}" != 1 ] && font_present "$family"; then
        skip "$family is already installed"
        return 0
    fi

    case "$FONT" in
        inter)  install_font_inter ;;
        misans) install_font_misans ;;
        sf-pro) install_font_sfpro ;;
    esac

    # fontconfig caches per directory and by mtime, so a freshly written font
    # directory is invisible to every running application until this runs. The
    # already-running shell picks the new family up on the next login either
    # way, but GTK apps started after this see it immediately.
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: fc-cache -f $FONT_DIR"
    elif have fc-cache; then
        fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
    fi

    ok "$family"
}
