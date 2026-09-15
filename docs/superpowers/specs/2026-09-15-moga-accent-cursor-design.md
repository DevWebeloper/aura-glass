# Moga Accent Cursor Design

## Goal

Make Moga a supported Aura Glass pointer pack whose active colour follows the
same nine-value GNOME accent choice as the rest of the theme.

## Scope

`--cursors moga` is a first-class choice beside Adwaita, AOSP, MacTahoe and
Original. It produces and selects a per-accent Xcursor theme named
`Aura-Glass-Moga-<Accent>`; `--accent teal --cursors moga`, a later accent-only
apply, and the settings window therefore all reach the same green/teal/etc.
cursor without each caller implementing its own mapping.

The source artwork is the official **Moga Neon Purple** Xcursor archive by
**Moyash**. The installer discovers the published archive through the source
page metadata, verifies its recorded checksum before unpacking it, and keeps
both the downloaded archive and the untouched template in Aura Glass's user
cache. It does not commit third-party artwork to this repository.

## Architecture

`lib/steps-assets.sh` owns all Moga decisions:

1. `moga_cursor_theme` maps the resolved Aura Glass accent to the generated
   directory name.
2. `install_moga_cursors` fetches and validates the Moga Neon Purple template
   once, builds every supported accent variant below
   `~/.local/share/icons`, and never mutates the upstream template.
3. `apply_gsettings` selects `moga_cursor_theme "$ACCENT"` whenever the
   resolved cursor pack is `moga`.

A small standard-library Python tool parses standard Xcursor image chunks and
rewrites their premultiplied ARGB pixels. It preserves chunk headers, image
sizes, frame delays, hotspots, alpha, aliases, and cursor names. The colour
transform replaces the neon-purple hue while retaining each pixel's lightness
and opacity, so every animation frame and contrast edge remains the original
Moga artwork. The tool accepts only explicit source/destination paths and an
Aura Glass accent name; it never reads or writes arbitrary desktop themes.

The installer downloads and copies only into per-user cache and icon paths.
It uses the existing backup/run conventions for replacement operations. The
uninstaller's assets scope and the settings window's asset inventory recognise
the `Aura-Glass-Moga-` prefix, but never offer to delete Moyash's original
`Moga-Neon-Purple` directory or another user-installed Moga variant.

## User Interfaces

The terminal wizard and GTK settings window gain a Moga row labeled as an
accent-following pointer. They emit only `--cursors moga`; the installer
remains the sole resolver. When the pointer selection stays Moga and the user
changes the accent, `Settings.flags_against` must also emit the cursor choice
so one apply switches both accent and pointer variant atomically.

## Attribution

README's cursor credits name **Moyash** as the Moga Neon creator and link to
the official profile at <https://www.pling.com/u/moyash>. The Moga option text
also identifies it as upstream artwork recoloured locally for Aura Glass
accents. The README must not claim Aura Glass created the artwork.

## Verification

A focused checker builds a minimal synthetic Xcursor containing static and
animated image chunks, runs the recolour tool, and asserts that structure,
hotspots, delays, alpha, and non-colour metadata survive while the intended
neon hue changes. A shell checker validates every supported Aura Glass accent
maps to a distinct Moga directory and checks that the installer, README,
wizard, settings window, gsettings application, and uninstall inventory all
list the same `moga` option.

For live verification, run the supported installer path with `--cursors moga`
and an explicit accent, read back `cursor-theme`, change only the accent via
`--settings-only`, and read back the changed Moga theme name. Preserve the
existing cursor-size unless the user separately asks to change it.

## Non-goals

- No cursor colour picker or arbitrary custom hex input.
- No modification or deletion of externally installed Moga themes.
- No manual writes to generated GTK or theme CSS files.
- No light/dark cursor switching; this feature follows Aura Glass accent only.
