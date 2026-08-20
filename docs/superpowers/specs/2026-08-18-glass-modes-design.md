# Glass modes: frosted, transparent, solid

Date: 2026-08-18
Status: approved for planning

## Problem

The Glass page is a flat list of switches whose legal combinations are not
obvious. `Frosted glass` off means solid mode; window blur, all-apps blur,
translucency, opacity and popup blur each stand alone, and several combinations
are meaningless (an opacity slider under a solid desktop, an all-apps switch
with no window blur to widen). The three ways people actually want to run the
theme are already in there, but the user has to assemble each one.

There is also no way to stand the theme down temporarily. Someone whose GPU or
whose app is unhappy has one option today — `./uninstall.sh` — which is a
one-way door, and reinstalling is the way back.

## What we are building

Three named modes, presented as three tabs on the Glass page. The tab is the
mode; every control inside a tab belongs to that mode.

| | frosted | transparent | solid |
|---|---|---|---|
| blur behind windows | yes, `gtk` or `all` | no | no |
| blur behind popups, menus, panel | switch, default on | switch, default on | no |
| translucent app windows | switch, with opacity | always on, with opacity | no |
| tint (app + shell) | yes | yes | — |
| blur strength | yes | yes, but only the popups and panel are blurred | — |
| the theme's styling | applied | applied | **stood down** |
| icon and cursor packs, accent | kept | kept | kept |

Solid is not a look. It is the theme standing down: the CSS block comes out,
the shell goes back to GNOME's own theme, and the extensions aura-glass enabled
are disabled without their settings being touched. The packs, the accent and
every memo stay, so coming back is one Apply.

## Design

### The mode is a real setting

`--glass-mode frosted|transparent|solid`, remembered in
`$CONF_DIR/glass-mode`. The mode resolves into the flags install.sh already
has, so nothing downstream learns a new vocabulary:

- `frosted` — `WANT_BLUR=1`, `WANT_WINDOW_BLUR=1`, `APP_BLUR_SCOPE` from the
  mode's memo, popup blur from the mode's memo, transparency from the mode's
  memo, styling on.
- `transparent` — `WANT_BLUR=1` (the translucent sheets stay; they are what
  makes this mode), `WANT_WINDOW_BLUR=0` and `APP_BLUR_SCOPE=none`, popup blur
  from the mode's memo, transparency from the mode's memo, styling on.
- `solid` — `WANT_BLUR=0`, `WANT_WINDOW_BLUR=0`, `WANT_POPUP_BLUR=0`,
  `WANT_ROUNDED_BLUR=0`, `APP_TRANSPARENCY=0`, **styling off** (below).

Precedence: an explicit blur flag given alongside `--glass-mode` wins over what
the mode would have resolved to, on the same rule the rest of install.sh
follows — a flag the user typed beats a value that was inferred. The one
exception install.sh already enforces stays: `--no-blur` with `--window-blur`
is a hard error, and `--glass-mode solid --window-blur` is the same error.

A run with no `--glass-mode` and no blur flags takes the remembered mode. A run
with blur flags and no `--glass-mode` derives the mode from the flags
(`WANT_BLUR=0` → solid; window blur off with transparency on → transparent;
otherwise frosted) and writes it, so a CLI user who never says "mode" still
opens the window on the right tab.

### Per-mode memory

`$CONF_DIR/modes/<mode>/` holds the settings that belong to that mode:

```
modes/frosted/app-transparency      modes/transparent/app-transparency
modes/frosted/app-tint-color        modes/transparent/app-tint-color
modes/frosted/shell-tint-color      modes/transparent/shell-tint-color
modes/frosted/blur-strength         modes/transparent/blur-strength
modes/frosted/app-blur-scope        modes/transparent/popup-blur
modes/frosted/popup-blur
modes/solid/disabled-extensions
```

The existing top-level memos (`app-transparency`, `app-tint-color`, …) keep
being written with whatever the active mode resolved to. They stay the live
state, so every existing reader — `Settings.__init__` in the window,
`install_transparency_css`, `apply_shell_tint_color`, the preview tools —
carries on unchanged. The per-mode files are the archive the mode switch reads
from, not a second source of truth.

First entry into a mode with no directory yet seeds it — from the current
top-level memos where they exist, so an install that predates this change keeps
exactly the tuning it is wearing and finds it in the tab it belongs to, and from
these constants only where there is no memo to read:

- frosted — today's shipped answers: transparency off, tints `#000000`, blur
  strength `100`, scope `gtk`, popup blur on.
- transparent — the same two controls, seeded darker because there is no blur
  behind the window to hold text up: transparency `0.82`, tints `#0b0b0f`,
  blur strength `100`, popup blur on. Transparency is on by definition here —
  the mode has no "off", only a level.

Seeded, not enforced. Both values are the ordinary Opacity and Tint controls
inside that tab and the user moves them wherever they like; the mode only
decides what they start at.

### Solid: standing the styling down

A marker, `$CONF_DIR/styling-off`, written by install.sh when the mode is solid
and removed when it is not. Three things read it.

**1. `bin/aura-glass-apply`.** With the marker present it strips rather than
splices: the `>>> aura-glass BEGIN/END <<<` block comes out of all four
targets, and the files with a backup are restored from `$CONF_DIR/backups`
rather than merely un-blocked —

- `gnome-shell.css` must be restored: flattening rewrote the theme's own shadow
  and gradient values in place, so a stripped-but-not-restored sheet is still a
  flattened one.
- `gtk-4.0/gtk.css` and `gtk-dark.css` follow the rule `restore()` in
  uninstall.sh already uses: `.orig` if there is one, remove if there is an
  `.absent` marker (the file existed only because the theme's installer made
  it), skip otherwise.

`install_css` still lays the sheets down in `$CONF_DIR` in solid mode; nothing
splices them, so they cost nothing and are there the moment the marker goes.

**2. `apply_gsettings`.** In solid mode, `gtk-theme` is reset and the user-theme
shell name is set to `''`, which is what puts the stock shell back. `accent-
color`, `icon-theme` and `cursor-theme` are left exactly as they are — the
packs stay, as does the accent. Leaving solid sets `gtk-theme=Tahoe-Dark` and
the user-theme name back to `Tahoe-Dark`.

**3. Extension handling.** Entering solid:

```
enabled  := gnome-extensions list --enabled
ours     := EXT_CORE + EXT_EXTRA_ALL + openbar@neuromorph
            + $BMS_UUID + custom-osd@neuromorph
record   := enabled ∩ ours        -> modes/solid/disabled-extensions
for each in record: gnome-extensions disable
```

No `dconf reset` anywhere — the settings of every extension survive untouched,
which is the difference between this and `uninstall.sh`. Extensions the user
installed themselves are outside `ours` and are never touched.

Leaving solid re-enables exactly the recorded UUIDs (through the same
`enable_extensions` fallback path, so a UUID the running shell will not take is
queued into `enabled-extensions` for the next session), then deletes the record.
A UUID in the record that has since been uninstalled is skipped with a note
rather than being an error.

The rounded-blur library is root-owned and is left alone in both directions.

### The GUI

The Glass section becomes a `Gtk.Box`: an `Adw.ViewSwitcher` over an
`Adw.ViewStack` whose three children are `Adw.PreferencesPage`s.

- **Frosted** — today's page, unchanged: the GPU tip card, window blur,
  all-apps blur, translucency + opacity, popup blur, tint, blur strength.
- **Transparent** — opacity and tint, the same two controls bound to this
  mode's values, plus one switch: *Blur behind menus and the top bar*, and the
  blur strength bar beneath it, which in this mode reaches only the popups and
  the panel and says so. No window-blur rows at all, and no switch for
  translucency itself — turning it off is choosing a different mode. Its own note in place of the GPU card: with nothing
  blurred behind the window, the wallpaper is what the text sits on, which is
  why 70% is the floor.
- **Solid** — no controls. A description of what it turns off (the CSS block,
  the shell theme, the extensions aura-glass enabled) and what it keeps (icon
  and cursor packs, accent, every setting in the other two tabs), and that
  leaving the tab puts all of it back.

Switching tab makes the mode pending, exactly like moving any other control:
the dirty banner appears and **Apply** commits, **Revert** puts the tab back.
The applied mode is marked in the switcher so browsing is distinguishable from
choosing.

`Settings` grows a `glass_mode` field; `flags_against` emits `--glass-mode M`
when it differs, and stops emitting the blur flags the mode already implies —
otherwise Apply would send `--glass-mode solid --no-window-blur --no-popup-blur`
and say the same thing three times. Within a tab the ordinary flags are still
what moves: changing the opacity in transparent mode sends
`--app-transparency`, not a mode.

`_sync_sensitivity` loses most of its work — a control that does not apply to
the active mode is not dimmed, it is in another tab.

### Error handling

- `--glass-mode` with an unknown value dies with the list, the way
  `--radius-preset` does.
- `--glass-mode solid --window-blur` is the existing hard error, reworded.
- A `modes/<mode>/` directory holding a value install.sh would reject is
  treated as unseeded and reseeded, not sent onward.
- `gnome-extensions disable` failing for one UUID warns and continues; the
  record still lists it, so the trip back still tries to re-enable it.
- Leaving solid with no record file (someone deleted it, or solid was entered
  by a version before this) re-enables the set install.sh would have enabled
  anyway, which is `enable_extensions`'s normal job.

### Testing

- `tools/check-gui-flags.py` gains transitions for each mode pair — six of
  them — and each list is fed to `install.sh --settings-only --dry-run` as the
  existing cases are, so a mode that composes into an argument list the parser
  rejects fails there.
- A new `tools/check-glass-modes.sh`: for each mode, run `install.sh
  --settings-only --dry-run --glass-mode M` and assert the resolved
  `WANT_BLUR`/`WANT_WINDOW_BLUR`/`WANT_POPUP_BLUR`/`APP_TRANSPARENCY` match the
  table above; assert the per-mode memo round-trips; assert
  `--glass-mode solid --window-blur` exits non-zero.
- `bin/aura-glass-apply` with and without `styling-off` against a fixture
  `$CONF_DIR`: the marked block present in all four targets in one case, absent
  and the backups restored in the other, and both idempotent across two runs.
- The extension round trip is checked by hand — it needs a live shell.

## Out of scope

- The setup wizard's Step 2, which is still a two-way frosted/solid question.
  It should become the three modes, but that is its own change.
- Any change to what the sheets themselves contain. Transparent mode is the
  existing translucency with the window blur off, not a new stylesheet.
