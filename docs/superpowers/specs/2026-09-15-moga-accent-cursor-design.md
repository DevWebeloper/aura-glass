# Moga Accent Cursor Design

## Goal

Make Moga a supported Aura Glass pointer pack whose active colour follows the
same nine-value GNOME accent choice as the rest of the theme.

## Scope

`--cursors moga` is a first-class choice beside Adwaita, AOSP, MacTahoe and
Original. It installs and selects the official Moga Neon variant mapped to the
Aura Glass accent: `blue→Blue`, `teal→Cyan`, `green→Green`,
`yellow→Yellow`, `orange→Orange`, `red→Red`, `pink→Rose`,
`purple→Purple`, and `slate→Sky`. `--accent teal --cursors moga`, a later
accent-only apply, and the settings window therefore all reach the same
green/teal/etc. cursor without each caller implementing its own mapping.

The source artwork is the official **Moga Neon** Xcursor series by **Moyash**.
The installer discovers the selected published variant through the source page
metadata, verifies the published checksum against the exact supported release
before unpacking it, and keeps the downloaded archive in Aura Glass's user
cache. It does not commit third-party artwork to this repository or alter its
pixels.

## Architecture

`lib/steps-assets.sh` owns all Moga decisions:

1. `moga_cursor_theme` maps the resolved Aura Glass accent to the installed
   official Moga directory name.
2. `install_moga_cursors` selects the matching official archive, checks its
   fixed filename and published checksum against source metadata, then installs
   only that accent's Xcursor theme below `~/.local/share/icons`.
3. `apply_gsettings` selects `moga_cursor_theme "$ACCENT"` whenever the
   resolved cursor pack is `moga`.

A small standard-library Python resolver holds the accent-to-official-variant
mapping and validates the source metadata. It emits one selected archive name,
checksum and short-lived download URL for an explicit accent. It never edits
Xcursor binary data, so every cursor shape, hotspot, animation frame and pixel
is the artist's original release.

The installer downloads and copies only into per-user cache and icon paths.
It uses the existing backup/run conventions for replacement operations. The
uninstaller's assets scope and the settings window's asset inventory recognise
only the `Aura-Glass-Moga-` prefix, never a standalone Moga directory the user
installed from Moyash or another source.

## User Interfaces

The terminal wizard and GTK settings window gain a Moga row labeled as an
accent-following pointer. They emit only `--cursors moga`; the installer
remains the sole resolver. When the pointer selection stays Moga and the user
changes the accent, `Settings.flags_against` must also emit the cursor choice
so one apply switches both accent and pointer variant atomically.

## Attribution

README's cursor credits name **Moyash** as the Moga Neon creator and link to
the official profile at <https://www.pling.com/u/moyash>. The Moga option text
also identifies it as an official upstream variant selected for the Aura Glass
accent. The README must not claim Aura Glass created the artwork.

## Verification

A focused checker uses a static source-metadata fixture to assert every
supported Aura Glass accent selects the intended official filename, rejects a
missing, inactive or checksum-mismatched release, and leaves no opening for a
signed URL to select a different archive. A shell checker validates that the
installer, README, wizard, settings window, gsettings application, and
uninstall inventory all list the same `moga` option.

For live verification, run the supported installer path with `--cursors moga`
and an explicit accent, read back `cursor-theme`, change only the accent via
`--settings-only`, and read back the changed Moga theme name. Preserve the
existing cursor-size unless the user separately asks to change it.

## Non-goals

- No cursor colour picker or arbitrary custom hex input.
- No recolouring or modification of Moga's Xcursor artwork.
- No modification or deletion of externally installed Moga themes.
- No manual writes to generated GTK or theme CSS files.
- No light/dark cursor switching; this feature follows Aura Glass accent only.
