# Code-only Blur My Shell patch checks

These tests do not use the running desktop or installed extensions.

```sh
python3 tests/check-performance.py
python3 tests/check-bms-patches.py /path/to/blur-my-shell-upstream-clone
```

The second check requires Python, Git, tar, Node.js, and an existing Blur My
Shell clone containing `BMS_REF` from `lib/steps.sh`. It archives that commit
into a temporary directory and applies
`patches/blur-my-shell-upstream-backports.patch`, then
`patches/blur-my-shell-subwindows.patch`, then
`patches/blur-my-shell-full-size-buffers.patch`,
`patches/blur-my-shell-overview-fade.patch` and
`patches/blur-my-shell-static-maximized.patch`. It never fetches or
modifies the clone.

The patched `components/applications/window_rules.js` runs against simulated
Meta windows. The checks cover:

- Attached dialogs and utility palettes matched through their transient-for app.
- The GTK application id matched when the wm_class is empty.
- The allow list winning over the block list in all mode.
- Blocked apps staying unblurred, dialogs included, and menus never blurred.
- A transient-for loop ending.
- `title:` entries matching the window title and not its class, up the
  transient-for chain as class entries do, the allow list still winning over a
  title on the block list, and class entries still reaching the chain beside
  them.

The patched `render/shader/texture_region.js` runs with `full-size-buffers` off
(exact first size, 1.25x growth, shrink below half) and on (largest monitor
first, never shrinks).

The patched `components/applications/index.js` runs with its real
`window_opacity.js`, `window_geometry.js`, `window_rules.js` and
`connections.js` over fake actors, windows and an overview, with `ease()` under
the test's control. The checks cover:

- The type decision: maximized both ways, fullscreen and sized over the work
  area are static, one-way maximized and half-tiled are dynamic,
  `static-blur=true` makes every window static, and a window on no monitor reads
  no work area.
- Crossing either way on a maximize, a fullscreen, a resize or a move, once each,
  with the old pipeline released, no handlers piling up, and the new type's
  signals connected. No rebuild while the type stays.
- An interactive resize waits for its end however often it crosses, where a move
  grab does not (dragging a maximized window free).
- The window entering another monitor, and the X11 stacking fix following the
  type of the blur.
- A crossing during the overview fade or a touchpad swipe, app to overview and
  overview to app: it waits, the fade or the following goes on, and it lands where
  the overview settles with the blur shown or hidden as it should be and the content
  at the right opacity. A rebuild forced in the middle of a fade, as a static window
  changing monitor does, leaves nothing stuck either.

Five of the seven fail against unpatched v76. The first check covers the empty
package-group placeholder rows. The v73 lifecycle tests (window tracking,
popup toggles, notification corners) went with the patches v76 made
unnecessary.

The hook runs source-only checks and also runs the patched-source checks when
`BMS_TEST_SOURCE=/absolute/path/to/clone` is set.

Desktop validation remains needed: a real dialog, file chooser and tool
palette of a blurred app on GNOME 51, and for static-maximized a real maximize,
drag-to-top and edge resize, in and out of the overview, with the signals in
Mutter's own order.
