# 🪟 Aura Glass

> **A fluid, frosted-glass desktop for GNOME 48–51.**  
> Real dynamic background blur, macOS-inspired ergonomics, adaptive accent integration, and unified system theming — installed in seconds without root.

---

## ⚡ Quick Start

### 1. Install
Clone the repository and run the installer:

```bash
git clone https://github.com/DevWebeloper/aura-glass.git
cd aura-glass
./install.sh
```

A clean, graphical setup wizard will guide you through:
- 🎨 **Accent Color** — Matches GNOME native accents (Purple, Blue, Teal, Green, etc.)
- 🪟 **Glass Mode** — Frosted Glass (blur) vs. Lightweight Solid (low GPU)
- 💎 **Translucency & Tint** — Dial in your preferred window glass opacity
- 🖱️ **Icons & Cursors** — Choose between Colloid, Reversal, MacTahoe, or Neon pointers
- 🔒 **Login Screen (GDM)** — Optional blurred login screen with live wallpaper sync

> **Non-interactive / Fast Install:**  
> Run `./install.sh --full -y` to install the complete recommended experience with a single command.

### 2. Apply
Simply **log out and log back in** to enjoy your new frosted-glass desktop!

---

## ✨ Features

- 🌫️ **Real Dynamic Blur** — Seamless background blur behind the top bar, Quick Settings, menus, notifications, dialogs, and application windows.
- 🎛️ **Dedicated Settings App** — Open **Aura Glass Settings** from your app grid to adjust corner rounding, glass tint, window opacity, and toggle per-app blur in real time.
- ⚡ **Adaptive Performance Mode** — An intelligent top-bar profile switcher (**Auto / Glass / Performance**) that automatically reduces blur overhead during fullscreen gaming, heavy GPU loads (≥80%), or battery discharge.
- 🔊 **Capsule OSD** — Sleek, compact pill for volume and brightness that floats over wallpaper blur.
- 🖼️ **Dynamic GDM Wallpaper Sync** — The login screen automatically adapts and blurs whenever your desktop wallpaper changes.
- 📦 **Zero System Bloat** — Assets install strictly in `$HOME` (`~/.local/` and `~/.config/`). Undo everything cleanly at any time with `./uninstall.sh`.

---

## 🐧 Distro Compatibility

Aura Glass works out of the box across major Linux distributions running GNOME Shell 48 to 51:

| Distribution | Package Manager / Installation Method |
|---|---|
| **Arch / CachyOS / EndeavourOS** | `./install.sh` or via AUR: `yay -S aura-glass-git` |
| **Fedora 40+** | `./install.sh` (automatic `dnf`/`dnf5` dependencies) |
| **Ubuntu 24.04+ / Debian 13+** | `./install.sh` (automatic `apt` dependencies) |
| **openSUSE Tumbleweed / Leap** | `./install.sh` (automatic `zypper` dependencies) |

---

## 🛠️ Handy Commands

```bash
# Re-apply CSS & dconf after updates or theme tweaks (instant, offline)
aura-glass-apply

# Re-tune an existing install without redownloading assets
./install.sh --settings-only -y

# Check for updates
aura-glass-update-check

# Battery saver / low-spec mode (themed, but zero blur GPU overhead)
./install.sh --full --no-blur -y

# Completely remove Aura Glass and restore system defaults
./uninstall.sh
```

---

## 🤝 Contributing & Documentation

- [Architecture & Design Guide](docs/ARCHITECTURE.md)
- [Contributing Guidelines](CONTRIBUTING.md)
- [AUR Packaging Guide](packaging/aur/README.md)

---

## 📄 License

GPL-3.0-or-later © [DevWebeloper](https://github.com/DevWebeloper)
