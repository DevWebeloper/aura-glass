# Pull Request: Application Blur Overview Clones, Subwindows Inheritance & Multi-Monitor Panel Debounce

**Target Repository**: `aunetx/blur-my-shell`  
**Branch**: `master`  
**Patches Referenced**:
- [`patches/blur-my-shell-overview.patch`](../../patches/blur-my-shell-overview.patch)
- [`patches/blur-my-shell-subwindows.patch`](../../patches/blur-my-shell-subwindows.patch)
- [`patches/blur-my-shell-notifications.patch`](../../patches/blur-my-shell-notifications.patch)

---

## 1. Overview Preview Clone Fix (`src/components/applications.js`)

### Problem
Because the blur actor is attached as a child of the window actor, GNOME Shell's Overview clones the blur actor along with the window preview via `Clutter.Clone`. With clipped redraws enabled, the effect samples the framebuffer wherever it is painted, but only updates when damaged (such as when the pointer hovers over the preview). This leaves window previews showing frozen, misaligned patches of the desktop background until hovered.

### Solution
When `show_blur` evaluates to false (or when overview is visible and `BLUR_ON_OVERVIEW` is disabled):
- Set `blur_actor.opacity = 0` (preventing `Clutter.Clone` from painting the blur actor in overview previews).
- Disable pipeline effects (`pipeline.effects?.forEach(e => e.set_enabled(false))`) to conserve GPU cycles.

---

## 2. Dialog & Transient Subwindow Blur Inheritance (`src/components/applications.js`)

### Problem
Modal dialogs, file pickers, preferences windows, and tool palettes frequently have a different `wm_class` or do not yet have their transient relationship established at `window-created` time. This left child windows unblurred next to their blurred parent.

### Solution
- Connect to `notify::gtk-application-id` and `shown` signals on `MetaWindow` in addition to `window-created`.
- Resolve window identity across its `wm_class`, `gtk_application_id`, and its parent's transient-for chain (with cycle detection).

---

## 3. Multi-Monitor Panel Blur Layout Debounce (`src/components/panel.js`)

### Problem
When display topology changes (e.g. connecting an external display or waking monitors from sleep), `Main.layoutManager` emits multiple layout update signals in rapid succession. Querying actor coordinates during intermediate frames causes panel blur actors to render off-screen or with zero geometry until manually toggled.

### Solution
- Attach a debounced 250ms `GLib.timeout_add` handler to `Main.layoutManager.connect('monitors-changed', ...)` in `components/panel.js`.
- Clean up any pending timer IDs in `disable()` to prevent leaks.
