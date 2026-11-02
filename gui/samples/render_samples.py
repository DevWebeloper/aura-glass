#!/usr/bin/env python3
"""Rebuild what the setup wizard shows of the fonts and pointers it offers.

The wizard runs before anything is installed, so none of the fonts or pointer
packs it asks about are on the machine yet. These files are how it can show them
anyway; gui/samples/NOTICE.md says why they are these and not the fonts.

Not part of an install and not run by one: run it by hand after changing
FONT_SAMPLES in gui/aura_glass_setup_wizard.py, after moving a pointer pack's pin
in lib/steps.sh, or after changing tools/moga_cursor.py's accent table. It needs
what the wizard does not, pycairo and PangoCairo, and the sources themselves:

  fonts     installed, which is the point of asking fontconfig below
  pointers  only with --mactahoe, a checkout of MACTAHOE_REF, plus
            $HOME/.cache/aura-glass/src, which an install that picked each pack
            leaves behind
  icons     only with --icon-themes, an icons directory holding every colour of
            all three packs: each pack's own installer run with a throwaway HOME
            for each -t, as lib/steps-assets.sh runs it, and Hatter's folders
            copied in. About 1.6 GB, so not something to keep around.
"""
import argparse
import configparser
import gzip
import importlib.util
import json
import os
import shutil
import subprocess
import sys

import cairo
import gi

gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Pango, PangoCairo  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "gui"))

import aura_glass_setup_wizard as wiz  # noqa: E402


def font_family(font):
    """The family install.sh would set, from install.sh rather than a copy."""
    script = 'source "$1/lib/steps-fonts.sh"; FONT="$2" font_family'
    return subprocess.run(["bash", "-c", script, "bash", ROOT, font],
                          capture_output=True, text=True,
                          check=True).stdout.strip()


def require_font(family):
    # fc-match always answers. A family it does not have comes back as DejaVu
    # and would be shipped as a sample of something else (font_present in
    # lib/steps-fonts.sh guards the same trap).
    got = subprocess.run(["fc-match", "-f", "%{family[0]}", family],
                         capture_output=True, text=True, check=True).stdout
    if got != family:
        sys.exit("%s is not installed (fontconfig answered %s)" % (family, got))


def render_text(family, text, px, weight):
    """One string as its outline: an SVG path that Gsk.Path can parse.

    Unhinted, because a hinted outline only suits the one scale it was hinted
    for and these get shown at all of them. The whole line box rather than the
    ink, so a sample sits where a label of that font would.
    """
    options = cairo.FontOptions()
    options.set_hint_style(cairo.HINT_STYLE_NONE)
    options.set_hint_metrics(cairo.HINT_METRICS_OFF)
    context = cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1))
    layout = PangoCairo.create_layout(context)
    PangoCairo.context_set_font_options(layout.get_context(), options)
    desc = Pango.FontDescription()
    desc.set_family(family)
    desc.set_absolute_size(px * Pango.SCALE)
    desc.set_weight(wiz.SAMPLE_WEIGHTS[weight])
    layout.set_font_description(desc)
    layout.set_text(text, -1)
    width, height = layout.get_pixel_size()
    PangoCairo.layout_path(context, layout)

    letters = {cairo.PATH_MOVE_TO: "M", cairo.PATH_LINE_TO: "L",
               cairo.PATH_CURVE_TO: "C", cairo.PATH_CLOSE_PATH: "Z"}
    parts = []
    for kind, points in context.copy_path():
        parts.append(letters[kind] + " ".join("%.3g" % round(v, 3) if abs(v) < 1
                                              else "%.3f" % v for v in points))
    return {"width": width + 1, "height": height, "path": " ".join(parts)}


def render_fonts():
    folder = os.path.join(HERE, "fonts")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    for font, _title, _subtitle in wiz.FONTS:
        family = font_family(font)
        # "system" has no outlines: it is drawn live, in whatever the machine has.
        if not family:
            continue
        require_font(family)
        outlines = {key: render_text(family, text, px, weight)
                    for key, (text, px, weight) in wiz.FONT_SAMPLES.items()}
        with open(os.path.join(folder, font + ".json"), "w",
                  encoding="utf-8") as out:
            json.dump(outlines, out, indent=0, sort_keys=True)
            out.write("\n")


def ship_pointer(source, name):
    """The pack's own arrow file, whole and untouched. See NOTICE.md."""
    with open(source, "rb") as handle:
        data = handle.read()
    with gzip.GzipFile(os.path.join(HERE, "pointers", name + ".xcursor.gz"),
                       "wb", compresslevel=9, mtime=0) as out:
        out.write(data)


def moga_variant_for(accent):
    spec = importlib.util.spec_from_file_location(
        "moga_cursor", os.path.join(ROOT, "tools", "moga_cursor.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.variant_for(accent)


def ship_pointers(mactahoe):
    cache = os.path.expanduser("~/.cache/aura-glass/src")
    folder = os.path.join(HERE, "pointers")
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    for accent, _label, _hexcolour in wiz.ACCENTS:
        variant = moga_variant_for(accent)
        pack = "Moga-Neon-" + variant
        ship_pointer(os.path.join(cache, "moga-" + variant, pack, pack,
                                  "cursors", "default"), "moga-" + accent)
    ship_pointer(os.path.join(cache, "aosp-cursors", "aosp-cursors", "cursors",
                              "default"), "aosp")
    # dist-dark because install_cursors asks for the MacTahoe-dark theme.
    ship_pointer(os.path.join(mactahoe, "cursors", "dist-dark", "cursors",
                              "default"), "mactahoe")


def asked_of_installer(function, accent):
    """An accent's colour or theme name, from lib/ rather than a copy of it."""
    script = 'source "$1/lib/steps-assets.sh"; "$2" "$3"'
    return subprocess.run(["bash", "-c", script, "bash", ROOT, function, accent],
                          capture_output=True, text=True,
                          check=True).stdout.strip()


def theme_for(pack, accent):
    """The theme directory install.sh would point the key at, minus -dark."""
    if pack == "reversal":
        return "Reversal-" + asked_of_installer("accent_to_reversal", accent)
    if pack == "hatter":
        return "Hatter-" + asked_of_installer("accent_to_hatter", accent)
    return asked_of_installer("accent_to_colloid_name", accent)


def find_icon(themes, theme, name, seen=()):
    """The scalable drawing of name, following Inherits as GTK would."""
    folder = os.path.join(themes, theme)
    found = None
    for where, _dirs, files in os.walk(folder, followlinks=True):
        if name + ".svg" in files and "symbolic" not in where:
            path = os.path.join(where, name + ".svg")
            rank = ("scalable" not in where, where)
            if found is None or rank < found[0]:
                found = (rank, path)
    if found:
        return found[1]
    index = configparser.ConfigParser(interpolation=None, strict=False)
    index.read(os.path.join(folder, "index.theme"), encoding="utf-8")
    for parent in index.get("Icon Theme", "Inherits", fallback="").split(","):
        parent = parent.strip()
        if parent and parent not in seen and os.path.isdir(
                os.path.join(themes, parent)):
            inherited = find_icon(themes, parent, name, (*seen, theme))
            if inherited:
                return inherited
    return None


def ship_icons(themes):
    folder = os.path.join(HERE, "icons")
    shutil.rmtree(folder, ignore_errors=True)
    for pack in ("reversal", "hatter", "colloid"):
        os.makedirs(os.path.join(folder, pack))
        for name in wiz.ICON_SAMPLES:
            drawings = {}
            for accent, _label, _hexcolour in wiz.ACCENTS:
                path = find_icon(themes, theme_for(pack, accent), name)
                if not path:
                    sys.exit("%s has no %s for %s" % (pack, name, accent))
                with open(path, "rb") as handle:
                    drawings[accent] = handle.read()
            for accent, data in drawings.items():
                # One file when the accent makes no difference to this drawing.
                if len(set(drawings.values())) == 1:
                    out = name + ".svg"
                else:
                    out = "%s-%s.svg" % (name, accent)
                with open(os.path.join(folder, pack, out), "wb") as handle:
                    handle.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mactahoe",
                        help="a checkout of MACTAHOE_REF from lib/steps.sh")
    parser.add_argument("--icon-themes",
                        help="an icons directory with every colour of each pack")
    opts = parser.parse_args()
    render_fonts()
    if opts.mactahoe:
        ship_pointers(opts.mactahoe)
    if opts.icon_themes:
        ship_icons(opts.icon_themes)


if __name__ == "__main__":
    main()
