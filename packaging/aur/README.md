# AUR Submission & Maintenance Guide for `aura-glass-git`

This directory contains the packaging files to submit and maintain **Aura Glass** as an official Arch User Repository (AUR) package (`aura-glass-git`).

## Files
- `PKGBUILD`: Package recipe defining sources, dependencies, and file layout.
- `.SRCINFO`: Package metadata consumed by AUR helpers (`yay`, `paru`).
- `aura-glass.install`: Post-install and post-upgrade hints for users.

---

## Initial AUR Submission

1. **Prerequisites**: Ensure you have an active AUR account with an uploaded SSH key.
2. **Clone the empty AUR repository**:
   ```bash
   git clone ssh://aur@aur.archlinux.org/aura-glass-git.git /tmp/aura-glass-git
   ```
3. **Copy the package files**:
   ```bash
   cp packaging/aur/PKGBUILD /tmp/aura-glass-git/
   cp packaging/aur/aura-glass.install /tmp/aura-glass-git/
   ```
4. **Regenerate `.SRCINFO` and test build**:
   ```bash
   cd /tmp/aura-glass-git
   makepkg --printsrcinfo > .SRCINFO
   makepkg -si
   ```
5. **Commit and push**:
   ```bash
   git add PKGBUILD .SRCINFO aura-glass.install
   git commit -m "Initial commit for aura-glass-git"
   git push origin master
   ```

---

## User Installation

Once published, any Arch Linux, CachyOS, EndeavourOS, or Manjaro user can install and receive rolling updates:

```bash
yay -S aura-glass-git
# or
paru -S aura-glass-git
```

Updates are automatically pulled during routine system updates (`yay -Syu`).
