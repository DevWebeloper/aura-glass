# aura-glass

> **A fluid, modern frosted-glass GNOME theme.**  
> Seamless dynamic blur, macOS-inspired ergonomics, pixel-perfect CSS fixes, and unified system theming — installed with a single command without root (root only required for optional GDM theming).

```
GNOME Shell   48 · 49 · 50 (tested on 50.3)
Session       Wayland preferred (X11 supported with fallback blur)
Compatibility Arch / CachyOS, Fedora, Ubuntu / Debian
```

---

## 🧪 Beta: GUI Update

[**v0.2.0-beta**][beta] is out — the new settings window, three glass modes, the first-run wizard, and installable interface fonts. It is a prerelease: expect rough edges, and stick to the [latest stable release][releases] if you would rather not hit them.

```bash
git clone https://github.com/DevWebeloper/aura-glass.git
cd aura-glass
git checkout v0.2.0-beta
./install.sh
```

[beta]: https://github.com/DevWebeloper/aura-glass/releases/tag/v0.2.0-beta
[releases]: https://github.com/DevWebeloper/aura-glass/releases

---

## ⚡ Quick Start

### 1. Install
Open your terminal and run:

```bash
git clone https://github.com/DevWebeloper/aura-glass.git
cd aura-glass
./install.sh
```

Running `./install.sh` launches an **interactive setup wizard** that lets you pick your preferences before anything is installed:
- 🎨 **Accent color** (Purple, Blue, Teal, Green, Yellow, Orange, Red, Pink, Slate)
- 🪟 **Blur & visual depth** (Frosted Glass vs. Lightweight Solid Mode)
- 💎 **App window transparency** (Off, 90% balanced, 82% deep, 94% subtle)
- 🖱️ **Icon and pointer packs**, each with a link to the project it comes from
- 🧩 **Extensions**, one switch each — or the recommended set in one click
- 🔒 **GDM login screen theme** (Optional matching blurred login screen)

The wizard opens in a **window**, with a Skip button on every question and nothing applied until you press Install. Close it and the install stops, having changed nothing. When it finishes, the window closes and the terminal carries on from there.

Where a window is not an option — over SSH, on a machine without PyGObject and libadwaita, or if you would simply rather not install them — the installer offers to fetch them once and otherwise asks **exactly the same questions in the terminal**. Either way the install completes.

> **Tip:** Prefer a dry run first? Run `./install.sh --dry-run` to preview all changes safely without modifying your system.

### 2. Log Out & Back In
GNOME Shell extensions and compositor settings take effect on the next session. Simply **log out and log back in** to enjoy your customized glass desktop!

### 3. Change Your Mind Later — Without the Terminal
Installing also puts an **Aura Glass** entry in your Activities overview (or run `aura-glass-settings`). It reads your current setup and lets you retune the parts worth revisiting:

- 🎨 **Accent color**, with a shortcut to GNOME's own `Settings → Appearance`
- ⬜ **Corner rounding** — six presets, each drawn as a little window carrying its own corners so you can see the difference before you pick it, a **Reset to default** beside them, or set each of the seven surfaces yourself: windows, menus, Quick Settings, notifications, dialogs, popups and the volume pill, each bounded to a range that has been looked at on a screen — with a live drawing of whichever surface you are pointing at, at the value you are setting
- 🪟 **Frosted glass / solid mode**, a standalone **blur behind every window** switch, and popup blur — with what the blur costs your GPU and CPU said at the top of the page rather than buried in a subtitle
- 🎚️ **Window transparency bar** — anywhere from 70% to 100%, with the three tuned levels marked
- 🎨 **Tint** — the colour under the glass, picked separately for app windows and for the shell or linked to one colour, with a preview window of real surfaces and real text that recolours as you drag
- 🌫️ **Blur amount** — one bar for every blurred surface at once, from a quarter of the tuned radii to double them
- 📋 **Two per-app blur lists** — the apps to blur and the apps never to, listed by the name each app calls itself with its window class underneath, each list in its own window and editable whichever one the current mode consults, from your installed apps or by wildcard pattern with the match explained as you type
- 🖱️ **Icon and pointer packs** — Hatter, Colloid or Reversal in a colour of their own rather than the accent's, AOSP, Adwaita or MacTahoe, plus **Default** (yours, left alone) and **Original**
- 🪟 **Titlebar buttons** — close alone, or all three
- 🧩 **Extensions** — every one this installs, with a switch each and install/remove, or fit the recommended or full pack in one click
- 📦 **Packages** — what each icon and pointer pack on disk costs you, and a button to remove the ones you stopped using: yours are deleted outright, and the ones your distribution installed name the package that owns them and hand it to your package manager in a terminal
- 🖥️ **System** — dependencies, the rounded-blur library, the multi-monitor panel fix, the login screen theme and its monitor layout sync
- 🔔 **Updates** — see your version, check for a new release, install it; on a branch you are testing it follows that branch's commits instead, and says so
- 🗑️ **Uninstall** — the same three scopes `uninstall.sh` has

Apply takes a few seconds and needs no password: under the hood it runs `./install.sh --settings-only`, which reapplies the dconf preset, the CSS and the gsettings and leaves the theme and extensions untouched. It stays off the network too, unless you pick an icon or pointer pack you have not downloaded yet — those two rows say so.

Some things do not wait for Apply, because they are not settings `install.sh` resolves: the extension switches apply as you click them, and removing a pack is a delete. And the steps that genuinely need root — the dependency install, the rounded-blur library, the login screen, the monitor sync, the uninstall scopes — **open a real terminal** rather than running `sudo` on your behalf out of a window that cannot show you the prompt. If none of the terminals it knows is installed, it hands you the command instead.

> The window is a front end for flags `install.sh` already has — nothing is exposed there that you cannot also script. It needs PyGObject and libadwaita; where those are missing the installer says so and skips it, and everything else installs as normal.
>
> One thing it deliberately does not offer is a custom accent **hex**. GNOME's `-st-accent-color` is a read-only keyword backed by a nine-value enum rather than something CSS can assign, so a custom colour would repaint every app window and none of the shell. Nine names it is.

### 4. Update Notifications
A `systemd --user` timer checks daily whether a newer release has been **tagged**, and notifies once per release — not once per day. Clicking the notification opens the settings window, where **Install** pulls the release and runs the full installer.

```bash
aura-glass-update-check      # check by hand, any time
./install.sh --no-update-check   # turn the daily check off (or use the switch in the window)
```

It asks the git remote for its tags — one request, no API token, no rate limit. It never fetches into your checkout and never installs anything on its own. Installing refuses outright if the checkout has uncommitted changes or is on a detached HEAD, and tells you which; a checkout whose history has diverged from the remote stops at `git pull --ff-only`'s own message rather than being merged or rewritten.

### 5. Testing a Branch
If you have been asked to try something before it is released, check that branch out and install from it as normal:

```bash
git clone https://github.com/DevWebeloper/aura-glass.git
cd aura-glass
git checkout feature/gui-post-install
./install.sh
```

From then on the daily check follows **that branch's commits** instead of release tags, because there are no tags on a branch being tested and the ones it can see belong to releases cut before it existed. The settings window says **Test build** and names the build `branch@commit`, and **Install** pulls the branch's new commits and re-runs the installer — the same button, pointed at the line you are actually on.

When the branch is merged and released, go back to the released line once and stay there:

```bash
git checkout main && git pull
```

Which line you are on is read from the checkout every time, so there is no setting to change and nothing to switch back.

### 6. Quick Update / Re-Apply
If you update your theme or GNOME packages later, re-apply the custom CSS fixes anytime with:
```bash
aura-glass-apply
```

---

## ✨ Features at a Glance

- 🪟 **Real Dynamic Frosted Glass** — True background blur behind the top bar, Quick Settings, app switcher, dialogs, notifications, and menus.
- 🎨 **Adaptive Accent Colors** — Full integration with GNOME's native accent system (`Settings → Appearance`). Toggles, sliders, focus rings, and icon variants update seamlessly.
- 🪟 **Optional App Window Blur** — Translucent, blurred backdrops for GTK4 and Electron/browser apps (e.g., VS Code, terminal).
- 🔊 **Minimalist Capsule OSD** — Distraction-free volume and brightness pill, blurring whatever wallpaper sits behind it.
- 🔒 **GDM Login Screen Theming** — Optional matching blurred login screen (`--gdm`).
- ⚡ **Lightweight "No Blur" Mode** — High-performance, opaque preset with the same sleek geometry for battery saving or low-power iGPUs.
- 📦 **Zero System Bloat** — Installs cleanly into `$HOME` (`~/.local/share/` and `~/.config/`). Uninstalls completely in one command.

---

## ⚙️ CLI Options & Non-Interactive Automation

For scripted setups or power users who prefer flags instead of the interactive wizard:

| Option | Description |
|---|---|
| `--interactive` | Force-launch the interactive setup wizard. |
| `--full` | Install everything at once (core theme, icons, cursors, OSD, panel blur fix, and all reference extensions). |
| `--accent COLOR` | Set accent: `blue`, `teal`, `green`, `yellow`, `orange`, `red`, `pink`, `purple`, `slate` *(default: `purple`, remembered across runs)*. |
| `--radius-preset P` | Corner rounding: `flat`, `sharp`, `soft`, `medium`, `default` or `rounded`. Moves windows, menus, dialogs, notifications **and** the blur radius behind each of them together *(default: `default`, remembered across runs)*. `pill` was retired and still resolves to `rounded`, so an older memo keeps installing. |
| `--settings-only` | Retune an existing install and nothing else — reapply the dconf preset, CSS and gsettings, leaving the theme and extensions alone. No root, and no network unless `--icons`/`--cursors`/`--font` ask for something you do not have. This is what `aura-glass-settings` runs. |
| `--no-gui` | Skip the `aura-glass-settings` window *(installed by default where PyGObject and libadwaita are present)*. |
| `--no-update-check` | Skip the daily update check. On `main` it asks the git remote for its tags and notifies once per release; on a branch you are testing it asks whether that branch has moved. Either way it never installs anything on its own. |
| `--app-blur-allow LIST` | Comma-separated `wm_class` patterns to blur in GTK/GNOME mode, replacing the shipped list. Wildcards allowed (`*chrome*`). Remembered across runs. |
| `--app-blur-block LIST` | Comma-separated `wm_class` patterns to exclude in all-apps mode. Remembered across runs. |
| `--app-transparency LEVEL` | Enable translucent app windows with blur: `90%` (balanced), `82%` (deep glass), `94%` (subtle glass), or custom percentage *(off by default)*. |
| `--app-tint-color HEX` | The colour a translucent app window is darkened toward under its opacity, e.g. `#101820`. How dark it stays is `--app-transparency`'s question; this is only what colour it is *(default `#000000`, remembered across runs)*. |
| `--shell-tint-color HEX` | The same for the panel, menus, Quick Settings, notifications and dialogs. Each shell surface keeps its own lightness and takes the colour's hue, so a tint cannot change how readable the text on it is *(default `#000000`, remembered across runs)*. |
| `--blur-strength P` | How far every blur reaches, as a percentage of the tuned radii: `25`–`200`. Scales the whole set together — panel, menus, overview, windows, lock screen — rather than flattening them *(default `100`, remembered across runs)*. |
| `--window-opacity LEVEL` | Alias for `--app-transparency` (e.g. `--window-opacity 90%`). |
| `--gdm` | Theme the GDM login screen with matching blurred style *(requires `sudo`)*. |
| `--gdm-background PATH` | Custom image for the GDM login background *(defaults to your wallpaper)*. |
| `--glass-mode M` | Pick the whole look in one flag: `frosted` (blur behind windows and popups, the default), `transparent` (translucent windows, no window blur) or `solid` (the theme stands down entirely). Remembered across runs, and each mode keeps its own opacity, tint, blur strength and popup blur *(see details below)*. |
| `--no-blur` | Opaque surfaces with identical geometry, still fully themed; saves ~30% GPU overhead for low-power laptops. Not the same as `--glass-mode solid` *(see details below)*. |
| `--extras` / `--recommended` | Install the recommended reference extension suite. |
| `--all-extras` | Install all 14 optional extensions. |
| `--minimal` / `--no-extras` | Minimal install with core look only (no optional extensions). |
| `--extensions LIST` | Comma-separated extension UUIDs to install instead of a pack, e.g. `space-bar@luchrioh,Vitals@CoreCoding.com`. Each must be one `--all-extras` would install; an empty list means the same as `--no-extras`. This is what the setup wizard's per-extension switches send. |
| `--icons WHICH` | Choose icon set: `colloid` (default, matches accent), `hatter` (the setup wizard's recommendation, also matches accent) or `reversal-COLOUR`. Each takes a colour of its own too: `colloid-teal`, `hatter-slate`. |
| `--cursors WHICH` | Choose pointer set: `adwaita` (default, ships with GNOME), `aosp` (the setup wizard's recommendation), `mactahoe`, or `original`. |
| `--font WHICH` | Interface font: `system` (default — GNOME's own font, left alone), `misans`, `inter` or `sf-pro`. The font is downloaded into `~/.local/share/fonts/aura-glass` if it is not already on the machine, then set as the interface, document and titlebar font at whatever size those keys already carry. `--font system` puts back the font from before aura-glass first ran here. Remembered across runs. |
| `--no-popup-blur` | Use flat translucent popups without background blur. |
| `--no-osd` | Keep GNOME's stock volume/brightness popup. |
| `--no-icons` / `--no-cursors` | Leave your icons or pointer alone — no pack installed and the `icon-theme` / `cursor-theme` key never written, so a choice made in GNOME Tweaks or anywhere else stands. Remembered across runs, so later runs leave it alone too. |
| `--dry-run`, `-n` | Print what would happen without modifying anything. |
| `--yes`, `-y` | Non-interactive mode (answers yes to all prompts). |

### Non-Interactive Command Examples

```bash
# 1. Full desktop with 90% frosted app windows
./install.sh --full --app-transparency 90%

# 2. Teal accent color with full extensions
./install.sh --full --accent teal

# 3. Battery-saving opaque theme (no blur, low GPU usage, styling intact)
./install.sh --full --no-blur

# 3b. Stand the theme down completely, keeping every setting for the way back
./install.sh --glass-mode solid -y

# 4. Apply GDM login screen theme
sudo ./install.sh --gdm

# 5. Sharper corners, without reinstalling anything else
./install.sh --settings-only --radius-preset sharp -y
```

---

## 🔬 In-Depth Details

### 1. Dynamic vs. Static Popup Blur
Menus, notifications, Quick Settings, Alt+Tab, and the OSD all render over real background blur.
- **Dynamic Blur (Default):** Blurs the actual active windows and content behind the popup. Powered by [`gnome-rounded-blur`][roundedblur] to give Blur My Shell's dynamic blur smooth rounded corners.
- **Static Blur:** Blurs the desktop wallpaper once. Used as an automatic fallback if `gnome-rounded-blur` is not built on your system.

### 2. App Window Transparency (`--app-transparency`)
Brings blurred frosted glass directly inside application windows:
- **`90%`** (Alpha 230) — Balanced frosted glass (recommended).
- **`82%`** (Alpha 210) — High translucency / deep glass.
- **`94%`** (Alpha 240) — Subtle glass / light translucency.

Applies across GTK4 native apps and Electron/Chromium windows (such as VS Code or Antigravity IDE). Dialogs and windows with server-side decorations are kept opaque to preserve readability.

### 3. The Three Glass Modes (`--glass-mode`)
One flag picks the whole look, and the choice is remembered, so a later flagless run comes back to it:
```bash
./install.sh --glass-mode frosted       # the default
./install.sh --glass-mode transparent
./install.sh --glass-mode solid -y
```
- **`frosted`** (default) — blur behind app windows and behind every popup. The full look described above.
- **`transparent`** — translucent windows with no blur behind them, so the wallpaper shows through directly. Popup blur stays on. Because there is no blurred window under the text, this mode starts darker (82%) rather than inheriting frosted's level.
- **`solid`** — the theme stands down rather than merely losing its blur: the stylesheets come back out, the shell and GTK themes go back to GNOME's stock ones, and this project's extensions are switched off **with their own settings left untouched**. Your icon and cursor packs and your accent colour stay, since those are your preferences and not this theme's styling. Nothing is uninstalled and nothing is forgotten — switching back to `frosted` or `transparent` restores exactly what was there.

Each mode keeps its own drawer of tuning — opacity, app and shell tint, blur strength, popup blur — so moving between them does not make you re-dial anything, and moving back returns the settings that mode was wearing.

Because `solid` removes the styling itself, it refuses flags that would have nothing left to act on: `--glass-mode solid --blur`, `--popup-blur`, `--window-blur` or a non-zero `--app-transparency` each stop the run rather than being silently discarded.

#### Battery & low-power mode (`--no-blur`)
Blur effects require continuous multi-pass Gaussian shader computations. If you are on battery or using an Intel/AMD iGPU:
```bash
./install.sh --full --no-blur
```
`--no-blur` drops GPU usage by **~30%** by disabling blur shaders completely while retaining every single radius, layout spacing, accent color, monochrome control, and capsule slider. This is the contrast to `solid`: a bare `--no-blur` is an **opaque but still themed** desktop, whereas `--glass-mode solid` is a desktop with the theme taken off it.

### 4. Minimalist Volume & Brightness OSD
Replaces stock GNOME's bulky OSD with a clean, compact pill. Configurable via **Extensions → Custom OSD → Settings**. GNOME 50 compatibility patches are applied automatically during installation.

### 5. Curated CSS Fixes & Architecture
`aura-glass` fixes dozens of unfinished styling quirks from upstream themes:
- Quick Settings sliders rendered as refined capsules instead of padded blocks.
- Real input metrics with visible borders and accent-colored focus rings.
- True push-buttons and dropdown styling across GTK apps.
- Calendar popups with inline notifications that don't punch visual holes.
- Flatpak overrides to ensure sandboxed apps inherit your custom theme.

---

## 🛠️ Project Structure

```
├── install.sh              # Main CLI entry point and orchestration
├── uninstall.sh            # Complete restoration & cleanup script
├── bin/
│   ├── aura-glass-apply    # Idempotent CSS patch & cascade re-apply script
│   ├── aura-glass-ext      # The extension catalogue, one extension at a time
│   ├── aura-glass-settings # Launcher for the settings window
│   └── aura-glass-update-check # Compares the local release tag — or, on a test branch, the local commit — against the remote
├── gui/                    # GTK4 / libadwaita windows (optional)
│   ├── aura_glass_settings.py     # Settings window, post-install
│   └── aura_glass_setup_wizard.py # Setup wizard, run by install.sh
├── css/                    # Modular CSS sheets applied in strict cascade order
│   ├── shell-NN-*.css      # GNOME Shell styling overrides
│   ├── gtk4-NN-*.css       # GTK4 & libadwaita overrides
│   └── gtk3-tweaks.css     # GTK3 overrides
├── dconf/                  # dconf presets (core, solid, extras)
├── lib/                    # Modular shell functions (distro, steps, GDM, assets)
├── patches/                # Upstream compatibility patches (GNOME 50, OpenBar, OSD)
├── tokens/                 # Design tokens (radii, sigmas, transparency) + radius presets
└── tools/                  # Developer testing, headless previews, & validation
```

---

## ❓ Troubleshooting

<details>
<summary><strong>Flatpak apps look like stock Adwaita</strong></summary>

Flatpak apps are sandboxed. The installer automatically grants them access to `~/.config/gtk-4.0` and `~/.local/share/themes`. If an app was already open during install, restart it. You can verify permissions with:
```bash
flatpak override --user --show
```
</details>

<details>
<summary><strong>Top bar has a mismatched strip on multi-monitor setups</strong></summary>

Blur My Shell clips to panel geometry before monitors fully register at login. A user service (`aura-glass-panel-blur.service`) rebuilds the panel blur once the desktop settles, and again on every monitor change. The installer enables it by default when the machine has more than one monitor — a single screen leaves it off. Force it either way with `--panel-blur-fix` / `--no-panel-blur-fix`, or from the settings window.
</details>

<details>
<summary><strong>Top bar font substitution</strong></summary>

The preset looks for `SF Pro Display Bold 10`. If SF Pro is not installed on your system, fontconfig falls back gracefully to your system sans-serif font. You can change this anytime in **Open Bar → Settings**.
</details>

<details>
<summary><strong>Popup blur shows wallpaper instead of background windows</strong></summary>

This means static fallback blur is active because `gnome-rounded-blur` is missing or needs a rebuild after a Mutter update. Rebuild it anytime with:
```bash
./install.sh --rounded-blur --force
```
</details>

---

## 🔄 Uninstall

To restore your original desktop configuration and remove all changes:

```bash
# Restore CSS, dconf settings, and systemd units
./uninstall.sh

# Complete uninstall (also removes installed extensions, themes, and icons)
./uninstall.sh --all
```

Backups of your previous settings are automatically stored in `~/.config/aura-glass/backups` (or `~/.config/tahoe-glass/backups`).

---

## 💖 Credits & Acknowledgments

This project is built on the incredible work of the open-source GNOME community. Huge thanks and credit to the upstream authors:

| Component | Project / Upstream | Author / Maintainer |
|---|---|---|
| **Theme Base** | [GNOME-macOS-Tahoe][tahoe] | [@kayozxo](https://github.com/kayozxo) |
| **Glass & Blur Engine** | [blur-my-shell][bms] | [@aunetx](https://github.com/aunetx) |
| **Top Bar & Geometry** | [openbar][ob] | [@neuromorph](https://github.com/neuromorph) |
| **Minimalist OSD** | [custom-osd][cosd] | [@neuromorph](https://github.com/neuromorph) |
| **Rounded Corner Clipping** | [gnome-rounded-blur][roundedblur] | [@kancko](https://github.com/kancko) |
| **Icons & Cursors** | [Colloid-icon-theme][colloid] & [MacTahoe-icon-theme][mactahoe] | [@vinceliuice](https://github.com/vinceliuice) |
| **Icons** | [Hatter][hatter] | [@Mibea](https://github.com/Mibea) |
| **Cursors** | [aosp-cursors][aosp] | [@Tech-Tac](https://github.com/Tech-Tac) |
| **Fonts** | [Inter][inter] (OFL) & [MiSans][misans] (Xiaomi's own licence) | [@rsms](https://github.com/rsms) / Xiaomi |
| **User Themes** | [User Themes][ut] | GNOME Extensions Team |

---

## 📄 License

The scripts, CSS patches, and integration tooling in this repository are released under the [MIT License](LICENSE).  
Upstream themes, extensions, and assets retain their respective original licenses.

`--font sf-pro` is the one thing here with no licence to point at. San Francisco is
Apple's, distributed under a licence that covers development for Apple platforms and
not a Linux desktop, and Apple publish no Linux build — so the font is fetched from a
[long-standing GitHub mirror][sfmirror] of the OTFs. Nothing about that makes it
licensed for this. It is offered because people ask for it and install it by hand
anyway; if that matters to you, `--font inter` and `--font misans` are both fonts
whose licences do allow this, and `--font system` installs no font at all.

[tahoe]: https://github.com/kayozxo/GNOME-macOS-Tahoe
[bms]: https://github.com/aunetx/blur-my-shell
[roundedblur]: https://github.com/kancko/gnome-rounded-blur
[ob]: https://github.com/neuromorph/openbar
[cosd]: https://github.com/neuromorph/custom-osd
[ut]: https://extensions.gnome.org/extension/19/user-themes/
[colloid]: https://github.com/vinceliuice/Colloid-icon-theme
[mactahoe]: https://github.com/vinceliuice/MacTahoe-icon-theme
[hatter]: https://github.com/Mibea/Hatter
[aosp]: https://github.com/Tech-Tac/aosp-cursors
[inter]: https://github.com/rsms/inter
[misans]: https://hyperos.mi.com/font/
[sfmirror]: https://github.com/sahibjotsaggu/San-Francisco-Pro-Fonts
