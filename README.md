# aura-glass

> **A fluid, modern frosted-glass desktop for GNOME.**  
> Seamless dynamic blur, macOS-inspired ergonomics, pixel-perfect CSS fixes, and unified system theming — installed with a single command without root (root only required for optional GDM theming).

```
GNOME Shell   48 · 49 · 50 (tested on 50.3)
Session       Wayland preferred (X11 supported with fallback blur)
Compatibility Arch / CachyOS, Fedora, Ubuntu / Debian
```

---

## 🧪 Beta: GUI Update

[**v0.2.1-beta**][beta] is out — the new settings window, three glass modes, the first-run wizard, and installable interface fonts. It is a prerelease: expect rough edges, and stick to the [latest stable release][releases] if you would rather not hit them.

```bash
git clone https://github.com/DevWebeloper/aura-glass.git
cd aura-glass
git checkout v0.2.1-beta
./install.sh
```

[beta]: https://github.com/DevWebeloper/aura-glass/releases/tag/v0.2.1-beta
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

Running `./install.sh` launches an **interactive setup wizard** that lets you easily pick your preferences directly in your terminal:
- 🎨 **Accent color** (Purple, Blue, Teal, Green, Yellow, Orange, Red, Pink, Slate)
- 🪟 **Blur & visual depth** (Frosted Glass vs. Lightweight Solid Mode)
- 💎 **App window transparency** (Off, 90% balanced, 82% deep, 94% subtle)
- 🧩 **Extension packages** (Recommended, Full, or Minimal)
- 🔒 **GDM login screen theme** (Optional matching blurred login screen)

> **Tip:** Prefer a dry run first? Run `./install.sh --dry-run` to preview all changes safely without modifying your system.

### 2. Log Out & Back In
GNOME Shell extensions and compositor settings take effect on the next session. Simply **log out and log back in** to enjoy your customized glass desktop!

### 3. Quick Update / Re-Apply
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
| `--app-transparency LEVEL` | Enable translucent app windows with blur: `90%` (balanced), `82%` (deep glass), `94%` (subtle glass), or custom percentage *(off by default)*. |
| `--window-opacity LEVEL` | Alias for `--app-transparency` (e.g. `--window-opacity 90%`). |
| `--gdm` | Theme the GDM login screen with matching blurred style *(requires `sudo`)*. |
| `--gdm-background PATH` | Custom image for the GDM login background *(defaults to your wallpaper)*. |
| `--no-blur` | Solid opaque surfaces with identical geometry; saves ~30% GPU overhead for low-power laptops *(see details below)*. |
| `--extras` / `--recommended` | Install the recommended reference extension suite. |
| `--all-extras` | Install all 14 optional extensions. |
| `--minimal` / `--no-extras` | Minimal install with core look only (no optional extensions). |
| `--icons WHICH` | Choose icon set: `colloid` (default, matches accent) or `reversal-COLOUR`. |
| `--no-popup-blur` | Use flat translucent popups without background blur. |
| `--no-osd` | Keep GNOME's stock volume/brightness popup. |
| `--no-icons` / `--no-cursors` | Keep your existing icons or cursor theme. |
| `--dry-run`, `-n` | Print what would happen without modifying anything. |
| `--yes`, `-y` | Non-interactive mode (answers yes to all prompts). |

### Non-Interactive Command Examples

```bash
# 1. Full desktop with 90% frosted app windows
./install.sh --full --app-transparency 90%

# 2. Teal accent color with full extensions
./install.sh --full --accent teal

# 3. Battery-saving solid mode (no blur, low GPU usage)
./install.sh --full --no-blur

# 4. Apply GDM login screen theme
sudo ./install.sh --gdm
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

### 3. Battery & Low-Power Mode (`--no-blur`)
Blur effects require continuous multi-pass Gaussian shader computations. If you are on battery or using an Intel/AMD iGPU:
```bash
./install.sh --full --no-blur
```
`--no-blur` drops GPU usage by **~30%** by disabling blur shaders completely while retaining every single radius, layout spacing, accent color, monochrome control, and capsule slider.

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
│   └── aura-glass-apply    # Idempotent CSS patch & cascade re-apply script
├── css/                    # Modular CSS sheets applied in strict cascade order
│   ├── shell-NN-*.css      # GNOME Shell styling overrides
│   ├── gtk4-NN-*.css       # GTK4 & libadwaita overrides
│   └── gtk3-tweaks.css     # GTK3 overrides
├── dconf/                  # dconf presets (core, solid, extras)
├── lib/                    # Modular shell functions (distro, steps, GDM, assets)
├── patches/                # Upstream compatibility patches (GNOME 50, OpenBar, OSD)
├── tokens/                 # Design tokens (radii, colors, padding)
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

Blur My Shell clips to panel geometry before monitors fully register at login. The installer enables a startup service (`aura-glass-panel-blur.service`) that automatically refreshes the panel blur once the desktop settles.
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
| **User Themes** | [User Themes][ut] | GNOME Extensions Team |

---

## 📄 License

The scripts, CSS patches, and integration tooling in this repository are released under the [MIT License](LICENSE).  
Upstream themes, extensions, and assets retain their respective original licenses.

[tahoe]: https://github.com/kayozxo/GNOME-macOS-Tahoe
[bms]: https://github.com/aunetx/blur-my-shell
[roundedblur]: https://github.com/kancko/gnome-rounded-blur
[ob]: https://github.com/neuromorph/openbar
[cosd]: https://github.com/neuromorph/custom-osd
[ut]: https://extensions.gnome.org/extension/19/user-themes/
[colloid]: https://github.com/vinceliuice/Colloid-icon-theme
[mactahoe]: https://github.com/vinceliuice/MacTahoe-icon-theme
