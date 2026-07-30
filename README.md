# tahoe-glass

A macOS Tahoe **glass** desktop for GNOME — one script, no root, works the same
on a mutable Arch system and a read-only atomic one.

This is a packaged version of a working desktop, not a fresh design. It installs
the [GNOME-macOS-Tahoe][tahoe] theme, the extensions that make it hold together,
a pinned dconf preset, and a set of CSS fixes that repair the parts of the theme
that were never finished — undersized text fields, buttons that render as plain
text, near-solid black popup menus, oversized quick-settings sliders, and window
controls that read as a novelty rather than a control.

```
GNOME Shell   48 · 49 · 50        (developed on 50.3)
session       Wayland preferred, X11 works with degraded blur
tested on     CachyOS · Bazzite (GNOME image)
```

---

## Install

```bash
git clone https://github.com/DevWebeloper/tahoe-glass.git
cd tahoe-glass
./install.sh
```

Then **log out and back in**. Extensions cannot be loaded into a running shell
on Wayland, so the top bar, the blur and the quick settings only appear on the
next session.

Have a look first if you like — nothing is written:

```bash
./install.sh --dry-run
```

### Options

| Flag | Effect |
|---|---|
| `--accent COLOR` | `blue teal green yellow orange red pink purple slate` (default `pink`) |
| `--extras` | also install Just Perfection, GNOME UI Tune, Space Bar, Dash to Dock |
| `--no-icons` | keep your icon theme |
| `--no-cursors` | keep your cursor theme |
| `--no-wm-buttons` | keep your titlebar button layout |
| `--no-deps` | never touch the package manager |
| `--force` | reinstall things already present |
| `-y`, `--yes` | answer yes to everything |
| `-n`, `--dry-run` | print what would happen |

The accent drives the whole desktop: the shell CSS uses `-st-accent-color` and
the GTK CSS uses `@accent_bg_color`, so switching accents in **Settings →
Appearance** afterwards re-colours the toggles, sliders, focus rings and
notification titles without touching a file. Only the icon theme is pinned at
install time, and that is one flag away from being changed.

---

## What it installs

**Theme** — [kayozxo/GNOME-macOS-Tahoe][tahoe] dark, plus its libadwaita
override, pinned to a known-good commit.

**Extensions** — [User Themes][ut] (loads the shell theme),
[Blur My Shell][bms] (the actual glass), [Open Bar][ob] (top-bar geometry, menu
and notification radii). Optional with `--extras`: Just Perfection, GNOME UI
Tune, Space Bar, Dash to Dock.

**Icons and cursors** — [Colloid][colloid] in your accent colour, and the
[MacTahoe][mactahoe] cursors. Both install to `~/.local/share/icons`.

**A dconf preset** — the Blur My Shell pipelines and the Open Bar geometry that
this look depends on. Machine-specific keys are stripped out of the preset:
wallpaper URIs, the wallpaper-derived colour palette, monitor dimensions and
Open Bar's usage counters are all regenerated on first run.

**CSS tweaks** — three sheets, appended to the generated theme files inside a
marked block. This is the part you cannot get from any of the upstreams:

- Quick Settings sliders as macOS capsules instead of 1.6em-padded rows
- text fields with real metrics, a visible edge and an accent focus ring
- buttons that look like buttons, dropdowns that look like dropdowns
- popup menus on the same translucent material as the rest of the shell,
  with an even perimeter hairline instead of a bright top-left corner streak
- notifications that sit *on* the calendar popup rather than punching a hole
  through it, with the app name in the accent
- monochrome window controls — close is the only one that earns colour, and
  only under the pointer
- Adwaita-native switches, checks, radios and sliders, with the theme's
  1.8× knob-pop removed

Every rule carries a comment saying what upstream did and why it was changed,
so you can read `css/` and disagree with any of it.

**A Flatpak override** — read-only access to `~/.config/gtk-4.0`,
`~/.config/gtk-3.0`, `~/.local/share/themes` and `~/.local/share/icons`.
Without this a Flatpak app is sandboxed away from the GTK config and silently
keeps stock Adwaita, which looks exactly like the install having failed.

**A systemd user unit** (opt-in, `--panel-blur-fix`) — see *Panel blur* below.

---

## Atomic systems (Bazzite, Bluefin, Silverblue)

Every asset installs under `$HOME`. `~/.themes`, `~/.local/share/icons` and
`~/.local/share/gnome-shell/extensions` are ordinary writable directories that
GNOME reads exactly like the `/usr` ones, so nothing needs layering and nothing
needs a reboot.

The one dependency that is usually missing is `sassc`, which the Tahoe theme
uses to compile its SCSS. The installer offers Homebrew for it — Bazzite and
Bluefin ship `brew`, it installs into `/home/linuxbrew`, and it costs no reboot.
Layering (`rpm-ostree install sassc`) works too, but you have to reboot before
the install can continue, so it is only suggested as a fallback.

**Bazzite ships KDE by default.** This is a GNOME theme; you need the
`bazzite-gnome` image. The installer checks `XDG_CURRENT_DESKTOP` and stops
rather than scattering files into a session that will never read them.

---

## After installing

```bash
tahoe-glass-apply     # re-apply the CSS
./uninstall.sh        # put everything back
```

Run `tahoe-glass-apply` **after any theme update**. All four CSS targets are
generated files, so re-running the theme's own installer overwrites them and
drops the tweaks. The command is idempotent — the existing block is replaced,
never stacked.

If `~/.local/bin` is not on your `PATH`:

```bash
fish_add_path ~/.local/bin                # fish
export PATH="$HOME/.local/bin:$PATH"      # bash / zsh
```

---

## Troubleshooting

**Flatpak apps still look like stock Adwaita.**
They are sandboxed away from `~/.config/gtk-4.0`. The installer grants access,
but an app that was already running keeps its old style until restarted. To
check the override is there: `flatpak override --user --show`.

**A GTK app didn't change.**
GTK reads its CSS at startup. Restart the app.

**The left ~40% of the top bar has a mismatched strip after login.**
Blur My Shell builds one background actor per monitor and clips it to the
panel's geometry, which isn't settled at login — its own source notes that
`get_transformed_position` "sometimes yields NaN when the actor is not fully
positionned yet".

Only seen on multi-monitor, so it is **off by default** — the fix costs a 12
second wait after every login, which is not worth paying for a bug you probably
don't have. If you do see the strip, run the installer with `--panel-blur-fix`
to get `tahoe-glass-panel-blur.service`, which toggles the blur off and on once
the session has settled and rebuilds the actor against correct geometry. If the
strip survives that, your session takes longer to settle: raise the first
`sleep` in `~/.config/systemd/user/tahoe-glass-panel-blur.service`, then
`systemctl --user daemon-reload`.

Re-running the installer without `--panel-blur-fix` removes the unit again.

**Open Bar on GNOME 50.**
There is no GNOME 50 release. The installer builds it from upstream's last
commit plus `patches/openbar-gnome50.patch` — metadata, null guards, and the
GTK4/libadwaita prefs layout. On GNOME 49 and below the published build is used
unchanged. If the patch stops applying, upstream has moved and the pin in
`lib/steps.sh` needs bumping.

**The top bar font looks wrong.**
The preset asks for `SF Pro Display Bold 10`. SF Pro is Apple's, is not
redistributable, and is not installed by this project — without it fontconfig
substitutes your default sans, which is what the reference desktop does too.
Change it in Open Bar's preferences if you want something deliberate.

**There is no real blur behind popup menus.**
There cannot be, from CSS. St — the GNOME Shell CSS engine — has no blur
property at all, and Blur My Shell has no popup component. What you get instead
is frosted translucency on a consistent material ladder. True backdrop blur
behind menus needs a `Shell.BlurEffect` extension, which is a different project.

---

## How it fits together

```
install.sh              entry point, flag parsing, step order
lib/common.sh           output, prompting, pinned-clone and backup helpers
lib/distro.sh           distro detection and dependency install per family
lib/steps.sh            the steps themselves, with the upstream pins at the top
css/                    the three CSS sheets
dconf/core.ini          Open Bar + Blur My Shell + shell theme name
dconf/extras.ini        optional extensions
patches/                Open Bar GNOME 50 patch
systemd/                the panel blur rebuild unit
bin/tahoe-glass-apply   idempotent CSS re-apply
```

Upstream commits are pinned in `lib/steps.sh`. They are all moving targets, and
a theme that changes under the CSS is how you get a half-applied look with no
error to explain it.

---

## Uninstall

```bash
./uninstall.sh                  # CSS, dconf preset, settings, systemd unit
./uninstall.sh --all            # also the extensions, theme, icons and cursors
```

The installer only ever appends to generated files inside a marked block, and
keeps a first-run copy of anything it overwrites in
`~/.config/tahoe-glass/backups`. Extensions are left installed unless you ask,
because removing one also throws away its settings.

Take your own snapshot first if you have a desktop worth keeping:

```bash
dconf dump / > ~/dconf-backup.ini      # restore with: dconf load / < ~/dconf-backup.ini
```

---

## Credits

The parts that aren't mine, and the people who made them:

- [kayozxo/GNOME-macOS-Tahoe][tahoe] — the theme
- [aunetx/blur-my-shell][bms] — the blur
- [neuromorph/openbar][ob] — the top bar and menu geometry
- [vinceliuice/Colloid-icon-theme][colloid] and
  [vinceliuice/MacTahoe-icon-theme][mactahoe] — icons and cursors

MIT, for the parts in this repository. The upstreams carry their own licences.

[tahoe]: https://github.com/kayozxo/GNOME-macOS-Tahoe
[bms]: https://github.com/aunetx/blur-my-shell
[ob]: https://github.com/neuromorph/openbar
[ut]: https://extensions.gnome.org/extension/19/user-themes/
[colloid]: https://github.com/vinceliuice/Colloid-icon-theme
[mactahoe]: https://github.com/vinceliuice/MacTahoe-icon-theme
