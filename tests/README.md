# Code-only Blur My Shell patch checks

These tests do not use the running desktop or installed extensions.

```sh
python3 tests/check-performance.py
python3 tests/check-bms-patches.py /path/to/blur-my-shell-upstream-clone
```

The second check requires Python, Git, tar, Node.js, and an existing Blur My
Shell clone containing `BMS_REF` from `lib/steps.sh`. It archives that commit
into a temporary directory and applies `patches/blur-my-shell-subwindows.patch`.
It never fetches or modifies the clone.

The patched `components/applications/window_rules.js` runs against simulated
Meta windows. The checks cover:

- Attached dialogs and utility palettes matched through their transient-for app.
- The GTK application id matched when the wm_class is empty.
- The allow list winning over the block list in all mode.
- Blocked apps staying unblurred, dialogs included, and menus never blurred.
- A transient-for loop ending.

Five of the seven fail against unpatched v76. The first check covers the empty
package-group placeholder rows. The v73 lifecycle tests (window tracking,
popup toggles, notification corners) went with the patches v76 made
unnecessary.

The hook runs source-only checks and also runs the patched-source checks when
`BMS_TEST_SOURCE=/absolute/path/to/clone` is set.

Desktop validation remains needed: a real dialog, file chooser and tool
palette of a blurred app on GNOME 51.
