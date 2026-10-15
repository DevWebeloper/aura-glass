# Code-only blur lifecycle regressions

These tests do not use the running desktop or installed extensions.

```sh
python3 tests/check-performance.py
python3 tests/check-bms-patches.py /path/to/blur-my-shell-upstream-clone
```

The second check requires Python, Git, tar, Node.js, and an existing Blur My
Shell clone containing `BMS_REF` from `lib/steps.sh`. It archives that commit
into a temporary directory and applies all three Aura patches in installer
order. It never fetches or modifies the clone.

Production window selection, tracking, signal management, popup reset, and
effect lifecycle methods run against simulated GI actors, timers and GPU
pipelines. Rendering/geometry and native destruction semantics are not tested.
The checks cover:

- Bounded tracking during repeated full refreshes and sticky-window enumeration.
- Reuse of unchanged pipelines on whitelist, blacklist and scope edits.
- Necessary removal/creation when eligibility changes and rebuild on pipeline refresh.
- Meta.Window and static X11 callback cleanup.
- Cancellation of delayed blur enable after disable.
- Preservation of focused-window dynamic-opacity behavior after rebuild.
- Allow-list overrides in both scope modes.
- Popup toggles with notifications both on and off.
- Notification corner-effect fallback attachment/removal.
- Empty package-group placeholder rows.

The hook runs source-only checks and also runs the patched-source checks when
`BMS_TEST_SOURCE=/absolute/path/to/clone` is set.

No visual settings or defaults are changed. Desktop validation remains needed
on GNOME 50 and 51: repeated list edits, window closure, Overview, fullscreen,
sticky windows, static X11 applications, mixed scaling, popup toggles and
notification corners. Performance improvements in fixtures mean less redundant
work, not a measured FPS or GPU percentage improvement.
