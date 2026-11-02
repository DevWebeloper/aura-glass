# What is in here, and whose it is

The setup wizard runs before anything is installed, so the fonts, pointers and
icon packs it asks about are not on the machine yet. Fetching them to show a
preview would cost up to 90 MB for the fonts alone and a working network before
the first question is answered, so the wizard shows these instead.
`render_samples.py` rebuilds them. Nothing here is installed, so there is nothing
to uninstall.

The MIT licence in the repository root does not cover the third-party work below.

## `fonts/`: outlines of a few words

One JSON file per font, holding the outline of each short string the wizard shows
as an SVG path. No font file is distributed and nothing here can be installed or
typed with. That is why they are not subset fonts: Inter's licence would allow a
font file here, but SF Pro's would not, and the MiSans zip carries no licence text
to go by. They are outlines rather than pictures of text because no picture stayed
sharp: at 133% a 4× PNG was as soft as a 2× one.

| File | Font | Owner and licence |
|---|---|---|
| `inter.json` | Inter | The Inter Project Authors, SIL OFL 1.1 |
| `misans.json` | MiSans Latin | Xiaomi, MiSans licence (none in the zip) |
| `sf-pro.json` | SF Pro Display | Apple, Apple's font licence |

## `pointers/`: the packs' own arrow files

Each file is one pack's `cursors/default`, gzipped and otherwise byte for byte as
the pack ships it. That matters most for Moga, whose licence allows sharing but
not adapting. Each one stays under its own licence.

| Files | Pack | Author | Licence | Source |
|---|---|---|---|---|
| `moga-*.xcursor.gz` | Moga Neon | Moyash | CC BY-NC-ND | https://www.gnome-look.org/p/2302110 |
| `aosp.xcursor.gz` | AOSP cursors | Tech-Tac, from the Android Open Source Project | Apache 2.0 | https://github.com/Tech-Tac/aosp-cursors |
| `mactahoe.xcursor.gz` | MacTahoe | vinceliuice | GPL 3.0 | https://github.com/vinceliuice/MacTahoe-icon-theme |

The `moga-*` files are named for the Aura Glass accent that picks them
(`tools/moga_cursor.py` has the table): `moga-pink` is Moga Neon Rose, and so on.

## `icons/`: the packs' own drawings

Eight SVGs from each pack, copied as they come out of the pack's installer. A
`-<accent>` suffix means the accent changes that drawing; the file picked is the
colour the installer would pick for that accent (`accent_to_*` in
`lib/steps-assets.sh`).

| Folder | Pack | Author | Licence | Source |
|---|---|---|---|---|
| `reversal/` | Reversal | yeyushengfan258 | GPL 3.0 | https://github.com/yeyushengfan258/Reversal-icon-theme |
| `hatter/` | Hatter | Mibea | GPL 3.0 | https://github.com/Mibea/Hatter |
| `colloid/` | Colloid | vinceliuice | GPL 3.0 | https://github.com/vinceliuice/Colloid-icon-theme |
