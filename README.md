# tahoe-glass

A macOS Tahoe **glass** desktop for GNOME — one script, and nothing but the
optional dependency install ever needs root.

This is a packaged version of a working desktop, not a fresh design. It installs
the [GNOME-macOS-Tahoe][tahoe] theme, the extensions that make it hold together,
a pinned dconf preset, and a set of CSS fixes that repair the parts of the theme
that were never finished — undersized text fields, buttons that render as plain
text, near-solid black popup menus, oversized quick-settings sliders, and window
controls that read as a novelty rather than a control.

```
GNOME Shell   48 · 49 · 50        (developed on 50.3)
session       Wayland preferred, X11 works with degraded blur
tested on     CachyOS (Arch family)
```

---

## Install

```bash
git clone https://github.com/DevWebeloper/tahoe-glass.git
cd tahoe-glass
./install.sh --full
```

`--full` turns on every optional piece at once. On a fresh machine that makes
it identical to `--extras`, because the other things it asserts — icons,
cursors, titlebar buttons, the OSD, the panel blur fix — are already on by
default. What it is really for is a re-install: it undoes an earlier `--no-*`
in one flag rather than making you remember which ones you turned off. Plain
`./install.sh` installs the core look only and leaves the optional extensions
out.

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
| `--accent COLOR` | `blue teal green yellow orange red pink purple slate` (default `pink`, and remembered for later runs) |
| `--full` | every optional piece at once — `--extras`, plus re-asserting the icons, cursors, titlebar buttons, OSD and panel-blur-fix defaults |
| `--extras` | also install the rest of the reference desktop — see below |
| `--icons WHICH` | `colloid` (default, follows `--accent`) or `reversal-COLOUR` |
| `--cursors WHICH` | `adwaita` (default) or `mactahoe` |
| `--app-transparency N` | translucent app windows, `0.70`–`1.00` (default `0.92`). Off unless asked for |
| `--no-osd` | keep the stock volume/brightness popup |
| `--no-blur` | no blur anywhere, opaque surfaces instead of translucent — see *Without blur* |
| `--no-popup-blur` | keep flat translucent popups, no blur behind them |
| `--no-rounded-blur` | skip `gnome-rounded-blur` — popup blur stays static |
| `--no-bms-git` | use Blur My Shell's published build (no popup component) |
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

The accent you install with is remembered, like `--icons` and `--grain` are.
The installer rewrites `accent-color` on every run, so without that a flagless
re-install would quietly re-theme a desktop running any other accent back to
the default.

---

## What it installs

**Theme** — [kayozxo/GNOME-macOS-Tahoe][tahoe] dark, plus its libadwaita
override, pinned to a known-good commit.

**Extensions** — [User Themes][ut] (loads the shell theme),
[Blur My Shell][bms] (the actual glass), [Open Bar][ob] (top-bar geometry, menu
and notification radii), [Custom OSD][cosd] (the volume and brightness popup —
see below).

`--extras` adds the rest of the reference desktop: Just Perfection, GNOME UI
Tune, Space Bar, Auto Accent Colour, Vitals, Clipboard Indicator, ddterm,
Kiwi Menu, HotEdge, Restart To, XWayland Indicator, AppIndicator Support,
Magic Lamp Effect and Add to Steam.

Some of those may already be packaged by your distro. The installer looks in
`/usr/share/gnome-shell/extensions` before it downloads anything, so those are
enabled where they are rather than shadowed by a second copy under `$HOME` that
would drift from the packaged one.

**Icons and cursors** — [Colloid][colloid] in your accent colour, installed to
`~/.local/share/icons`. Cursors are GNOME's own Adwaita by default; pass
`--cursors mactahoe` for the [MacTahoe][mactahoe] set instead.

Colloid ships a `-Light` and a `-Dark` build of every accent, but GNOME's
`icon-theme` key holds one name and knows nothing about the pair — so
switching **Settings → Appearance** to Light would restyle everything except
the icons. `tahoe-glass-icon-sync.service` watches the colour scheme and keeps
the key pointing at the matching variant.

### Popup blur

Menus, quick settings, notifications, dialogs, the alt-tab switcher and the
volume/brightness OSD all sit on a real blur.

This is why Blur My Shell is built from a pinned commit rather than taken from
extensions.gnome.org: the popup component only exists on upstream's `master`,
and no release carries it yet. When one does, this project will go back to the
published build.

There are two modes, and the difference is what the blur samples:

- **dynamic** — whatever is actually behind the popup. This is the default, and
  it needs [`gnome-rounded-blur`][roundedblur], a small C library that gives
  Blur My Shell's dynamic blur a corner mask. Without it the blur still works
  but the corners come out square.
- **static** — the wallpaper, blurred once. Needs nothing extra, and rounds its
  own corners.

The installer picks between them from Blur My Shell's own `rounded-blur-found`
key rather than assuming: library present means dynamic, absent means static.
So declining the library, or a mutter update breaking it, costs you *what the
blur samples* rather than the shape — round over the wallpaper, instead of
square over the window. Re-run `./install.sh --rounded-blur --force` to rebuild
it and the mode flips back on its own.

`gnome-rounded-blur` is the only thing this project installs outside `$HOME`,
so it is the only step that asks first — and it asks even under `--yes`. It is
compiled against your current mutter and has to be rebuilt after a mutter
update; the installer notices that case and says so.

`--no-popup-blur` reverts to the flat translucent popups this project shipped
before, exactly.

### Without blur

```bash
./install.sh --full --no-blur
```

Blur is the only part of this desktop that costs real GPU time, and the cost is
not spread evenly. Blur My Shell attaches a Gaussian shader per surface; the
panel's is the only one that is both always visible and always active, since
every other pipeline exists for the seconds a menu, the overview or the OSD is
open. On top of that the preset runs `hacks-level=2`, which turns off clipped
redraws — it has to, or blur actors go stale when what is behind them moves —
and the cost of that is a full-screen repaint every frame, for everything.

On a discrete card that is affordable. On an Intel iGPU, an older discrete card,
or a laptop trying to stay awake on battery, it is the difference between a
desktop that feels light and one that does not.

**`--no-blur` is not the glass look with the blur switched off.** Translucency
and blur are one effect: take the blur away and the same translucent fills read
as a smeared window rather than as glass, which is worse than either. So this
mode swaps the whole ladder for opaque surfaces on the same geometry.

What is kept: every radius and every spacing, the flat pass, the accent, the
icons and cursors, the monochrome window controls, the Adwaita-native switches
and sliders, the Quick Settings capsules, the OSD reduced to its level bar.
What is lost: depth. Nothing else.

Blur My Shell is not installed and not enabled in this mode. Disabling its
components would leave the extension loaded and still building one background
actor per surface; leaving it out is what actually removes the cost.

Measured over the same scripted sequence in the preview harness, on a Radeon
RX 7600. Absolute numbers move a lot with whatever else the machine is doing,
so what is worth quoting is the ratio, which held across two sessions with very
different baselines:

| | glass | `--no-blur` |
|---|---|---|
| p90 GPU busy, session A | 19% | 13% |
| p90 GPU busy, session B | 28-31% | 18-22% |

That is `--no-blur` costing about **70% of what glass costs**, both times. The
maximum is unchanged between modes because it is app startup rather than blur.

Two caveats worth having. This is a headless render, which does not pay the
continuous repaint cost a real display does, so it is a floor. And the saving
comes from Blur My Shell not running at all — lowering the panel's sigma from
30 to 20 produced no measurable change over three runs, with the run-to-run
noise larger than the effect. Tuning the blur is not the lever; not running it
is.

To go back, reinstall without the flag: `./install.sh --full`.

### App transparency

Blur My Shell can blur behind app windows, but libadwaita paints opaque
backgrounds, so by default there is nothing to see through. `--app-transparency`
makes the surfaces libadwaita actually paints translucent — the window, header
bar, sidebar panes, content views and popovers.

Blur My Shell's window blur follows this flag rather than being on by default,
because it is the flag that gives it anything to reveal. That blur paints behind
every window and rebuilds as the window moves, while the window sits at 94%
opacity — so with transparency off it was expensive and all but invisible.
Measured on the live session, overview toggled six times on a Radeon RX 7600:
p90 GPU busy **99% with it on, 28% with it off**, and it is on only when you ask
for transparency now.

It is **off by default and not part of `--full`**, because it only works for
apps that use GTK's stylesheet. These will ignore it and stay opaque:

- Electron and Chromium apps — VS Code, Discord, Slack, Brave
- Steam, Java/Swing apps, LibreOffice
- anything drawing a GL or video surface — mpv, Totem's video widget
- XWayland apps generally, and GTK3 apps

Message dialogs and windows with server-side decorations are deliberately left
opaque: a translucent dialog is harder to read, and a translucent window under
an opaque frame reads as a rendering bug.

Any app that looks wrong can be added to Blur My Shell's per-app blacklist.

### The volume and brightness popup

Stock GNOME shows a speaker icon, the output device's name and a bar every time
you touch the volume keys. tahoe-glass drops the icon and the name and keeps
the bar, on a translucent pill with the wallpaper blurred behind it. Brightness
gets the same treatment — both go through the same shell class, so there is
only one thing to configure.

It is [Custom OSD][cosd] doing the work, so everything stays adjustable from a
window: **Extensions → Custom OSD → Settings**. Position, size, hide delay,
colours, corner radius and which parts show are all there, and the preset is
saved as its `Default` profile so the Profiles page reproduces this look rather
than reverting to upstream's.

Upstream's last release targets GNOME 46 and its last commit does not run on
50 at all — `ShellBlurEffect:sigma`, `meta_add_clutter_debug_flags()` and
`OsdWindowManager.show()`'s signature have all changed since. `patches/custom-osd-gnome50.patch`
fixes exactly those and nothing else.

The blur behind the pill, and its rounded corners, come from Blur My Shell's
popup component instead — `osd-window` is one of the surfaces it blurs. This
project used to carry its own corner shader for that job, and it was the most
fragile code here: a `Clutter.ShaderEffect` gets an offscreen buffer sized to
the actor's *paint volume* rather than its allocation, which rendered a rounded
pill on one GPU and a hard square on another. Blur My Shell's own corner effect
clamps the radius instead, so the shape comes out right without this project
maintaining a shader. The preset therefore ships `bg-effect='none'`.

Pass `--no-osd` to leave the stock popup alone.

### Custom colours

**Settings → Appearance cannot take custom swatches.** Its nine accents are
compiled into gnome-control-center; no extension can add to that list, and the
only way to change it is to patch and rebuild the app — which comes undone at
every GNOME update. Not worth it.

For arbitrary colours, use the two layers that *are* designed to be changed:

- **Open Bar → Settings** has RGB pickers for the bar, menu, highlight and
  border colours. This is where the shipped look comes from, and it can also
  derive a whole palette from the current wallpaper.
- **Auto Accent Colour** (installed with `--extras`) keeps GNOME's own accent
  tracking the wallpaper, so the parts that read the accent stay in step.

Both are GUI, and neither needs the terminal or a rebuilt package.

**A dconf preset** — the Blur My Shell pipelines and the Open Bar geometry that
this look depends on. Machine-specific keys are stripped out of the preset:
wallpaper URIs, the wallpaper-derived colour palette, monitor dimensions and
Open Bar's usage counters are all regenerated on first run.

**CSS tweaks** — a set of sheets, one per concern, concatenated in cascade order
and appended to the generated theme files inside a marked block. This is the
part you cannot get from any of the upstreams:

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

## Where things land

Every asset installs under `$HOME`. `~/.themes`, `~/.local/share/icons` and
`~/.local/share/gnome-shell/extensions` are ordinary writable directories that
GNOME reads exactly like the `/usr` ones, so no step scatters files into system
directories and none of them needs root.

The one dependency that is usually missing is `sassc`, which the Tahoe theme
uses to compile its SCSS. The installer prints the exact `pacman` line and asks
before running it.

This is a GNOME theme. The installer checks `XDG_CURRENT_DESKTOP` and stops
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

Only seen on multi-monitor. The fix is **on by default** and costs a 12
second wait after every login; pass `--no-panel-blur-fix` to skip it for a bug you probably
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

**The popup blur shows the wallpaper, not the window behind it.**
That is static blur, and it means `gnome-rounded-blur` is missing or has gone
stale. See *Popup blur* above; `./install.sh --rounded-blur` fixes it. The
installer says so on its own if it detects that case.

---

## How it fits together

```
install.sh              entry point, flag parsing, step order
lib/common.sh           output, prompting, pinned-clone and backup helpers
lib/distro.sh           distro detection and dependency install per family
lib/steps.sh            the upstream pins, the paths, preflight, the theme
lib/steps-extensions.sh  every extension, and the rounded-blur library
lib/steps-assets.sh      icon and cursor themes
lib/steps-css.sh         the CSS tweaks and the display-density correction
lib/steps-dconf.sh       the dconf preset, and the gsettings beside it
lib/steps-integration.sh icon-sync agent, Flatpak override, panel blur unit
css/shell-NN-*.css      the shell sheets, in cascade order — see below
css/gtk4-NN-*.css       the GTK4 sheets, likewise
css/gtk3-tweaks.css     GTK3, which is small enough to stay one file
tokens/tokens.sh        every value that is written down in more than one place
dconf/core.ini          Open Bar + Blur My Shell + Custom OSD + shell theme name
dconf/solid.ini         the --no-blur overlay, applied on top of core.ini
dconf/extras.ini        optional extensions
patches/                the GNOME 50 patches for Open Bar and Custom OSD
systemd/                the panel blur rebuild unit
bin/tahoe-glass-apply   idempotent CSS re-apply
tools/                  development only, never installed — see below
tools/hooks/            the pre-commit hook, enabled by tools/install-hooks.sh
```

**The numeric prefix on a sheet is its cascade position, not decoration.**
`tahoe-glass-apply` concatenates them in that order into one block, and several
rules here are meant to override each other on equal specificity: the dropdown
radius beats the button radius it follows, the accent slider fill beats the
white one. Put a new sheet at the position its cascade needs.

---

## Developing

None of this is installed. It exists so that a change can be looked at before it
is lived with.

```bash
tools/preview.sh              render the working tree, screenshot it
tools/preview.sh --solid      the same, in --no-blur mode
tools/preview.sh --gpu        sample GPU busy% over the run
tools/preview.sh --gtk-only nautilus    one GTK app + the inspector, no shell
tools/check-tokens.sh         assert tokens/tokens.sh still matches every file
tools/check-cascade.sh        assert every sheet in css/ is installed and applied
tools/check-shots.py --accept adopt this preview run as the visual baseline
tools/install-hooks.sh        run all of the above before every commit
tools/gpu-sample.py --probe   say what this machine can measure
```

`preview.sh` builds a throwaway profile from the installed theme plus this
tree's CSS, runs a real GNOME Shell against it with the real extensions, opens
the menus, notifications and OSD that an idle desktop never shows, and leaves
eight PNGs in `screenshots/preview/`. It takes about a minute, and it does not
touch the session you are sitting in: `HOME`, the XDG directories and the D-Bus
bus are all redirected, and settings go through GLib's keyfile backend rather
than dconf so a preset cannot reach the live database at all.

It is a headless render, not a window to click around in — mutter has no nested
backend compiled in on Arch, so a shell started inside your session tries to
take the seat and dies. The long comment at the top of `tools/preview.sh`
explains the rest.

`check-tokens.sh` is the reason a radius in a stylesheet and the same radius in
a dconf key cannot drift apart any more. Run it after changing either. It fails
on a check that has stopped matching anything, not just on a wrong value.

`check-cascade.sh` covers the other half of that problem. Which sheets get
*installed* is a glob in `lib/steps-css.sh`; which sheets get *applied* is a
hand-written array in `bin/tahoe-glass-apply`; and the two are edited at
different moments. So a new sheet could be copied into `$CONF_DIR`, appear in a
preview, and still never be applied, with nothing to say so. It also asserts
the arrays run in ascending prefix order, since the prefix *is* the cascade
position, and that no two sheets claim the same one.

The arrays cannot just be replaced by a sorted glob, which is why they are
checked instead: `shell-popup-blur.css` has to land after `shell-90-density.css`,
and `9` sorts before `p`.

`check-shots.py` compares a preview run against the last one you accepted, so
"I changed one sheet, what else moved?" has an answer. Glass and solid keep
separate baselines — they are *meant* to look different, and one baseline for
both would flag every mode switch until you stopped reading it. Baselines live
in `~/.cache/tahoe-glass/baseline`, not in the repository: they are 1080p PNGs
that would need regenerating on most commits here. It needs Pillow, and says so
rather than failing when that is missing.

`install-hooks.sh` points `core.hooksPath` at `tools/hooks`, so both checks and
a syntax pass run before every commit. It checks the **staged** tree rather than
the working tree — this project stages explicitly rather than `git add -A`, so
those are routinely different, and checking the working tree would block a good
commit over an unrelated file being mid-edit.

Upstream commits are pinned in `lib/steps.sh`. They are all moving targets, and
a theme that changes under the CSS is how you get a half-applied look with no
error to explain it.

---

## Uninstall

```bash
./uninstall.sh                  # CSS, dconf preset, settings, systemd unit
./uninstall.sh --all            # also the extensions, theme, icons and cursors
```

The installer writes its CSS into generated files inside a marked block, and
additionally flattens those files in place — the theme's own shadow and gradient
values are rewritten to `none`, which is how the desktop stays flat without a
cascade fight. Both are undone by `./uninstall.sh`, which restores a first-run
copy of every file it touched from `~/.config/tahoe-glass/backups`. Extensions
are left installed unless you ask, because removing one also throws away its
settings.

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
- [neuromorph/custom-osd][cosd] — the volume and brightness popup
- [vinceliuice/Colloid-icon-theme][colloid] and
  [vinceliuice/MacTahoe-icon-theme][mactahoe] — icons and cursors

MIT, for the parts in this repository. The upstreams carry their own licences.

[tahoe]: https://github.com/kayozxo/GNOME-macOS-Tahoe
[bms]: https://github.com/aunetx/blur-my-shell
[roundedblur]: https://github.com/kancko/gnome-rounded-blur
[ob]: https://github.com/neuromorph/openbar
[cosd]: https://github.com/neuromorph/custom-osd
[ut]: https://extensions.gnome.org/extension/19/user-themes/
[colloid]: https://github.com/vinceliuice/Colloid-icon-theme
[mactahoe]: https://github.com/vinceliuice/MacTahoe-icon-theme
