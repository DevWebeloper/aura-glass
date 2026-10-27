# Glass tab: three main sliders, per-surface overrides

## Why

The Frosted tab carried five sliders and eight switches. The user wants three
main sliders (blur amount, brightness, opacity) that move windows, popups and
notifications together, plus a collapsed Advanced area to tune each surface on
its own, without the tab feeling complicated or limited. Built on Blur My Shell
v76 (`fix/bms-v76`): one pipeline per surface, brightness clamped to 0–1,
notification blur following the popup blur.

## Decisions (the user's)

- Three main sliders. The main Blur amount keeps scaling every pipeline.
- Advanced surfaces: Windows; Popups & notifications (one v76 pipeline, one
  opacity); Top bar; Lock screen. Each has blur amount and brightness; Popups &
  notifications also has opacity.
- A surface tuned in Advanced keeps its value when the main slider moves, shows
  it is custom, and has a reset button that returns it to following the main.

## Decisions (the builder's call)

- Main brightness is a percentage of each pipeline's tuned brightness, the
  same unit Blur amount already uses. Every tuned value is 100% except the lock
  screen (80%) and the window list (60%), so the lock screen stays dimmer by
  the same proportion. Range 50–100: v76 clamps above 1.0.
- Per-surface blur amount and brightness use the same units and ranges as
  their main slider. Effective = core.ini baseline × (override or main).
- Main opacity is `--app-transparency`, unchanged. Popups & notifications
  follow it in proportion, as popups already do (`apply_popup_transparency`,
  base 0.90); the banner ground now follows too (40 at 0.90). The override,
  `--popup-opacity`, is in the main slider's units (70–100): "as if the windows
  were at P". Opaque windows (level 0) count as 100 for this.
- Memo value `main` means "follow the main slider". An absent memo is `main`.
- New memo names for the per-surface brightness (`window-blur-brightness`,
  `popup-blur-brightness`) so legacy memos can be read unambiguously: a legacy
  `window-brightness` of 100 or `popup-brightness` of 100/115 is `main`, any
  other legacy value is an override (clamped to 100).
- `--notification-opacity` is retired (accepted, warned, ignored): the banner
  ground follows the popup opacity. Its memo is not migrated.
- `--notification-blur` / `--no-notification-blur` are retired (accepted,
  warned, ignored): the banner sheet now follows `--popup-blur`.

## Flags

| Flag | Range | Memo |
|---|---|---|
| `--blur-strength P` (existing) | 25–200 | `blur-strength` |
| `--blur-brightness P` (new) | 50–100 | `blur-brightness` |
| `--app-transparency` (existing) | 70–100% | `app-transparency` |
| `--{window,popup,panel,lockscreen}-blur-strength P\|main` | 25–200 | same name |
| `--{window,popup}-brightness P\|main` (existing, range now 50–100) | 50–100 | `{window,popup}-blur-brightness` |
| `--{panel,lockscreen}-brightness P\|main` | 50–100 | `{panel,lockscreen}-blur-brightness` |
| `--popup-opacity P\|main` | 70–100 | `popup-opacity` |

All are frosted-drawer keys (`modes/frosted/<memo>`), resolved on the usual
precedence. One writer (`apply_blur_pipelines`, which replaces
`apply_blur_strength`, `apply_popup_brightness`, `apply_window_brightness` and
`tools/apply-popup-brightness.py`) rewrites every pipeline's radius and
brightness from core.ini baselines in one dconf write.

## Glass tab layout (Frosted)

1. Tint (unchanged).
2. Glass: Blur amount, Brightness, Opacity.
3. Where the blur reaches: a "Blur behind windows" dropdown (All apps / GTK
   apps only / Off), replacing two switches, and the popup blur switch, which
   now names notifications too.
4. Glass style (unchanged dropdown).
5. Advanced: collapsed expander rows for Windows, Popups & notifications, Top
   bar, Lock screen, and More (glass style behind app windows, fullscreen
   blur). A following slider tracks the main slider live; dragging it makes it
   custom, and a reset button appears.

Removed: "Translucent app windows" (the opacity slider's 100% covers it; an
install at level 0 shows 100% and sends nothing until moved) and "Blur behind
notifications (BETA)" (inert on v76).

The Performance tab is unchanged. Neither wizard asks about brightness or
per-surface values; the text wizard's summary drops its notification blur line.

## Non-goals

No change to tints, radius, the Per-app blur page or the Performance tab. No
separate notification blur pipeline.
